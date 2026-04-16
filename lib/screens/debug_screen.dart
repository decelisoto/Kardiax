// lib/screens/debug_screen.dart
// Internal debug panel — access from drawer, never shown to end users.
// Lets you manually trigger any app state for demo purposes.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/ble_service.dart';

class DebugScreen extends StatefulWidget {
  // Pass in callbacks from EcgDashboard so debug actions affect the live screen
  final Function(bool) onArrhythmiaToggle;
  final Function() onTriggerAlarm;
  final Function() onCancelAlarm;
  final Function(String, double) onSetRhythm;
  final Function(int) onSetHR;
  final Function(double) onSetSignalQuality;
  final Function(double) onSetBattery;
  final VoidCallback onExitDebugMode;
  final BleStatus currentStatus;

  const DebugScreen({
    super.key,
    required this.onArrhythmiaToggle,
    required this.onTriggerAlarm,
    required this.onCancelAlarm,
    required this.onSetRhythm,
    required this.onSetHR,
    required this.onSetSignalQuality,
    required this.onSetBattery,
    required this.onExitDebugMode,
    required this.currentStatus,
  });

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  bool _arrhythmiaOn = false;
  int _heartRate = 72;
  double _signalQuality = 0.94;
  double _batteryLevel = 0.87;
  String _selectedRhythm = 'Normal sinus';
  double _confidence = 0.97;

