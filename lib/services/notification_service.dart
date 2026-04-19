// lib/services/notification_service.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

// Top-level handler required by firebase_messaging for background/terminated state.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

  // Assign this key to MaterialApp so we can navigate without a BuildContext.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> initialize() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    if (Platform.isIOS) {
      String? apnsToken;
      for (int i = 0; i < 5; i++) {
        apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      if (apnsToken == null) {
        debugPrint('NotificationService: APNS token unavailable, skipping FCM token fetch');
        return;
      }
    }

    await _refreshAndStoreToken();
    _messaging.onTokenRefresh.listen(_storeToken);

    FirebaseMessaging.onMessage.listen(_showBanner);
    FirebaseMessaging.onMessageOpenedApp.listen(_route);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _route(initial);
  }

  static Future<void> _refreshAndStoreToken() async {
    final token = await _messaging.getToken();
    if (token != null) await _storeToken(token);
  }

  static Future<void> _storeToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmToken': token,
      'email': user.email,
      'displayName': user.displayName ?? user.email,
    }, SetOptions(merge: true));
  }

  static void _showBanner(RemoteMessage msg) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final title = msg.notification?.title ?? 'Alert';
    final body = msg.notification?.body ?? '';
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontFamily: 'Oswald',
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            if (body.isNotEmpty)
              Text(body,
                  style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: Colors.white70,
                      fontSize: 12)),
          ],
        ),
        backgroundColor: KardiaxColors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () => _route(msg),
        ),
      ),
    );
  }

  static void _route(RemoteMessage msg) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    final type = msg.data['type'];
    if (type == 'cardiac_alert') {
      navigator.pushNamed('/respond', arguments: {
        'alertId': msg.data['alertId'],
        'userId': msg.data['userId'],
        'patientName': msg.data['patientName'],
        'alertType': msg.data['alertType'],
      });
    } else if (type == 'circle_invite') {
      navigator.pushNamed('/invites');
    }
  }
}
