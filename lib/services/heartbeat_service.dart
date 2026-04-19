// lib/services/heartbeat_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HeartbeatService {
  static const _interval = Duration(seconds: 30);

  Timer? _timer;
  bool _bleConnected = false;
  int _heartRate = 0;
  bool _isArrhythmia = false;
  String _arrhythmiaLabel = 'Normal sinus';

  void start() {
    _timer = Timer.periodic(_interval, (_) => _ping());
  }

  void setConnected(bool connected) {
    _bleConnected = connected;
    _ping();
  }

  /// Called by EcgDashboard on each analysis window — values are picked up
  /// by the next periodic ping (no immediate write to avoid Firestore spam).
  void updateEcgStats({
    required int heartRate,
    required bool isArrhythmia,
    required String arrhythmiaLabel,
  }) {
    _heartRate = heartRate;
    _isArrhythmia = isArrhythmia;
    _arrhythmiaLabel = arrhythmiaLabel;
  }

  Future<void> _ping() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final stats = {
      'lastHeartbeat': FieldValue.serverTimestamp(),
      'bleConnected': _bleConnected,
      'heartRate': _heartRate,
      'isArrhythmia': _isArrhythmia,
      'arrhythmiaLabel': _arrhythmiaLabel,
    };

    await Future.wait([
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(stats, SetOptions(merge: true)),
      FirebaseFirestore.instance.collection('userStatus').doc(user.uid).set({
        ...stats,
        'displayName': user.displayName ?? user.email ?? 'Unknown',
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    ]);
  }

  void dispose() {
    _timer?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final offline = {
        'bleConnected': false,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(offline, SetOptions(merge: true));
      FirebaseFirestore.instance
          .collection('userStatus')
          .doc(user.uid)
          .set(offline, SetOptions(merge: true));
    }
  }
}
