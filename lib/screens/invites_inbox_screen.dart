// lib/screens/invites_inbox_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/invite_service.dart';
import '../theme.dart';

class InvitesInboxScreen extends StatelessWidget {
  const InvitesInboxScreen({super.key});

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
                text: 'Circle ',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.textPrimary)),
            TextSpan(
                text: 'Invites',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.red)),
          ]),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: KardiaxColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: KardiaxColors.red.withValues(alpha: 0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: KardiaxColors.red, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Accepting an invite adds you to someone\'s circle or group.',
                  style: TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.textSecondary,
                      fontSize: 12),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: InviteService.pendingInvites(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: KardiaxColors.red));
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.mail_outline,
                            color: KardiaxColors.gray, size: 48),
                        SizedBox(height: 12),
                        Text('No pending invites',
                            style: TextStyle(
                                fontFamily: 'Oswald',
                                color: KardiaxColors.textSecondary,
                                fontSize: 15)),
                        SizedBox(height: 6),
                        Text(
                            'When someone invites you to their circle\nor group, you\'ll see it here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Oswald',
                                color: KardiaxColors.textHint,
                                fontSize: 13)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final type =
                        data['type'] as String? ?? 'circleInvite';
                    final fromName =
                        data['fromName'] as String? ?? 'Someone';
                    final groupName =
                        data['groupName'] as String?;

                    return _InviteCard(
                      token: doc.id,
                      fromName: fromName,
                      isGroupInvite: type == 'groupInvite',
                      groupName: groupName,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatefulWidget {
  final String token;
  final String fromName;
  final bool isGroupInvite;
  final String? groupName;

  const _InviteCard({
    required this.token,
    required this.fromName,
    required this.isGroupInvite,
    this.groupName,
  });

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  bool _loading = false;

  Future<void> _respond(bool accept) async {
    setState(() => _loading = true);
    try {
      if (accept) {
        if (widget.isGroupInvite) {
          await InviteService.acceptGroupInvite(widget.token);
        } else {
          await InviteService.acceptCircleInvite(widget.token);
        }
      } else {
        await InviteService.declineInvite(widget.token);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            accept
                ? widget.isGroupInvite
                    ? 'Joined ${widget.groupName ?? 'group'}'
                    : 'Added to ${widget.fromName}\'s circle'
                : 'Invite declined',
            style: const TextStyle(fontFamily: 'Oswald'),
          ),
          backgroundColor:
              accept ? KardiaxColors.green : KardiaxColors.gray,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: 'Oswald')),
          backgroundColor: KardiaxColors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isGroupInvite
        ? 'wants you to join "${widget.groupName ?? 'a group'}"'
        : 'wants to add you to their circle';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KardiaxColors.card,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: KardiaxColors.gray.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: KardiaxColors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.fromName.isNotEmpty
                      ? widget.fromName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.red,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.fromName,
                      style: const TextStyle(
                          fontFamily: 'Oswald',
                          color: KardiaxColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  Text(label,
                      style: const TextStyle(
                          fontFamily: 'Oswald',
                          color: KardiaxColors.textSecondary,
                          fontSize: 12)),
                ],
              ),
            ),
            if (widget.isGroupInvite)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: KardiaxColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('GROUP',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.red,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
              ),
          ]),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(
                    color: KardiaxColors.red, strokeWidth: 2))
          else
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KardiaxColors.textSecondary,
                    side: BorderSide(
                        color: KardiaxColors.gray.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(fontFamily: 'Oswald')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _respond(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KardiaxColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    widget.isGroupInvite ? 'Join' : 'Accept',
                    style: const TextStyle(
                        fontFamily: 'Oswald',
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}
