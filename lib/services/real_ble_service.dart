// lib/services/real_ble_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';

/// Parsed result from one BLE Heart Rate Measurement packet.
class BleHeartRatePacket {
  final int hrBpm;
  final double rrMs;       // RR interval in milliseconds
  final bool isLeadsOff;   // true if Arduino flagged leads-off (flags = 0xFE)
  final bool isStatusOnly; // true if init/status packet (flags = 0xFF)

  const BleHeartRatePacket({
    required this.hrBpm,
    required this.rrMs,
    this.isLeadsOff = false,
    this.isStatusOnly = false,
  });

  @override
  String toString() =>
      'BleHeartRatePacket(hr=$hrBpm, rr=${rrMs.toStringAsFixed(1)}ms, '
      'leadsOff=$isLeadsOff, statusOnly=$isStatusOnly)';
}

class RealBleService implements BleService {
  static const _deviceName  = 'Kardiax';
  static const _serviceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const _charUuid    = '00002a37-0000-1000-8000-00805f9b34fb';
  static final Guid _serviceGuid = Guid(_serviceUuid);
  static final Guid _charGuid = Guid(_charUuid);

  // Raw packet stream — kept for compatibility with existing BleService interface.
  // Emits [hrBpm, rrMs_int] as a 2-element list so existing consumers don't break.
  final _ecgController    = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<BleStatus>.broadcast();

  // Parsed stream — prefer this over ecgStream for new consumers.
  final _packetController = StreamController<BleHeartRatePacket>.broadcast();

  BluetoothDevice?          _device;
  BluetoothCharacteristic?  _characteristic;
  StreamSubscription?       _scanSub;
  StreamSubscription?       _valueSub;
  StreamSubscription?       _connectionSub;
  bool                      _isFullyConnected = false;
  bool                      _isConnecting     = false;

  BleStatus _currentStatus = BleStatus.disconnected;

  String get _debugTag =>
      'RealBleService#${identityHashCode(this).toRadixString(16)}';

  @override
  Stream<List<int>> get ecgStream => _ecgController.stream;

  @override
  Stream<BleStatus> get statusStream => _statusController.stream;

  @override
  BleStatus get currentStatus => _currentStatus;

  void _emitStatus(BleStatus s) {
    if (kDebugMode) {
      debugPrint(
        '$_debugTag status -> $s '
        '(device=${_device?.platformName ?? "-"}, '
        'isConnected=${_device?.isConnected ?? false}, '
        'fullyConnected=$_isFullyConnected, '
        'connecting=$_isConnecting)',
      );
    }
    _currentStatus = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  /// Parsed Heart Rate Measurement packets.
  /// Each emission has a valid hrBpm and rrMs — check isLeadsOff / isStatusOnly
  /// before using the values.
  Stream<BleHeartRatePacket> get packetStream => _packetController.stream;

  // ── Connect ────────────────────────────────────────────────────

  @override
  Future<void> connect() async {
    if (kDebugMode) {
      debugPrint(
        '$_debugTag connect() called '
        '(current=$_currentStatus, '
        'deviceConnected=${_device?.isConnected ?? false}, '
        'fullyConnected=$_isFullyConnected, '
        'connecting=$_isConnecting)',
      );
    }
    if (_isConnecting || _isFullyConnected) return;

    if (_device?.isConnected ?? false) {
      _emitStatus(BleStatus.connected);
      if (!_isFullyConnected) {
        await _discoverAndSubscribe();
      }
      return;
    }

    _isConnecting = true;

    try {
      await _doConnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _doConnect() async {
    // Wait for BT adapter to be ready on iOS
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      _emitStatus(BleStatus.disconnected);
      return;
    }

    _emitStatus(BleStatus.scanning);

    final completer = Completer<BluetoothDevice>();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name    = r.device.platformName;
        final advName = r.advertisementData.advName;
        final hasHrService = r.advertisementData.serviceUuids
            .any((u) => u.toString().toLowerCase().contains('180d'));

        if ((name == _deviceName || advName == _deviceName) &&
            !completer.isCompleted) {
          if (kDebugMode) {
            debugPrint(
              '$_debugTag matched device '
              '(name="$name", adv="$advName", '
              'hasHr=$hasHrService, '
              'serviceUuids=${r.advertisementData.serviceUuids})',
            );
          }
          completer.complete(r.device);
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    try {
      _device = await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _emitStatus(BleStatus.disconnected);
      return;
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
    }

    _emitStatus(BleStatus.connecting);
    await _device!.connect(autoConnect: false);
    _emitStatus(BleStatus.connected);
    await Future.delayed(const Duration(milliseconds: 500));

    await _discoverAndSubscribe();

    // Set up connection-loss watcher only after full setup succeeds,
    // so iOS disconnect events during GATT discovery are ignored.
    if (_isFullyConnected) {
      _connectionSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _isFullyConnected) {
          _isFullyConnected = false;
          _emitStatus(BleStatus.lost);
          _scheduleReconnect();
        }
      });
    }
  }

