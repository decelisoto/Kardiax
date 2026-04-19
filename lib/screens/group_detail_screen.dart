// lib/screens/group_detail_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/group_service.dart';
import '../services/invite_service.dart';
import '../theme.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String initialName;

  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.initialName,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      'Someone';

  void _showInviteSheet(String groupId, String groupName, String inviteCode) {
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KardiaxColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Invite by email',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: KardiaxColors.textPrimary)),
                const SizedBox(height: 4),
                const Text(
                    'If they have a Kardiax account, they\'ll get an in-app invite.',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: emailCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'email@example.com',
                    hintStyle: const TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textHint),
                    prefixIcon: const Icon(Icons.mail_outline,
                        color: KardiaxColors.gray, size: 18),
                    filled: true,
                    fillColor: KardiaxColors.input,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: KardiaxColors.gray
                                .withValues(alpha: 0.3))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: KardiaxColors.gray
                                .withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: KardiaxColors.red, width: 1.5)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter an email';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: loading
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheet(() => loading = true);
                            try {
                              final profile =
                                  await InviteService.createGroupInvite(
                                groupId: groupId,
                                groupName: groupName,
                                inviteCode: inviteCode,
                                toEmail: emailCtrl.text.trim(),
                                fromName: _displayName,
                              );
                              if (!mounted) return;
                              Navigator.pop(context);
                              if (profile != null) {
                                final name = profile['displayName']
                                        as String? ??
                                    emailCtrl.text.trim();
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                      'Invite sent to $name',
                                      style: const TextStyle(
                                          fontFamily: 'Oswald')),
                                  backgroundColor: KardiaxColors.green,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ));
                              } else {
                                // No Kardiax account — show invite code to share
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: KardiaxColors.card,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    title: const Text('No account found',
                                        style: TextStyle(
                                            fontFamily: 'Oswald',
                                            color:
                                                KardiaxColors.textPrimary,
                                            fontWeight: FontWeight.w700)),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                            'This email doesn\'t have a Kardiax account yet. Share the invite code with them:',
                                            style: TextStyle(
                                                fontFamily: 'Oswald',
                                                color: KardiaxColors
                                                    .textSecondary,
                                                fontSize: 13)),
                                        const SizedBox(height: 16),
                                        Center(
                                          child: Text(inviteCode,
                                              style: const TextStyle(
                                                  fontFamily: 'Oswald',
                                                  color: KardiaxColors.red,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 6)),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context),
                                        child: const Text('OK',
                                            style: TextStyle(
                                                fontFamily: 'Oswald',
                                                color: KardiaxColors.red,
                                                fontWeight:
                                                    FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheet(() => loading = false);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('Error: $e',
                                    style: const TextStyle(
                                        fontFamily: 'Oswald')),
                                backgroundColor: KardiaxColors.red,
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KardiaxColors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('SEND INVITE',
                            style: TextStyle(
                                fontFamily: 'Oswald',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLeave(
      BuildContext ctx, bool isCreator, String groupName) async {
    final action = isCreator ? 'Delete' : 'Leave';
    final detail = isCreator
        ? 'This will permanently delete "$groupName" and remove all members.'
        : 'You\'ll be removed from "$groupName".';

    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: KardiaxColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$action group',
            style: const TextStyle(
                fontFamily: 'Oswald',
                color: KardiaxColors.textPrimary,
                fontWeight: FontWeight.w700)),
        content: Text(detail,
            style: const TextStyle(
                fontFamily: 'Oswald',
                color: KardiaxColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action,
                style: const TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.red,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    try {
      await GroupService.leaveGroup(widget.groupId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
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
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .snapshots(),
      builder: (context, groupSnap) {
        if (groupSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: KardiaxColors.black,
            body: Center(
                child: CircularProgressIndicator(color: KardiaxColors.red)),
          );
        }

        if (!groupSnap.hasData || !groupSnap.data!.exists) {
          return const Scaffold(
            backgroundColor: KardiaxColors.black,
            body: Center(
                child: Text('Group not found',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textSecondary))),
          );
        }

        final groupData = groupSnap.data!.data() as Map<String, dynamic>;
        final groupName = groupData['name'] as String? ?? widget.initialName;
        final inviteCode = groupData['inviteCode'] as String? ?? '';
        final createdBy = groupData['createdBy'] as String? ?? '';
        final isCreator = createdBy == _uid;
        final memberUids =
            List<String>.from(groupData['memberUids'] as List? ?? []);
        final membersMap =
            (groupData['members'] as Map<String, dynamic>?) ?? {};

        return Scaffold(
          backgroundColor: KardiaxColors.black,
          appBar: AppBar(
            backgroundColor: KardiaxColors.black,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios,
                  color: KardiaxColors.textPrimary, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(groupName,
                style: const TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.textPrimary)),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_outlined,
                    color: KardiaxColors.textPrimary, size: 20),
                tooltip: 'Invite by email',
                onPressed: () =>
                    _showInviteSheet(widget.groupId, groupName, inviteCode),
              ),
              TextButton.icon(
                onPressed: () =>
                    _confirmLeave(context, isCreator, groupName),
                icon: Icon(
                  isCreator ? Icons.delete_outline : Icons.exit_to_app,
                  color: KardiaxColors.red,
                  size: 18,
                ),
                label: Text(
                  isCreator ? 'Delete' : 'Leave',
                  style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.red,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Invite code banner ────────────────────────────────────────
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Invite code copied!',
                        style: TextStyle(fontFamily: 'Oswald')),
                    backgroundColor: KardiaxColors.green,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ));
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: KardiaxColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: KardiaxColors.gray.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.link,
                        color: KardiaxColors.textSecondary, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('INVITE CODE',
                              style: TextStyle(
                                  fontFamily: 'Oswald',
                                  color: KardiaxColors.textHint,
                                  fontSize: 10,
                                  letterSpacing: 1.5)),
                          Text(inviteCode,
                              style: const TextStyle(
                                  fontFamily: 'Oswald',
                                  color: KardiaxColors.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 4)),
                        ],
                      ),
                    ),
                    const Icon(Icons.copy,
                        color: KardiaxColors.textHint, size: 16),
                  ]),
                ),
              ),

              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text('MEMBERS',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textHint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5)),
              ),

              // ── Live member stats ─────────────────────────────────────────
              Expanded(
                child: memberUids.isEmpty
                    ? const Center(
                        child: Text('No members yet',
                            style: TextStyle(
                                fontFamily: 'Oswald',
                                color: KardiaxColors.textSecondary)))
                    : StreamBuilder<QuerySnapshot>(
                        stream:
                            GroupService.memberStatuses(memberUids),
                        builder: (context, statusSnap) {
                          final statusMap = <String,
                              Map<String, dynamic>>{};
                          if (statusSnap.hasData) {
                            for (final doc
                                in statusSnap.data!.docs) {
                              statusMap[doc.id] =
                                  doc.data() as Map<String, dynamic>;
                            }
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            itemCount: memberUids.length,
                            itemBuilder: (context, i) {
                              final uid = memberUids[i];
                              final memberInfo = (membersMap[uid]
                                      as Map<String, dynamic>?) ??
                                  {};
                              final displayName =
                                  memberInfo['displayName']
                                      as String? ??
                                  'Unknown';
                              final role =
                                  memberInfo['role'] as String? ??
                                  'member';
                              final status = statusMap[uid];

                              return _MemberCard(
                                uid: uid,
                                displayName: displayName,
                                role: role,
                                isCurrentUser: uid == _uid,
                                status: status,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  final String uid;
  final String displayName;
  final String role;
  final bool isCurrentUser;
  final Map<String, dynamic>? status;

  const _MemberCard({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.isCurrentUser,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final bleConnected = status?['bleConnected'] as bool? ?? false;
    final heartRate = status?['heartRate'] as int? ?? 0;
    final isArrhythmia = status?['isArrhythmia'] as bool? ?? false;
    final arrhythmiaLabel =
        status?['arrhythmiaLabel'] as String? ?? 'Normal sinus';
    final lastSeen = status?['lastSeen'] as Timestamp?;

    final bool isOnline = lastSeen != null &&
        DateTime.now()
                .difference(lastSeen.toDate())
                .inMinutes <
            2;

    final statusColor = isArrhythmia
        ? KardiaxColors.red
        : bleConnected
            ? KardiaxColors.green
            : KardiaxColors.gray;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KardiaxColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isArrhythmia
                ? KardiaxColors.red.withValues(alpha: 0.4)
                : KardiaxColors.gray.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        // ── Avatar with online dot ──────────────────────────────────────
        Stack(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty
                    ? displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    color: statusColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? KardiaxColors.green : KardiaxColors.gray,
                shape: BoxShape.circle,
                border: Border.all(color: KardiaxColors.card, width: 2),
              ),
            ),
          ),
        ]),

        const SizedBox(width: 12),

        // ── Name + role + arrhythmia label ─────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(
                  isCurrentUser ? '$displayName (you)' : displayName,
                  style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                if (role == 'admin') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: KardiaxColors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('ADMIN',
                        style: TextStyle(
                            fontFamily: 'Oswald',
                            color: KardiaxColors.red,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ),
                ],
              ]),
              Text(
                bleConnected ? arrhythmiaLabel : 'Device not connected',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    color: isArrhythmia
                        ? KardiaxColors.red
                        : KardiaxColors.textSecondary,
                    fontSize: 12),
              ),
            ],
          ),
        ),

        // ── Heart rate ──────────────────────────────────────────────────
        if (bleConnected && heartRate > 0)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(children: [
                Icon(Icons.favorite,
                    color: isArrhythmia
                        ? KardiaxColors.red
                        : KardiaxColors.textSecondary,
                    size: 12),
                const SizedBox(width: 4),
                Text(
                  '$heartRate',
                  style: TextStyle(
                      fontFamily: 'Oswald',
                      color: isArrhythmia
                          ? KardiaxColors.red
                          : KardiaxColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
              ]),
              const Text('BPM',
                  style: TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.textHint,
                      fontSize: 9,
                      letterSpacing: 1)),
            ],
          )
        else
          const Icon(Icons.bluetooth_disabled,
              color: KardiaxColors.gray, size: 18),
      ]),
    );
  }
}
