// lib/screens/ecg_dashboard.dart
// Full ECG dashboard screen — responsive, works on all iOS and Android sizes.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/ble_service.dart';
import '../services/mock_ble_service.dart';
import '../widgets/ecg_painter.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'debug_screen.dart';

class EcgDashboard extends StatefulWidget {
  const EcgDashboard({super.key});

  @override
  State<EcgDashboard> createState() => _EcgDashboardState();
}

class _EcgDashboardState extends State<EcgDashboard>
    with TickerProviderStateMixin {
  // 🔁 Swap to RealBleService() when on laptop with phone
  final BleService _ble = MockBleService();

  // Waveform buffer — 300 samples = ~5s at 60fps display
  final List<double> _waveform = List.filled(500, 0.5, growable: true);
  BleStatus _status = BleStatus.disconnected;
  bool _isArrhythmia = false;
  int _heartRate = 72;
  double _signalQuality = 1.0;
  double _batteryLevel = 0.87;
  String _arrhythmiaLabel = 'Normal sinus';
  double _arrhythmiaConfidence = 0.97;
  Duration _recordingDuration = Duration.zero;

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

  @override
  void initState() {
    super.initState();

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

    _connect();
  }

  Future<void> _connect() async {
    _statusSub = _ble.statusStream.listen((s) {
      setState(() => _status = s);
    });

    _ecgSub = _ble.ecgStream.listen((samples) {
      for (final raw in samples) {
        _waveform.add(raw / 4095.0);
        if (_waveform.length > 500) _waveform.removeAt(0);
      }

      bool shouldTrigger = false;
      bool shouldResolve = false;

      setState(() {
        if (_waveform.length >= 90) {
          final window = _waveform.sublist(_waveform.length - 90);
          final mean = window.reduce((a, b) => a + b) / window.length;
          final variance = window
              .map((x) => (x - mean) * (x - mean))
              .reduce((a, b) => a + b) / window.length;

          final wasArrhythmia = _isArrhythmia;
          _isArrhythmia = variance > 0.003;

          if (_isArrhythmia) {
            _arrhythmiaLabel      = 'LBBB detected';
            _arrhythmiaConfidence = 0.91;
            _signalQuality        = 0.62;
          } else {
            _arrhythmiaLabel      = 'Normal sinus';
            _arrhythmiaConfidence = 0.97;
            _signalQuality        = 0.94;
          }

          if (_isArrhythmia && !wasArrhythmia && !_showAlarm) shouldTrigger = true;
          if (!_isArrhythmia && wasArrhythmia) shouldResolve = true;
        }
      });

      if (shouldTrigger) _triggerAlarm();
      if (shouldResolve) _resolveAlarm();
    });

    await _ble.connect();
  }

  void _triggerAlarm() {
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
    setState(() {
      _showAlarm = false;
      _countdown = 30;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Alert cancelled — logged as false positive'),
        backgroundColor: KardiaxColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  void _fireCircleAlert() {
    setState(() => _showAlarm = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Circle notified'),
        backgroundColor: KardiaxColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
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
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _ble.dispose();
    super.dispose();
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmall = size.height < 700; // SE / older devices

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
                    color: KardiaxColors.gray.withOpacity(0.3),
                  ),
                ),
                child: const Icon(
                  Icons.menu,
                  color: KardiaxColors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Logo / title
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Kardia',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.textPrimary,
                    letterSpacing: 1.5,
                  ),
                ),
                TextSpan(
                  text: 'x',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
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
          // Battery
          _BatteryIndicator(level: _batteryLevel),
          const SizedBox(width: 12),
          // Recording duration
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: KardiaxColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KardiaxColors.gray.withOpacity(0.3)),
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
                    fontFamily: 'Rajdhani',
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
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // Signal quality bar
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
              color: _isArrhythmia ? KardiaxColors.red : KardiaxColors.green,
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
              value: '${(_arrhythmiaConfidence * 100).toInt()}',
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
                ? KardiaxColors.red.withOpacity(0.5)
                : KardiaxColors.gray.withOpacity(0.15),
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

  // ── Rhythm / arrhythmia label bar ──
  Widget _buildRhythmBar(bool isSmall) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isSmall ? 10 : 14,
        ),
        decoration: BoxDecoration(
          color: _rhythmColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _rhythmColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            // Pulse dot
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _rhythmColor.withOpacity(_pulseAnim.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _rhythmColor.withOpacity(0.4),
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
                      fontFamily: 'Rajdhani',
                      color: _rhythmColor,
                      fontSize: isSmall ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${(_arrhythmiaConfidence * 100).toInt()}% confidence',
                    style: const TextStyle(
                      fontFamily: 'Rajdhani',
                      color: KardiaxColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Export button
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Generating export...'),
                  backgroundColor: KardiaxColors.card,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: KardiaxColors.input,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: KardiaxColors.gray.withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.download_outlined,
                      color: KardiaxColors.textSecondary,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Export',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
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
      builder: (_, __) => Container(
        width: size.width,
        height: size.height,
        color: KardiaxColors.red.withOpacity(_alarmAnim.value * 0.15),
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: size.width * 0.08),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: KardiaxColors.red.withOpacity(0.7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: KardiaxColors.red.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Label
                const Text(
                  'ARRHYTHMIA DETECTED',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
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
                    fontFamily: 'Rajdhani',
                    color: KardiaxColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),

                // Countdown ring
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
                          valueColor: AlwaysStoppedAnimation(KardiaxColors.red),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_countdown',
                            style: const TextStyle(
                              fontFamily: 'Rajdhani',
                              color: KardiaxColors.textPrimary,
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'sec',
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
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
                    fontFamily: 'Rajdhani',
                    color: KardiaxColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _cancelAlarm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KardiaxColors.green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "I'M OK — CANCEL ALERT",
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
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
                        fontFamily: 'Rajdhani',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: KardiaxColors.textPrimary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    TextSpan(
                      text: 'x',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
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
              selected: true,
            ),
            _DrawerItem(icon: Icons.history, label: 'Alert history'),
            _DrawerItem(icon: Icons.people_outline, label: 'My circle'),
            _DrawerItem(icon: Icons.download_outlined, label: 'Export ECG'),
            _DrawerItem(icon: Icons.bluetooth_outlined, label: 'Device'),
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
            _DrawerItem(icon: Icons.person_outline, label: 'Health profile'),
            _DrawerItem(icon: Icons.settings_outlined, label: 'Settings'),
            _DrawerItem(
              icon: Icons.logout,
              label: 'Sign out',
              color: KardiaxColors.red,
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
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
        vertical: isSmall ? 10 : 14,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: KardiaxColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              color: KardiaxColors.textSecondary,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
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
                      fontFamily: 'Rajdhani',
                      color: color,
                      fontSize: isSmall ? 20 : 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        color: color.withOpacity(0.6),
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
  final double quality; // 0.0 – 1.0
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
        Text(
          'SQ',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            color: KardiaxColors.textSecondary,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
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
        Text(
          '${(quality * 100).toInt()}%',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            color: color,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  final double level; // 0.0 – 1.0
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
        Text(
          '${(level * 100).toInt()}%',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            color: color,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
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
      leading: Icon(
        icon,
        color: selected ? KardiaxColors.red : color,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Rajdhani',
          color: selected ? KardiaxColors.red : color,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      selected: selected,
      selectedTileColor: KardiaxColors.red.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () {
        Navigator.pop(context);
        onTap?.call();
      },
      dense: true,
    );
  }
}
