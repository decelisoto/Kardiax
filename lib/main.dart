import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/ble_connect_screen.dart';
import 'screens/responder_screen.dart';
import 'screens/invites_inbox_screen.dart';
import 'services/real_ble_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be registered before runApp so it works in the background/terminated state.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const KardiaxApp());
}

class KardiaxApp extends StatefulWidget {
  const KardiaxApp({super.key});

  @override
  State<KardiaxApp> createState() => _KardiaxAppState();
}

class _KardiaxAppState extends State<KardiaxApp> {
  late final RealBleService _ble = RealBleService();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint(
        'KardiaxApp initState (sharedBle=${identityHashCode(_ble).toRadixString(16)})',
      );
    }
    // Initialize FCM after the first frame so navigatorKey.currentContext is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kardiax',
      theme: KardiaxTheme.theme,
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      // Named routes used by NotificationService when routing FCM taps.
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/respond':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (_) => ResponderScreen(
                alertId: args['alertId'] as String,
                userId: args['userId'] as String,
                patientName: args['patientName'] as String? ?? 'Unknown',
                alertType: args['alertType'] as String? ?? 'Arrhythmia',
              ),
            );
          case '/invites':
            return MaterialPageRoute(
              builder: (_) => const InvitesInboxScreen(),
            );
          default:
            return null;
        }
      },
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (kDebugMode) {
            debugPrint(
              'KardiaxApp authStateChanges '
              '(state=${snapshot.connectionState}, hasData=${snapshot.hasData})',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFFFF3131)),
              ),
            );
          }
          if (snapshot.hasData) {
            return BleConnectScreen(bleService: _ble);
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
