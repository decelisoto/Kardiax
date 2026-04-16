// lib/services/real_ble_service.dart

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';

class RealBleService implements BleService {
  static const _deviceName = 'Kardiax';
  static const _serviceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const _charUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  final _ecgController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<BleStatus>.broadcast();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription? _scanSub;
  StreamSubscription? _valueSub;
  StreamSubscription? _connectionSub;

  @override
  Stream<List<int>> get ecgStream => _ecgController.stream;
  @override
  Stream<BleStatus> get statusStream => _statusController.stream;

  @override
  Future<void> connect() async {
    _statusController.add(BleStatus.scanning);

    // Scan for Kardiax — stop as soon as we find it
    final completer = Completer<BluetoothDevice>();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.platformName == _deviceName && !completer.isCompleted) {
          completer.complete(r.device);
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    try {
      _device = await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _statusController.add(BleStatus.disconnected);
      return;
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
    }

    // Connect
    _statusController.add(BleStatus.connecting);
    await _device!.connect(autoConnect: false);

    // Watch for unexpected disconnects
    _connectionSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _statusController.add(BleStatus.lost);
        _scheduleReconnect();
      }
    });

    await _discoverAndSubscribe();
  }

  Future<void> _discoverAndSubscribe() async {
    final services = await _device!.discoverServices();

    for (final s in services) {
      if (s.uuid.toString() == _serviceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid.toString() == _charUuid) {
            _characteristic = c;
            await c.setNotifyValue(true);

            _valueSub = c.onValueReceived.listen(_parsePacket);
            _statusController.add(BleStatus.connected);
            return;
          }
        }
      }
    }
    // Service/char not found
    _statusController.add(BleStatus.disconnected);
  }

  void _parsePacket(List<int> data) {
    // Each packet: SAMPLES_PER_PACKET × 2 bytes, little-endian uint16
    final samples = <int>[];
    for (int i = 0; i + 1 < data.length; i += 2) {
      final raw = data[i] | (data[i + 1] << 8);
      samples.add(raw);
    }
    if (samples.isNotEmpty) _ecgController.add(samples);
  }

  // Exponential backoff reconnect: 1s → 2s → 4s → 8s → 30s (cap)
  int _reconnectAttempts = 0;
  void _scheduleReconnect() {
    final seconds = [1, 2, 4, 8, 30];
    final delay = seconds[_reconnectAttempts.clamp(0, seconds.length - 1)];
    _reconnectAttempts++;

    Future.delayed(Duration(seconds: delay), () async {
      try {
        await _device!.connect(autoConnect: false);
        await _discoverAndSubscribe();
        _reconnectAttempts = 0;
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _valueSub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _statusController.add(BleStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    _ecgController.close();
    _statusController.close();
  }
}
