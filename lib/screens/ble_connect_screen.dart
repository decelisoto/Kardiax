// lib/screens/ble_connect_screen.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/real_ble_service.dart';
import '../theme.dart';
import 'ecg_dashboard.dart';

enum _ConnStep { idle, scanning, connecting, ready, failed }

class BleConnectScreen extends StatefulWidget {
  final RealBleService bleService;

  const BleConnectScreen({
    super.key,
    required this.bleService,
  });

  @override
  State<BleConnectScreen> createState() => _BleConnectScreenState();
}

class _BleConnectScreenState extends State<BleConnectScreen>
    with TickerProviderStateMixin {
  late final RealBleService _ble;
  StreamSubscription<BleStatus>? _statusSub;
  bool _navigationScheduled = false;

  _ConnStep _step = _ConnStep.idle;
  String _subtitle = '';

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  String get _debugTag =>
      'BleConnectScreen#${identityHashCode(this).toRadixString(16)}';

  @override
  void initState() {
    super.initState();
    _ble = widget.bleService;
    if (kDebugMode) {
      debugPrint('$_debugTag initState (ble=${identityHashCode(_ble).toRadixString(16)})');
    }

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _statusSub = _ble.statusStream.listen(_onStatus);
    _beginConnect();
  }

  void _onStatus(BleStatus s) {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint('$_debugTag onStatus($s) step=$_step navScheduled=$_navigationScheduled');
    }
    setState(() {
      switch (s) {
        case BleStatus.scanning:
          if (_step == _ConnStep.connecting || _step == _ConnStep.ready) {
            return;
          }
          _step = _ConnStep.scanning;
          _subtitle = 'Scanning for "Kardiax" device...';
          return;
        case BleStatus.connecting:
          if (_step == _ConnStep.ready) return;
          _step = _ConnStep.connecting;
          _subtitle = 'Device found — establishing connection';
          return;
        case BleStatus.connected:
          _step = _ConnStep.ready;
          _subtitle = 'Connected!';
          _goToDashboard();
          return;
        case BleStatus.disconnected:
          if (_step != _ConnStep.ready) {
            _step = _ConnStep.failed;
            _subtitle = 'Device not found. Is the shirt powered on and nearby?';
          }
          return;
        case BleStatus.lost:
          if (_step != _ConnStep.ready) {
            _step = _ConnStep.failed;
            _subtitle = 'Connection lost during setup.';
          }
          return;
        case BleStatus.leadsOff:
          return;
      }
    });
  }

  Future<void> _beginConnect() async {
    final status = _ble.currentStatus;
    if (kDebugMode) {
      debugPrint('$_debugTag _beginConnect() currentStatus=$status step=$_step');
    }
    if (status == BleStatus.connected || status == BleStatus.connecting) {
      _onStatus(status);
      return;
    }

    setState(() {
      _step = _ConnStep.scanning;
      _subtitle = 'Checking Bluetooth...';
    });
    await _ble.connect();
    _onStatus(_ble.currentStatus);
  }

  void _goToDashboard() {
    if (_navigationScheduled) return;
    _navigationScheduled = true;
    if (kDebugMode) {
      debugPrint('$_debugTag scheduling dashboard navigation');
    }
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, anim, __) => EcgDashboard(bleService: _ble),
          transitionsBuilder: (context, anim, secondary, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 450),
        ),
      );
    });
  }

  void _retry() {
    setState(() {
      _step = _ConnStep.scanning;
      _subtitle = 'Retrying...';
    });
    _beginConnect();
  }

  void _skip() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EcgDashboard(bleService: _ble),
      ),
    );
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('$_debugTag dispose()');
    }
    _statusSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KardiaxColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 28),
              _buildWordmark(),
              const SizedBox(height: 6),
              const Text(
                'Connecting to your EKG shirt',
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 14,
                  color: KardiaxColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              _buildCenterIcon(),
              const SizedBox(height: 52),
              _buildStepList(),
              const SizedBox(height: 20),
              _buildSubtitle(),
              const Spacer(),
              if (_step == _ConnStep.failed) ...[
                _buildFailureActions(),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordmark() {
    return RichText(
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
    );
  }

  Widget _buildCenterIcon() {
    final isDone = _step == _ConnStep.ready;
    final isFailed = _step == _ConnStep.failed;
    final isActive =
        _step == _ConnStep.scanning || _step == _ConnStep.connecting;

    final color = isDone
        ? KardiaxColors.green
        : isFailed
            ? KardiaxColors.red
            : KardiaxColors.red;

    final iconData = isDone
        ? Icons.bluetooth_connected
        : isFailed
            ? Icons.bluetooth_disabled
            : Icons.bluetooth_searching;

    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(
          scale: isActive ? _pulseAnim.value : 1.0,
          child: child,
        ),
        child: Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDone ? 0.09 : 0.06),
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: isDone ? 0.55 : 0.22),
              width: 1.5,
            ),
            boxShadow: isDone
                ? [
                    BoxShadow(
                      color: KardiaxColors.green.withValues(alpha: 0.22),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ]
                : [],
          ),
          child: Icon(iconData, color: color, size: 50),
        ),
      ),
    );
  }

  Widget _buildStepList() {
    return Column(
      children: [
        _StepRow(
          label: 'Bluetooth enabled',
          state: _rowState(0),
        ),
        const SizedBox(height: 18),
        _StepRow(
          label: 'Scanning for device',
          state: _rowState(1),
        ),
        const SizedBox(height: 18),
        _StepRow(
          label: 'Connecting',
          state: _rowState(2),
        ),
        const SizedBox(height: 18),
        _StepRow(
          label: 'Subscribing to ECG stream',
          state: _rowState(3),
        ),
      ],
    );
  }

  _RowState _rowState(int index) {
    return switch (_step) {
      _ConnStep.idle => index == 0 ? _RowState.active : _RowState.pending,
      _ConnStep.scanning => switch (index) {
          0 => _RowState.done,
          1 => _RowState.active,
          _ => _RowState.pending,
        },
      _ConnStep.connecting => switch (index) {
          0 || 1 => _RowState.done,
          2      => _RowState.active,
          _      => _RowState.pending,
        },
      _ConnStep.ready => _RowState.done,
      _ConnStep.failed => switch (index) {
          0 => _RowState.done,
          1 => _RowState.error,
          _ => _RowState.pending,
        },
    };
  }

  Widget _buildSubtitle() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(
        _subtitle,
        key: ValueKey(_subtitle),
        style: TextStyle(
          fontFamily: 'Oswald',
          fontSize: 13,
          color: _step == _ConnStep.failed
              ? KardiaxColors.red
              : KardiaxColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildFailureActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _retry,
          style: ElevatedButton.styleFrom(
            backgroundColor: KardiaxColors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: const Text(
            'RETRY',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _skip,
          style: OutlinedButton.styleFrom(
            foregroundColor: KardiaxColors.textSecondary,
            side: BorderSide(
                color: KardiaxColors.gray.withValues(alpha: 0.35)),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text(
            'Skip for now',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step row ───────────────────────────────────────────────────────

enum _RowState { pending, active, done, error }

class _StepRow extends StatelessWidget {
  final String label;
  final _RowState state;
  const _StepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _RowState.done    => KardiaxColors.green,
      _RowState.error   => KardiaxColors.red,
      _RowState.active  => KardiaxColors.red,
      _RowState.pending => KardiaxColors.gray,
    };

    final textColor = switch (state) {
      _RowState.pending => KardiaxColors.textSecondary,
      _RowState.error   => KardiaxColors.red,
      _               => KardiaxColors.textPrimary,
    };

    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: state == _RowState.active
              ? CircularProgressIndicator(strokeWidth: 2.5, color: color)
              : Icon(
                  switch (state) {
                    _RowState.done  => Icons.check_circle_outline,
                    _RowState.error => Icons.error_outline,
                    _               => Icons.radio_button_unchecked,
                  },
                  color: color,
                  size: 22,
                ),
        ),
        const SizedBox(width: 14),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Oswald',
            fontSize: 15,
            fontWeight: state == _RowState.active || state == _RowState.done
                ? FontWeight.w600
                : FontWeight.w400,
            color: textColor,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
