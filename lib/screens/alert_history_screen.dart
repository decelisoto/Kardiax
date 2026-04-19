// lib/screens/alert_history_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Stream<QuerySnapshot> get _alertsStream => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('alerts')
      .orderBy('timestamp', descending: true)
      .limit(100)
      .snapshots();

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
        title: RichText(
          text: const TextSpan(children: [
            TextSpan(
                text: 'Alert ',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.textPrimary)),
            TextSpan(
                text: 'History',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.red)),
          ]),
        ),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _alertsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child:
                    CircularProgressIndicator(color: KardiaxColors.red));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.history, color: KardiaxColors.gray, size: 48),
                  SizedBox(height: 12),
                  Text('No alerts yet',
                      style: TextStyle(
                          fontFamily: 'Oswald',
                          color: KardiaxColors.textSecondary,
                          fontSize: 15)),
                  SizedBox(height: 6),
                  Text('Fired and cancelled alarms will appear here.',
                      style: TextStyle(
                          fontFamily: 'Oswald',
                          color: KardiaxColors.textHint,
                          fontSize: 13)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return _AlertTile(data: data);
            },
          );
        },
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AlertTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final cancelled = data['cancelled'] as bool? ?? false;
    final dropped = data['dropped'] as bool? ?? false;
    final circleNotified = data['circleNotified'] as bool? ?? false;
    final type = data['type'] as String? ?? 'Unknown';
    final hr = data['hr'] as int? ?? 0;
    final confidence = ((data['confidence'] as num? ?? 0) * 100).toInt();
    final ts = data['timestamp'] as Timestamp?;
    final respondedBy =
        (data['respondedBy'] as List<dynamic>?)?.cast<Map>() ?? [];

    final (statusLabel, statusColor) = dropped
        ? ('Dropped (stale)', KardiaxColors.gray)
        : cancelled
            ? ('Cancelled', KardiaxColors.amber)
            : circleNotified
                ? ('Circle notified', KardiaxColors.red)
                : ('Logged', KardiaxColors.gray);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KardiaxColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(type,
                    style: const TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.35)),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _Chip(label: '$hr bpm', icon: Icons.favorite_outline),
              const SizedBox(width: 8),
              _Chip(
                  label: '$confidence% confidence',
                  icon: Icons.analytics_outlined),
              if (ts != null) ...[
                const SizedBox(width: 8),
                _Chip(
                    label: _formatTs(ts.toDate()),
                    icon: Icons.access_time_outlined),
              ],
            ],
          ),
          if (respondedBy.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Responded by: ${respondedBy.map((r) => r['name']).join(', ')}',
              style: const TextStyle(
                  fontFamily: 'Oswald',
                  color: KardiaxColors.green,
                  fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTs(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Chip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: KardiaxColors.textSecondary, size: 11),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Oswald',
                color: KardiaxColors.textSecondary,
                fontSize: 11)),
      ],
    );
  }
}