  final _rhythms = {
    'Normal sinus': 0.97,
    'LBBB detected': 0.91,
    'AFib': 0.88,
    'PVC': 0.85,
    'Tachycardia': 0.92,
    'Bradycardia': 0.89,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KardiaxColors.black,
      appBar: AppBar(
        backgroundColor: KardiaxColors.black,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: KardiaxColors.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text(
              'Debug Panel',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                color: KardiaxColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KardiaxColors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: KardiaxColors.amber.withOpacity(0.4)),
              ),
              child: const Text(
                'DEV ONLY',
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  color: KardiaxColors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Alarm controls ──
            _SectionHeader('ALARM'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DebugButton(
                    label: 'Trigger alarm',
                    color: KardiaxColors.red,
                    icon: Icons.notification_important_outlined,
                    onTap: () {
                      widget.onArrhythmiaToggle(true);
                      widget.onTriggerAlarm();
                      _showToast('Alarm triggered');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DebugButton(
                    label: 'Cancel alarm',
                    color: KardiaxColors.green,
                    icon: Icons.cancel_outlined,
                    onTap: () {
                      widget.onArrhythmiaToggle(false);
                      widget.onCancelAlarm();
                      _showToast('Alarm cancelled');
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Rhythm simulation ──
            _SectionHeader('SIMULATE RHYTHM'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _rhythms.entries.map((e) {
                final selected = _selectedRhythm == e.key;
                final isAbnormal = e.key != 'Normal sinus';
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRhythm = e.key;
                      _confidence = e.value;
                      _arrhythmiaOn = isAbnormal;
                    });
                    widget.onSetRhythm(e.key, e.value);
                    widget.onArrhythmiaToggle(isAbnormal);
                    if (isAbnormal) widget.onTriggerAlarm();
                    _showToast('Simulating: ${e.key}');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? (isAbnormal
                                ? KardiaxColors.red.withOpacity(0.15)
                                : KardiaxColors.green.withOpacity(0.15))
                          : KardiaxColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? (isAbnormal
                                  ? KardiaxColors.red
                                  : KardiaxColors.green)
                            : KardiaxColors.gray.withOpacity(0.3),
                        width: selected ? 1.5 : 0.5,
                      ),
                    ),
                    child: Text(
                      e.key,
                      style: TextStyle(
                        fontFamily: 'Rajdhani',
                        color: selected
                            ? (isAbnormal
                                  ? KardiaxColors.red
                                  : KardiaxColors.green)
                            : KardiaxColors.textSecondary,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ── Heart rate ──
            _SectionHeader('HEART RATE  $_heartRate bpm'),
            Slider(
              value: _heartRate.toDouble(),
              min: 30,
              max: 180,
              divisions: 150,
              activeColor: KardiaxColors.red,
              inactiveColor: KardiaxColors.input,
              onChanged: (v) {
                setState(() => _heartRate = v.toInt());
                widget.onSetHR(v.toInt());
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  '30',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    color: KardiaxColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  'Bradycardia  |  Normal  |  Tachycardia',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    color: KardiaxColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '180',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    color: KardiaxColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Signal quality ──
            _SectionHeader(
              'SIGNAL QUALITY  ${(_signalQuality * 100).toInt()}%',
            ),
            Slider(
              value: _signalQuality,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: _signalQuality > 0.7
                  ? KardiaxColors.green
                  : _signalQuality > 0.4
                  ? KardiaxColors.amber
                  : KardiaxColors.red,
              inactiveColor: KardiaxColors.input,
              onChanged: (v) {
                setState(() => _signalQuality = v);
                widget.onSetSignalQuality(v);
              },
            ),

            const SizedBox(height: 16),

            // ── Battery ──
            _SectionHeader('DEVICE BATTERY  ${(_batteryLevel * 100).toInt()}%'),
            Slider(
              value: _batteryLevel,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: _batteryLevel > 0.4
                  ? KardiaxColors.green
                  : _batteryLevel > 0.2
                  ? KardiaxColors.amber
                  : KardiaxColors.red,
              inactiveColor: KardiaxColors.input,
              onChanged: (v) {
                setState(() => _batteryLevel = v);
                widget.onSetBattery(v);
              },
            ),

            const SizedBox(height: 20),

            // ── BLE status ──
            _SectionHeader('BLE STATUS'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KardiaxColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KardiaxColors.gray.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bluetooth,
                    color: KardiaxColors.textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.currentStatus.name.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Rajdhani',
                      color: KardiaxColors.textSecondary,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Quick scenarios ──
            _SectionHeader('DEMO SCENARIOS'),
            const SizedBox(height: 10),
            _DebugButton(
              label: 'Full demo flow (normal → LBBB alarm in 5s)',
              color: KardiaxColors.red,
              icon: Icons.play_arrow_outlined,
              onTap: () {
                widget.onSetRhythm('Normal sinus', 0.97);
                widget.onArrhythmiaToggle(false);
                setState(() {
                  _selectedRhythm = 'Normal sinus';
                  _arrhythmiaOn = false;
                  _heartRate = 72;
                });
                Future.delayed(const Duration(seconds: 5), () {
                  widget.onSetRhythm('LBBB detected', 0.91);
                  widget.onArrhythmiaToggle(true);
                  widget.onTriggerAlarm();
                });
                _showToast('Demo started — alarm fires in 5s');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            _DebugButton(
              label: 'Simulate poor signal quality',
              color: KardiaxColors.amber,
              icon: Icons.signal_wifi_bad_outlined,
              onTap: () {
                widget.onSetSignalQuality(0.25);
                setState(() => _signalQuality = 0.25);
                _showToast('Signal quality set to 25%');
              },
            ),
            const SizedBox(height: 8),
            _DebugButton(
              label: 'Simulate low battery',
              color: KardiaxColors.amber,
              icon: Icons.battery_1_bar_outlined,
              onTap: () {
                widget.onSetBattery(0.08);
                setState(() => _batteryLevel = 0.08);
                _showToast('Battery set to 8%');
              },
            ),
            const SizedBox(height: 8),
            _DebugButton(
              label: 'Reset all to normal',
              color: KardiaxColors.green,
              icon: Icons.refresh_outlined,
              onTap: () {
                widget.onExitDebugMode();
                widget.onArrhythmiaToggle(false);
                widget.onCancelAlarm();
                widget.onSetRhythm('Normal sinus', 0.97);
                widget.onSetHR(72);
                widget.onSetSignalQuality(0.94);
                widget.onSetBattery(0.87);
                setState(() {
                  _arrhythmiaOn = false;
                  _selectedRhythm = 'Normal sinus';
                  _heartRate = 72;
                  _signalQuality = 0.94;
                  _batteryLevel = 0.87;
                });
                _showToast('Reset to normal');
              },
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Rajdhani')),
        backgroundColor: KardiaxColors.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── Sub-widgets ──

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Rajdhani',
        color: KardiaxColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _DebugButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _DebugButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
