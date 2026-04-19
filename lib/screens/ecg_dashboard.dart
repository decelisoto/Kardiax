// lib/screens/ecg_dashboard.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kardiax/services/real_ble_service.dart';
import '../services/ble_service.dart';
import '../services/export_service.dart';
import '../services/mock_ble_service.dart';
import '../services/heartbeat_service.dart';
import '../services/offline_queue_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/ecg_painter.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'debug_screen.dart';
import 'circle_screen.dart';
import 'invites_inbox_screen.dart';
import 'alert_history_screen.dart';

class EcgDashboard extends StatefulWidget {
  /// Pass an already-connected [BleService] from [BleConnectScreen] to skip
  /// the connect call. If null, the dashboard creates and connects its own.
  final BleService? bleService;
  const EcgDashboard({super.key, this.bleService});

  @override
  State<EcgDashboard> createState() => _EcgDashboardState();
}

class _EcgDashboardState extends State<EcgDashboard>
    with TickerProviderStateMixin {
  late final BleService _ble;

  final _heartbeat = HeartbeatService();
  final _offlineQueue = OfflineQueueService();
  final _exportService = ExportService();

  // Waveform buffer — 500 samples ≈ 5s
  final List<double> _waveform = List.filled(500, 0.5, growable: true);
  BleStatus _status = BleStatus.disconnected;
  bool _isArrhythmia = false;
  int _heartRate = 72;
  double _signalQuality = 1.0;
  double _batteryLevel = 0.87;
  String _arrhythmiaLabel = 'Normal sinus';
  double _arrhythmiaConfidence = 0.97;
  Duration _recordingDuration = Duration.zero;

  // ── Sustained-detection ──────────────────────────────────────────────────
  // Each detection window is ~375 ms (90 samples × 25 ms / 6 samples).
  // 24 consecutive positive windows ≈ 9 seconds of sustained arrhythmia
  // before the alarm fires, preventing single-window noise spikes.
  int _arrhythmiaWindowCount = 0;
  static const int _sustainedWindows = 24;

  // ── Exponential backoff ──────────────────────────────────────────────────
  // After a cancellation the backoff doubles (30 → 60 → 120 → 240 → 300 s).
  // After 30 minutes of no cancellations the count resets to 0.
  int _falsePositiveCount = 0;
  DateTime? _lastCancelTime;
  DateTime? _lastAlarmFiredAt;

  int get _backoffSeconds {
    if (_falsePositiveCount == 0) return 0;
    final s = 30 * (1 << (_falsePositiveCount - 1)); // 30, 60, 120, 240 …
    return s.clamp(0, 300);
  }

  // Alarm state
  bool _showAlarm = false;
  int _countdown = 30;
  Timer? _countdownTimer;
  Timer? _recordingTimer;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _alarmController;
  late Animation<double> _pulseAnim;
  late Animation<double> _alarmAnim;

  StreamSubscription? _ecgSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _packetSub;

  double _lastRrMs = 800.0;

  @override
  void initState() {
    super.initState();
    _ble = widget.bleService ?? RealBleService();
    UserProfileService.ensureProfile();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _alarmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
    _alarmAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _alarmController, curve: Curves.easeInOut),
    );

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == BleStatus.connected) {
        setState(() => _recordingDuration += const Duration(seconds: 1));
      }
    });

    _heartbeat.start();
    _offlineQueue.start();
    _connect();
    final ble = _ble;
    if (ble is RealBleService) {
      _exportService.startRecording(ble.packetStream);
    }
  }

  Future<void> _connect() async {
    // Seed from currentStatus, but don't let that snapshot overwrite a newer
    // status event if one arrives while subscriptions are being set up.
    final seededStatus = _ble.currentStatus;
    var receivedStatusEvent = false;

    _statusSub = _ble.statusStream.listen((s) {
      receivedStatusEvent = true;
      if (kDebugMode) {
        debugPrint('EcgDashboard status listener -> $s');
      }
      setState(() => _status = s);
      _heartbeat.setConnected(s == BleStatus.connected);
    });

    if (!receivedStatusEvent && _status != seededStatus) {
      setState(() => _status = seededStatus);
    }
    if (kDebugMode) {
      debugPrint('EcgDashboard _connect() seeded status=$_status');
    }
    _heartbeat.setConnected(_status == BleStatus.connected);

    // ecgStream carries synthetic ECG samples — used only for waveform display.
    _ecgSub = _ble.ecgStream.listen((samples) {
      setState(() {
        for (final raw in samples) {
          _waveform.add(raw / 4095.0);
          if (_waveform.length > 500) _waveform.removeAt(0);
        }
      });
    });

    // packetStream carries beat-by-beat HR + RR from the Arduino.
    // Arrhythmia detection uses RR-interval variability (>20% beat-to-beat
    // deviation), which is meaningful for the processed data the Arduino sends.
    final ble = _ble;
    if (ble is RealBleService) {
      _packetSub = ble.packetStream.listen((pkt) {
        if (!mounted || pkt.isLeadsOff || pkt.isStatusOnly) return;

        bool shouldTrigger = false;
        bool shouldResolve = false;

        setState(() {
          _heartRate = pkt.hrBpm;

          final rrDeviation = (pkt.rrMs - _lastRrMs).abs();
          _lastRrMs = pkt.rrMs;

          final wasArrhythmia = _isArrhythmia;
          _isArrhythmia = rrDeviation > (_lastRrMs * 0.20);

          if (_isArrhythmia) {
            _arrhythmiaWindowCount++;
            _arrhythmiaLabel = 'Irregular rhythm';
            _arrhythmiaConfidence =
                (0.70 + rrDeviation / 1000.0).clamp(0.70, 0.99);
            _signalQuality = 0.62;
          } else {
            _arrhythmiaWindowCount = 0;
            _arrhythmiaLabel = 'Normal sinus';
            _arrhythmiaConfidence = 0.97;
            _signalQuality = 0.94;
          }

          if (_isArrhythmia &&
              _arrhythmiaWindowCount == _sustainedWindows &&
              !_showAlarm) {
            shouldTrigger = true;
          }
          if (!_isArrhythmia && wasArrhythmia) shouldResolve = true;
        });

        _heartbeat.updateEcgStats(
          heartRate: _heartRate,
          isArrhythmia: _isArrhythmia,
          arrhythmiaLabel: _arrhythmiaLabel,
        );

        if (shouldTrigger) _triggerAlarm();
        if (shouldResolve) _resolveAlarm();
      });
    }

    // Skip connect() if a pre-connected service was passed in.
    if (widget.bleService == null) await _ble.connect();
  }

  void _triggerAlarm() {
    // Reset backoff counter if it's been quiet for 30 minutes.
    if (_lastCancelTime != null &&
        DateTime.now().difference(_lastCancelTime!) >
            const Duration(minutes: 30)) {
      _falsePositiveCount = 0;
      _lastCancelTime = null;
    }

    // Rate-limit: refuse to fire again within the backoff window.
    if (_lastAlarmFiredAt != null && _backoffSeconds > 0) {
      final elapsed =
          DateTime.now().difference(_lastAlarmFiredAt!).inSeconds;
      if (elapsed < _backoffSeconds) return;
    }

    _lastAlarmFiredAt = DateTime.now();
    HapticFeedback.heavyImpact();
    setState(() {
      _showAlarm = true;
      _countdown = 30;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _countdown--);
      HapticFeedback.lightImpact();
      if (_countdown <= 0) {
        t.cancel();
        _fireCircleAlert();
      }
    });
  }

  void _cancelAlarm() {
    HapticFeedback.mediumImpact();
    _countdownTimer?.cancel();

    _falsePositiveCount++;
    _lastCancelTime = DateTime.now();

    setState(() {
      _showAlarm = false;
      _countdown = 30;
    });

    _logAlert(cancelled: true);

    final wait = _backoffSeconds;
    final msg = wait > 0
        ? 'Alert cancelled — next alarm blocked for ${wait}s'
        : 'Alert cancelled — logged as false positive';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Oswald')),
        backgroundColor: KardiaxColors.card,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _resolveAlarm() {
    _countdownTimer?.cancel();
    setState(() {
      _showAlarm = false;
      _countdown = 30;
    });
  }

  Future<void> _fireCircleAlert() async {
    setState(() => _showAlarm = false);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final alertPayload = {
      'type': _arrhythmiaLabel,
      'confidence': _arrhythmiaConfidence,
      'hr': _heartRate,
      'circleNotified': true,
      'cancelled': false,
      'patientName':
          FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown',
    };

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline =
        connectivity.any((r) => r != ConnectivityResult.none);

    if (isOnline) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts')
          .add({
        ...alertPayload,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Circle notified',
                style: TextStyle(fontFamily: 'Oswald')),
            backgroundColor: KardiaxColors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      await _offlineQueue.enqueue(alertPayload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'No internet — alert queued, will send when online',
                style: TextStyle(fontFamily: 'Oswald')),
            backgroundColor: KardiaxColors.amber,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _logAlert({required bool cancelled}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('alerts')
        .add({
      'type': _arrhythmiaLabel,
      'confidence': _arrhythmiaConfidence,
      'hr': _heartRate,
      'cancelled': cancelled,
      'circleNotified': !cancelled,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _debugSetArrhythmia(bool on) {
    if (_ble is MockBleService) _ble.forceArrhythmia(on);
  }

  void _debugSetRhythm(String label, double confidence) => setState(() {
        _arrhythmiaLabel = label;
        _arrhythmiaConfidence = confidence;
      });

  void _debugSetHR(int hr) => setState(() => _heartRate = hr);
  void _debugSetSQ(double sq) => setState(() => _signalQuality = sq);
  void _debugSetBattery(double level) => setState(() => _batteryLevel = level);
  void _debugExitMode() {}

  String get _patientName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown Patient';

  Future<void> _showExportOptions() async {
    if (_exportService.isEmpty) {
      _showSnackBar('No data recorded yet');
      return;
    }

    final selection = await showModalBottomSheet<_ExportFormat>(
      context: context,
      backgroundColor: KardiaxColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Export ECG',
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: KardiaxColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a format to generate and share.',
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 13,
                  color: KardiaxColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              _ExportOptionTile(
                icon: Icons.table_chart_outlined,
                title: 'Export CSV',
                subtitle: 'Raw beat log for spreadsheets or analysis',
                onTap: () => Navigator.of(sheetContext).pop(_ExportFormat.csv),
              ),
              const SizedBox(height: 10),
              _ExportOptionTile(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Export PDF',
                subtitle: 'Branded report with summary and beat table',
                onTap: () => Navigator.of(sheetContext).pop(_ExportFormat.pdf),
              ),
            ],
          ),
        ),
      ),
    );

    if (selection == null || !mounted) return;
    await _runExport(selection);
  }

  Future<void> _runExport(_ExportFormat format) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: KardiaxColors.red),
      ),
    );

    String? filePath;
    String? errorMessage;

    try {
      filePath = switch (format) {
        _ExportFormat.csv => await _exportService.exportCsv(_patientName),
        _ExportFormat.pdf => await _exportService.exportPdf(_patientName),
      };
    } on StateError catch (error) {
      errorMessage = error.message.toString();
    } catch (error) {
      errorMessage = 'Export failed: $error';
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;

    if (errorMessage != null) {
      _showSnackBar(errorMessage);
      return;
    }

    if (filePath != null) {
      await _exportService.shareFile(filePath);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Oswald'),
        ),
        backgroundColor: KardiaxColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Color get _rhythmColor {
    if (_isArrhythmia) return KardiaxColors.red;
    if (_signalQuality < 0.7) return KardiaxColors.amber;
    return KardiaxColors.green;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _alarmController.dispose();
    _ecgSub?.cancel();
    _statusSub?.cancel();
    _packetSub?.cancel();
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _heartbeat.dispose();
    _offlineQueue.dispose();
    _exportService.stopRecording();
    if (widget.bleService == null) {
      _ble.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmall = size.height < 700;

    return Scaffold(
      backgroundColor: KardiaxColors.black,
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                _buildStatusStrip(),
                _buildMetricsRow(isSmall),
                Expanded(child: _buildWaveform()),
                _buildRhythmBar(isSmall),
                SizedBox(height: isSmall ? 8 : 16),
              ],
            ),
          ),
          if (_showAlarm) _buildAlarmOverlay(context),
        ],
      ),
    );
  }

  // ── Top bar ──
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => GestureDetector(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KardiaxColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: KardiaxColors.gray.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.menu,
                    color: KardiaxColors.textPrimary, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Kardia',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.textPrimary,
                    letterSpacing: 1.5,
                  ),
                ),
                TextSpan(
                  text: 'x',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.red,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _BatteryIndicator(level: _batteryLevel),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: KardiaxColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: KardiaxColors.gray.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _status == BleStatus.connected
                        ? KardiaxColors.red
                        : KardiaxColors.gray,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDuration(_recordingDuration),
                  style: const TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── BLE status strip ──
  Widget _buildStatusStrip() {
    final (label, color, icon) = switch (_status) {
      BleStatus.connected => (
        'Connected',
        KardiaxColors.green,
        Icons.bluetooth_connected,
      ),
      BleStatus.connecting => (
        'Connecting...',
        KardiaxColors.amber,
        Icons.bluetooth_searching,
      ),
      BleStatus.scanning => (
        'Scanning...',
        KardiaxColors.amber,
        Icons.bluetooth_searching,
      ),
      BleStatus.lost => (
        'Signal lost — reconnecting',
        KardiaxColors.red,
        Icons.bluetooth_disabled,
      ),
      BleStatus.disconnected => (
        'Disconnected',
        KardiaxColors.gray,
        Icons.bluetooth_disabled,
      ),
      BleStatus.leadsOff => (
        'Leads off — check electrodes',
        KardiaxColors.red,
        Icons.sensors_off,
      ),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Oswald',
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          _SignalQualityBar(quality: _signalQuality),
        ],
      ),
    );
  }

  // ── Metrics row ──
  Widget _buildMetricsRow(bool isSmall) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: _MetricCard(
              label: 'HEART RATE',
              value: '$_heartRate',
              unit: 'bpm',
              color: _isArrhythmia
                  ? KardiaxColors.red
                  : KardiaxColors.green,
              isSmall: isSmall,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCard(
              label: 'RHYTHM',
              value: _isArrhythmia ? 'Irregular' : 'Normal',
              unit: '',
              color: _rhythmColor,
              isSmall: isSmall,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCard(
              label: 'CONFIDENCE',
              value:
                  '${(_arrhythmiaConfidence * 100).toInt()}',
              unit: '%',
              color: KardiaxColors.textSecondary,
              isSmall: isSmall,
            ),
          ),
        ],
      ),
    );
  }

  // ── ECG Waveform ──
  Widget _buildWaveform() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isArrhythmia
                ? KardiaxColors.red.withValues(alpha: 0.5)
                : KardiaxColors.gray.withValues(alpha: 0.15),
            width: _isArrhythmia ? 1.5 : 0.5,
          ),
          boxShadow: _isArrhythmia
              ? [
                  BoxShadow(
                    color: KardiaxColors.redGlow,
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CustomPaint(
            painter: EcgPainter(
              samples: List.from(_waveform),
              isArrhythmia: _isArrhythmia,
              waveColor: KardiaxColors.green,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  // ── Rhythm bar ──
  Widget _buildRhythmBar(bool isSmall) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: isSmall ? 10 : 14),
        decoration: BoxDecoration(
          color: _rhythmColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: _rhythmColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, _) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color:
                      _rhythmColor.withValues(alpha: _pulseAnim.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _rhythmColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _arrhythmiaLabel,
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      color: _rhythmColor,
                      fontSize: isSmall ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${(_arrhythmiaConfidence * 100).toInt()}% confidence',
                    style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _showExportOptions,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: KardiaxColors.input,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: KardiaxColors.gray.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_outlined,
                        color: KardiaxColors.textSecondary,
                        size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Export',
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Alarm overlay ──
  Widget _buildAlarmOverlay(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _alarmAnim,
      builder: (_, _) => Container(
        width: size.width,
        height: size.height,
        color: KardiaxColors.red.withValues(alpha: _alarmAnim.value * 0.15),
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(
                horizontal: size.width * 0.08),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: KardiaxColors.red.withValues(alpha: 0.7),
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: KardiaxColors.red.withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ARRHYTHMIA DETECTED',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _arrhythmiaLabel,
                  style: const TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                if (_backoffSeconds > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Backoff active — was suppressed for ${_backoffSeconds}s',
                    style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.amber,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: _countdown / 30.0,
                          strokeWidth: 4,
                          backgroundColor: KardiaxColors.input,
                          valueColor: AlwaysStoppedAnimation(
                              KardiaxColors.red),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_countdown',
                            style: const TextStyle(
                              fontFamily: 'Oswald',
                              color: KardiaxColors.textPrimary,
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'sec',
                            style: TextStyle(
                              fontFamily: 'Oswald',
                              color: KardiaxColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Circle will be notified',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _cancelAlarm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KardiaxColors.green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "I'M OK — CANCEL ALERT",
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Drawer ──
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Kardia',
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: KardiaxColors.textPrimary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    TextSpan(
                      text: 'x',
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: KardiaxColors.red,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(color: KardiaxColors.input, height: 1),
            const SizedBox(height: 8),
            _DrawerItem(
                icon: Icons.monitor_heart_outlined,
                label: 'Live ECG',
                selected: true),
            _DrawerItem(
              icon: Icons.history,
              label: 'Alert history',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AlertHistoryScreen()),
              ),
            ),
            _DrawerItem(
              icon: Icons.people_outline,
              label: 'My circle',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CircleScreen()),
              ),
            ),
            _DrawerItem(
              icon: Icons.mail_outline,
              label: 'Invites',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const InvitesInboxScreen()),
              ),
            ),
            _DrawerItem(
              icon: Icons.download_outlined,
              label: 'Export ECG',
              onTap: _showExportOptions,
            ),
            _DrawerItem(
                icon: Icons.bluetooth_outlined, label: 'Device'),
            _DrawerItem(
              icon: Icons.bug_report_outlined,
              label: 'Debug panel',
              color: KardiaxColors.amber,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DebugScreen(
                    onArrhythmiaToggle: _debugSetArrhythmia,
                    onTriggerAlarm: _triggerAlarm,
                    onCancelAlarm: _cancelAlarm,
                    onSetRhythm: _debugSetRhythm,
                    onSetHR: _debugSetHR,
                    onSetSignalQuality: _debugSetSQ,
                    onSetBattery: _debugSetBattery,
                    onExitDebugMode: _debugExitMode,
                    currentStatus: _status,
                  ),
                ),
              ),
            ),
            const Spacer(),
            const Divider(color: KardiaxColors.input, height: 1),
            _DrawerItem(
                icon: Icons.person_outline, label: 'Health profile'),
            _DrawerItem(
                icon: Icons.settings_outlined, label: 'Settings'),
            _DrawerItem(
              icon: Icons.logout,
              label: 'Sign out',
              color: KardiaxColors.red,
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── SUB-WIDGETS ───────────────────────────

enum _ExportFormat { csv, pdf }

class _ExportOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: KardiaxColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: KardiaxColors.gray.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: KardiaxColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: KardiaxColors.red, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Oswald',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KardiaxColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Oswald',
                          fontSize: 12,
                          color: KardiaxColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.chevron_right,
                  color: KardiaxColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  final bool isSmall;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.isSmall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          vertical: isSmall ? 10 : 14, horizontal: 12),
      decoration: BoxDecoration(
        color: KardiaxColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                fontFamily: 'Oswald',
                color: KardiaxColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1.2,
              )),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      color: color,
                      fontSize: isSmall ? 20 : 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        color: color.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalQualityBar extends StatelessWidget {
  final double quality;
  const _SignalQualityBar({required this.quality});

  @override
  Widget build(BuildContext context) {
    final color = quality > 0.8
        ? KardiaxColors.green
        : quality > 0.5
            ? KardiaxColors.amber
            : KardiaxColors.red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('SQ',
            style: TextStyle(
                fontFamily: 'Oswald',
                color: KardiaxColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1)),
        const SizedBox(width: 6),
        SizedBox(
          width: 60,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: quality,
              backgroundColor: KardiaxColors.input,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('${(quality * 100).toInt()}%',
            style: TextStyle(
                fontFamily: 'Oswald',
                color: color,
                fontSize: 10,
                letterSpacing: 0.5)),
      ],
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  final double level;
  const _BatteryIndicator({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = level > 0.4
        ? KardiaxColors.green
        : level > 0.2
            ? KardiaxColors.amber
            : KardiaxColors.red;
    final icon = level > 0.8
        ? Icons.battery_full
        : level > 0.6
            ? Icons.battery_5_bar
            : level > 0.4
                ? Icons.battery_3_bar
                : level > 0.2
                    ? Icons.battery_2_bar
                    : Icons.battery_1_bar;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 3),
        Text('${(level * 100).toInt()}%',
            style: TextStyle(
                fontFamily: 'Oswald',
                color: color,
                fontSize: 11,
                letterSpacing: 0.5)),
      ],
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  const _DrawerItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.color = KardiaxColors.textPrimary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: selected ? KardiaxColors.red : color, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Oswald',
          color: selected ? KardiaxColors.red : color,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      selected: selected,
      selectedTileColor: KardiaxColors.red.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      onTap: () {
        Navigator.pop(context);
        onTap?.call();
      },
      dense: true,
    );
  }
}
