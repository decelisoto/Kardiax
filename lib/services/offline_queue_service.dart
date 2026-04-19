// lib/services/offline_queue_service.dart
//
// Persists pending alert payloads to SharedPreferences when the device is
// offline and flushes them to Firestore once connectivity is restored.
// Alerts older than 5 minutes are logged as stale/dropped rather than sent,
// because a 5-minute-old cardiac alert is no longer actionable.

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineQueueService {
  static const _prefsKey = 'kardiax_pending_alerts';
  static const _maxStalenessMinutes = 5;

  StreamSubscription? _connectivitySub;

  void start() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) _flush();
    });
  }

  Future<void> enqueue(Map<String, dynamic> alert) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _load(prefs);
    alert['enqueuedAt'] = DateTime.now().toIso8601String();
    queue.add(jsonEncode(alert));
    await prefs.setStringList(_prefsKey, queue);
  }

  Future<void> _flush() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final prefs = await SharedPreferences.getInstance();
    final queue = _load(prefs);
    if (queue.isEmpty) return;

    final now = DateTime.now();
    final alertsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('alerts');

    for (final raw in queue) {
      final alert = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final enqueuedAt = DateTime.parse(alert.remove('enqueuedAt') as String);
      final stale =
          now.difference(enqueuedAt).inMinutes > _maxStalenessMinutes;

      await alertsRef.add({
        ...alert,
        'timestamp': FieldValue.serverTimestamp(),
        if (stale) 'dropped': true,
        if (stale) 'dropReason': 'stale_offline',
        // Stale alerts are logged but the Cloud Function won't notify circle
        // because circleNotified is overridden to false.
        if (stale) 'circleNotified': false,
      });
    }

    await prefs.setStringList(_prefsKey, []);
  }

  List<String> _load(SharedPreferences prefs) =>
      List<String>.from(prefs.getStringList(_prefsKey) ?? []);

  void dispose() => _connectivitySub?.cancel();
}