  // ── Service / characteristic discovery ────────────────────────

  Future<void> _discoverAndSubscribe() async {
    if (kDebugMode) {
      debugPrint(
        '$_debugTag discoverAndSubscribe() '
        '(deviceConnected=${_device?.isConnected ?? false}, '
        'fullyConnected=$_isFullyConnected)',
      );
    }
    if (_isFullyConnected) return; // already subscribed, don't duplicate
    final services = await _device!.discoverServices();
    if (kDebugMode) {
      debugPrint(
        '$_debugTag discovered ${services.length} services: '
        '${services.map((s) => s.uuid.toString()).join(", ")}',
      );
    }

    for (final s in services) {
      if (kDebugMode) {
        debugPrint(
          '$_debugTag inspecting service ${s.uuid} '
          'with ${s.characteristics.length} characteristics',
        );
      }
      if (s.uuid == _serviceGuid ||
          s.uuid.toString().toLowerCase() == _serviceUuid) {
        for (final c in s.characteristics) {
          if (kDebugMode) {
            debugPrint('$_debugTag inspecting characteristic ${c.uuid}');
          }
          if (c.uuid == _charGuid ||
              c.uuid.toString().toLowerCase() == _charUuid) {
            _characteristic = c;
            await c.setNotifyValue(true);
            _valueSub = c.onValueReceived.listen(_parsePacket);
            _isFullyConnected = true;
            if (kDebugMode) {
              debugPrint(
                '$_debugTag notify subscribed '
                '(service=${s.uuid}, characteristic=${c.uuid})',
              );
            }
            _emitStatus(BleStatus.connected);
            return;
          }
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
        '$_debugTag failed to match expected service/characteristic; '
        'keeping connection status because peripheral is still connected',
      );
    }
    if (_device?.isConnected ?? false) {
      _emitStatus(BleStatus.connected);
      return;
    }
    _emitStatus(BleStatus.disconnected);
  }

  // ── Packet parsing ─────────────────────────────────────────────
  //
  // Arduino sends 18-byte Heart Rate Measurement packets:
  //
  //   Byte 0    : flags
  //               0x08 = normal beat packet (RR present, HR uint8)
  //               0xFF = status/init packet  → isStatusOnly = true
  //               0xFE = leads-off packet    → isLeadsOff   = true
  //   Byte 1    : HR in bpm (uint8)
  //   Bytes 2-3 : RR interval in 1/1024 sec units (uint16 little-endian)
  //               Convert to ms: value / 1.024
  //   Bytes 4-17: padding (0x00, ignored)
  //
  // Previous _parsePacket treated every 2 bytes as a raw uint16 sample —
  // that was wrong for this packet format.

  void _parsePacket(List<int> data) {
    if (data.isEmpty) return;

    final flags = data[0] & 0xFF;

    // ── Status packets (leads-off, init complete) ──
    if (flags == 0xFF) {
      // Init complete / generic status — emit so UI can react
      final pkt = const BleHeartRatePacket(
        hrBpm: 0,
        rrMs: 0,
        isStatusOnly: true,
      );
      _packetController.add(pkt);
      return;
    }

    if (flags == 0xFE) {
      // Leads-off detected by Arduino
      final pkt = const BleHeartRatePacket(
        hrBpm: 0,
        rrMs: 0,
        isLeadsOff: true,
      );
      _packetController.add(pkt);
      _emitStatus(BleStatus.leadsOff);
      return;
    }

    // ── Normal beat packet (flags == 0x08) ──
    if (data.length < 4) return; // malformed, need at least 4 bytes

    final hrBpm = data[1] & 0xFF;

    // RR interval: uint16 LE in 1/1024 sec units
    final rrRaw = (data[2] & 0xFF) | ((data[3] & 0xFF) << 8);
    final rrMs  = rrRaw / 1.024; // convert to milliseconds

    // Basic sanity check before emitting
    if (hrBpm < 20 || hrBpm > 300) return; // outside any plausible HR range
    if (rrMs < 200 || rrMs > 3000) return; // outside 20–300 bpm range

    final pkt = BleHeartRatePacket(hrBpm: hrBpm, rrMs: rrMs);
    _packetController.add(pkt);

    // Synthesize one cardiac cycle of ECG samples at 250 Hz so the waveform
    // painter receives meaningful data (the Arduino only sends beat-by-beat
    // HR+RR, not raw ADC samples).
    _emitSyntheticCycle(rrMs);
  }

  // Generates a plausible Lead-I ECG cycle (P → QRS → T) scaled to the
  // 12-bit ADC range (0–4095) so consumers can normalise with raw / 4095.0.
  void _emitSyntheticCycle(double rrMs) {
    final n = (rrMs * 250 / 1000).round().clamp(30, 500);
    final buf = List<int>.filled(n, 2048); // baseline at mid-rail

    // P wave (~20% into cycle)
    final p = (n * 0.20).round();
    for (int i = -6; i <= 6; i++) {
      _setBuf(buf, p + i, (2048 + 250 * (1.0 - i.abs() / 7.0)).round());
    }

    // QRS complex (~35% into cycle)
    final r = (n * 0.35).round();
    _setBuf(buf, r - 5, 1900);
    _setBuf(buf, r - 4, 1600);
    _setBuf(buf, r - 3, 1400); // Q nadir
    _setBuf(buf, r - 1, 2700);
    _setBuf(buf, r,     3850); // R peak
    _setBuf(buf, r + 1, 2700);
    _setBuf(buf, r + 2, 1400); // S nadir
    _setBuf(buf, r + 3, 1700);
    _setBuf(buf, r + 4, 2000);

    // T wave (~55% into cycle)
    final t = (n * 0.55).round();
    for (int i = -10; i <= 10; i++) {
      _setBuf(buf, t + i, (2048 + 400 * (1.0 - i.abs() / 11.0)).round());
    }

    _ecgController.add(buf);
  }

  void _setBuf(List<int> buf, int i, int v) {
    if (i >= 0 && i < buf.length) buf[i] = v;
  }

  // ── Reconnect (unchanged, exponential backoff) ─────────────────

  int _reconnectAttempts = 0;

  void _scheduleReconnect() {
    if (_device == null || _device!.isConnected) return;

    const delays = [1, 2, 4, 8, 30];
    final delay  = delays[_reconnectAttempts.clamp(0, delays.length - 1)];
    _reconnectAttempts++;
    if (kDebugMode) {
      debugPrint('$_debugTag scheduleReconnect() in ${delay}s');
    }

    Future.delayed(Duration(seconds: delay), () async {
      if (_device == null || _device!.isConnected) return;
      _emitStatus(BleStatus.connecting);
      try {
        // Reuse the existing device reference — no rescan needed.
        await _device!.connect(autoConnect: false);
        _emitStatus(BleStatus.connected);
        await Future.delayed(const Duration(milliseconds: 500));
        await _discoverAndSubscribe();
        _reconnectAttempts = 0;
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  // ── Disconnect / dispose ───────────────────────────────────────

  @override
  Future<void> disconnect() async {
    if (kDebugMode) {
      debugPrint('$_debugTag disconnect() called');
    }
    await _valueSub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _emitStatus(BleStatus.disconnected);
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('$_debugTag dispose() called');
    }
    disconnect();
    _ecgController.close();
    _statusController.close();
    _packetController.close();
  }
}
