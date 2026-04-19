// lib/screens/responder_screen.dart
//
// Shown to a circle member when they tap a cardiac-alert push notification.
// Lets them mark themselves as responding and call 911, and shows live
// status of other responders so everyone knows who's already on their way.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

class ResponderScreen extends StatefulWidget {
  final String alertId;
  final String userId; // patient's uid
  final String patientName;
  final String alertType;

  const ResponderScreen({
    super.key,
    required this.alertId,
    required this.userId,
    required this.patientName,
    required this.alertType,
  });

  @override
  State<ResponderScreen> createState() => _ResponderScreenState();
}

class _ResponderScreenState extends State<ResponderScreen> {
  bool _isResponding = false;
  bool _hasResponded = false;

  DocumentReference get _alertRef => FirebaseFirestore.instance
      .collection('users')
      .doc(widget.userId)
      .collection('alerts')
      .doc(widget.alertId);

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;
  String get _myName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      'Unknown';

  Future<void> _markResponding() async {
    setState(() => _isResponding = true);
    try {
      await _alertRef.update({
        'respondedBy': FieldValue.arrayUnion([
          {
            'uid': _myUid,
            'name': _myName,
            'respondedAt': Timestamp.now(),
          }
        ]),
      });
      setState(() => _hasResponded = true);
    } finally {
      setState(() => _isResponding = false);
    }
  }

  Future<void> _call911() async {
    final uri = Uri(scheme: 'tel', path: '911');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KardiaxColors.black,
      appBar: AppBar(
        backgroundColor: KardiaxColors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: KardiaxColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Emergency Alert',
            style: TextStyle(
                fontFamily: 'Oswald',
                color: KardiaxColors.red,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _alertRef.snapshots(),
        builder: (context, snapshot) {
          final data =
              snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final respondedBy =
              (data['respondedBy'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
          final alreadyResponded =
              respondedBy.any((r) => r['uid'] == _myUid);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Alert header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: KardiaxColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: KardiaxColors.red.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.favorite,
                          color: KardiaxColors.red, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        widget.patientName,
                        style: const TextStyle(
                            fontFamily: 'Oswald',
                            color: KardiaxColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(widget.alertType,
                          style: const TextStyle(
                              fontFamily: 'Oswald',
                              color: KardiaxColors.red,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('may need immediate help',
                          style: TextStyle(
                              fontFamily: 'Oswald',
                              color: KardiaxColors.textSecondary,
                              fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isResponding ||
                            alreadyResponded ||
                            _hasResponded
                        ? null
                        : _markResponding,
                    icon: _isResponding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Icon(
                            alreadyResponded || _hasResponded
                                ? Icons.check
                                : Icons.directions_run,
                            size: 20),
                    label: Text(
                      alreadyResponded || _hasResponded
                          ? "YOU'RE RESPONDING"
                          : "I'M ON MY WAY",
                      style: const TextStyle(
                          fontFamily: 'Oswald',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: alreadyResponded || _hasResponded
                          ? KardiaxColors.green
                          : KardiaxColors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _call911,
                    icon: const Icon(Icons.phone, size: 20),
                    label: const Text('CALL 911',
                        style: TextStyle(
                            fontFamily: 'Oswald',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KardiaxColors.red,
                      side: const BorderSide(
                          color: KardiaxColors.red, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Live responders list
                const Text('RESPONDERS',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5)),
                const SizedBox(height: 10),
                if (respondedBy.isEmpty)
                  const Text('No one has responded yet.',
                      style: TextStyle(
                          fontFamily: 'Oswald',
                          color: KardiaxColors.textHint,
                          fontSize: 13))
                else
                  ...respondedBy.map((r) {
                    final name = r['name'] as String? ?? 'Unknown';
                    final ts = r['respondedAt'] as Timestamp?;
                    final isMe = r['uid'] == _myUid;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: KardiaxColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: KardiaxColors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.directions_run,
                            color: KardiaxColors.green, size: 16),
                        const SizedBox(width: 10),
                        Text(
                          isMe ? '$name (you)' : name,
                          style: const TextStyle(
                              fontFamily: 'Oswald',
                              color: KardiaxColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (ts != null)
                          Text(
                            _elapsed(ts.toDate()),
                            style: const TextStyle(
                                fontFamily: 'Oswald',
                                color: KardiaxColors.textSecondary,
                                fontSize: 11),
                          ),
                      ]),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  String _elapsed(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}
