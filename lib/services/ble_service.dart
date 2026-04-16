// lib/services/ble_service.dart

import 'dart:async';

abstract class BleService {
  Stream<List<int>> get ecgStream;
  Stream<BleStatus> get statusStream;
  Future<void> connect();
  Future<void> disconnect();
  void dispose();
}

enum BleStatus { disconnected, scanning, connecting, connected, lost }
