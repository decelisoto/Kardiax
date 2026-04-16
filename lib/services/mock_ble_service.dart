// lib/services/mock_ble_service.dart

import 'dart:async';
import 'dart:math';
import 'ble_service.dart';

class MockBleService implements BleService {
  final _ecgController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<BleStatus>.broadcast();

  Timer? _dataTimer;
  double _t = 0.0;
  final double _sampleRate = 360.0;
  final _rng = Random();

  bool _inArrhythmia = false;
  int _cycleCounter = 0;
  static const int _normalSamples = 240 * 8;     // 8s normal       @ 240 Hz effective
  static const int _arrhythmiaSamples = 240 * 5; // 5s arrhythmia  @ 240 Hz effective

  @override
  Stream<List<int>> get ecgStream => _ecgController.stream;
  @override
  Stream<BleStatus> get statusStream => _statusController.stream;

  @override
  Future<void> connect() async {
    _statusController.add(BleStatus.scanning);
    await Future.delayed(const Duration(milliseconds: 800));
    _statusController.add(BleStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 600));
    _statusController.add(BleStatus.connected);
    _startStreaming();
  }

  @override
  Future<void> disconnect() async {
    _dataTimer?.cancel();
    _statusController.add(BleStatus.disconnected);
  }

  void _startStreaming() {
    // 9 samples every 40ms ≈ 225 Hz effective
    _dataTimer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      final batch = <int>[];
      for (int i = 0; i < 6; i++) {
        batch.add(_nextSample());
      }
      _ecgController.add(batch);
    });
  }

  int _nextSample() {
    _cycleCounter++;

    if (!_inArrhythmia && _cycleCounter >= _normalSamples) {
      _inArrhythmia = true;
      _cycleCounter = 0;
    } else if (_inArrhythmia && _cycleCounter >= _arrhythmiaSamples) {
      _inArrhythmia = false;
      _cycleCounter = 0;
    }

    final value = _inArrhythmia ? _arrhythmiaSample() : _sinusSample();
    final noisy = value + (_rng.nextDouble() - 0.5) * 0.04;
    final raw = (noisy * 400 + 2048).clamp(0, 4095).toInt();

    _t += 1.0 / _sampleRate;
    return raw;
  }

  // ── Normal sinus rhythm ──
  double _sinusSample() {
    const bpm = 72.0;
    final period = 60.0 / bpm;
    final phase = (_t % period) / period;

    double v = 0.15 * _g(phase, 0.12, 0.025); // P
    v -= 0.10 * _g(phase, 0.22, 0.008); // Q
    v += 1.00 * _g(phase, 0.25, 0.012); // R
    v -= 0.25 * _g(phase, 0.28, 0.010); // S
    v += 0.30 * _g(phase, 0.42, 0.045); // T
    v += 0.05 * sin(2 * pi * 0.15 * _t); // baseline wander
    return v;
  }

  // ── LBBB-like arrhythmia (widened/notched QRS, irregular rate) ──
  double _arrhythmiaSample() {
    final bpm = 45.0 + 65.0 * (0.5 + 0.5 * sin(2 * pi * 0.3 * _t));
    final period = 60.0 / bpm;
    final phase = (_t % period) / period;

    double v = 0.10 * _g(phase, 0.12, 0.030);
    v += 0.60 * _g(phase, 0.26, 0.025);
    v += 0.40 * _g(phase, 0.32, 0.020);
    v -= 0.15 * _g(phase, 0.38, 0.015);
    v += 0.20 * _g(phase, 0.52, 0.060);
    v += 0.08 * sin(2 * pi * 0.2 * _t);
    return v;
  }

  // Force arrhythmia mode immediately — used by debug panel.
  void forceArrhythmia(bool on) {
    _inArrhythmia = on;
    _cycleCounter = 0;
  }

  double _g(double x, double mean, double sigma) {
    final d = x - mean;
    return exp(-d * d / (2 * sigma * sigma));
  }

  @override
  void dispose() {
    _dataTimer?.cancel();
    _ecgController.close();
    _statusController.close();
  }
}
