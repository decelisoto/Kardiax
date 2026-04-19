// lib/screens/circle_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/group_service.dart';
import '../theme.dart';
import 'group_detail_screen.dart';

class CircleScreen extends StatefulWidget {
  const CircleScreen({super.key});

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  late final Stream<QuerySnapshot> _groupsStream;

  @override
  void initState() {
    super.initState();
    _groupsStream = GroupService.myGroups();
  }

  // ── Create group ──────────────────────────────────────────────────────────

  void _showCreateSheet() {
    final nameCtrl = TextEditingController();
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
                const Text('Create group',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: KardiaxColors.textPrimary)),
                const SizedBox(height: 4),
                const Text(
                    'Give your circle a name. You\'ll get a shareable invite code.',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.textPrimary),
                  decoration: _inputDecoration(
                      'e.g. Family, Close Friends', Icons.group_outlined),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name' : null,
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
                              final id = await GroupService.createGroup(
                                  nameCtrl.text);
                              if (!mounted) return;
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GroupDetailScreen(
                                    groupId: id,
                                    initialName: nameCtrl.text.trim(),
                                  ),
                                ),
                              );
                            } catch (e) {
                              setSheet(() => loading = false);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e',
                                      style: const TextStyle(
                                          fontFamily: 'Oswald')),
                                  backgroundColor: KardiaxColors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
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
                        : const Text('CREATE GROUP',
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

  // ── Join group ────────────────────────────────────────────────────────────

  void _showJoinSheet() {
    final codeCtrl = TextEditingController();
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
                const Text('Join group',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: KardiaxColors.textPrimary)),
                const SizedBox(height: 4),
                const Text('Enter the 6-character invite code.',
                    style: TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: codeCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: const TextStyle(
                      fontFamily: 'Oswald',
                      color: KardiaxColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6),
                  decoration: _inputDecoration('XXXXXX', Icons.tag).copyWith(
                    counterText: '',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length != 6) {
                      return 'Enter the full 6-character code';
                    }
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
                              final groupId = await GroupService.joinGroup(
                                  codeCtrl.text);
                              if (!mounted) return;
                              // Get the group name to show in detail screen.
                              final snap = await FirebaseFirestore.instance
                                  .collection('groups')
                                  .doc(groupId)
                                  .get();
                              final name = (snap.data()?['name'] as String?) ??
                                  'Group';
                              if (!mounted) return;
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GroupDetailScreen(
                                    groupId: groupId,
                                    initialName: name,
                                  ),
                                ),
                              );
                            } catch (e) {
                              setSheet(() => loading = false);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString().contains('Invalid')
                                        ? 'Invalid invite code. Try again.'
                                        : 'Error: $e',
                                    style: const TextStyle(
                                        fontFamily: 'Oswald'),
                                  ),
                                  backgroundColor: KardiaxColors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
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
                        : const Text('JOIN GROUP',
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

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          fontFamily: 'Oswald', color: KardiaxColors.textHint),
      prefixIcon: Icon(icon, color: KardiaxColors.gray, size: 18),
      filled: true,
      fillColor: KardiaxColors.input,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: KardiaxColors.gray.withValues(alpha: 0.3))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: KardiaxColors.gray.withValues(alpha: 0.2))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: KardiaxColors.red, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: KardiaxColors.red.withValues(alpha: 0.5))),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        title: RichText(
          text: const TextSpan(children: [
            TextSpan(
                text: 'My ',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.textPrimary)),
            TextSpan(
                text: 'Circle',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KardiaxColors.red)),
          ]),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _groupsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: KardiaxColors.red));
          }

          if (snap.hasError) {
            return Center(
              child: Text('Error loading groups: ${snap.error}',
                  style: const TextStyle(
                      fontFamily: 'Oswald', color: KardiaxColors.textSecondary)),
            );
          }

          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return _EmptyState(
              onCreateTap: _showCreateSheet,
              onJoinTap: _showJoinSheet,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] as String? ?? 'Unnamed';
              final code = data['inviteCode'] as String? ?? '';
              final memberUids =
                  List<String>.from(data['memberUids'] as List? ?? []);
              final createdBy = data['createdBy'] as String? ?? '';
              final isCreator = createdBy == _uid;

              return _GroupCard(
                name: name,
                code: code,
                memberCount: memberUids.length,
                isCreator: isCreator,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupDetailScreen(
                      groupId: doc.id,
                      initialName: name,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      // ── Floating action buttons: Create + Join ──────────────────────────
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _Fab(
            icon: Icons.group_add,
            label: 'Join group',
            onTap: _showJoinSheet,
            small: true,
          ),
          const SizedBox(height: 12),
          _Fab(
            icon: Icons.add,
            label: 'Create group',
            onTap: _showCreateSheet,
            small: false,
          ),
        ],
      ),
    );
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  final String name;
  final String code;
  final int memberCount;
  final bool isCreator;
  final VoidCallback onTap;

  const _GroupCard({
    required this.name,
    required this.code,
    required this.memberCount,
    required this.isCreator,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KardiaxColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: KardiaxColors.gray.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: KardiaxColors.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.red,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(name,
                      style: const TextStyle(
                          fontFamily: 'Oswald',
                          color: KardiaxColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  if (isCreator) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
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
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.people_outline,
                      color: KardiaxColors.textHint, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                    style: const TextStyle(
                        fontFamily: 'Oswald',
                        color: KardiaxColors.textSecondary,
                        fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.tag,
                      color: KardiaxColors.textHint, size: 11),
                  const SizedBox(width: 3),
                  Text(code,
                      style: const TextStyle(
                          fontFamily: 'Oswald',
                          color: KardiaxColors.textHint,
                          fontSize: 12,
                          letterSpacing: 1.5)),
                ]),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              color: KardiaxColors.gray, size: 20),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  final VoidCallback onJoinTap;

  const _EmptyState(
      {required this.onCreateTap, required this.onJoinTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline,
                color: KardiaxColors.gray, size: 56),
            const SizedBox(height: 16),
            const Text('No groups yet',
                style: TextStyle(
                    fontFamily: 'Oswald',
                    color: KardiaxColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Create a group to monitor each other, or join one with an invite code.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Oswald',
                  color: KardiaxColors.textSecondary,
                  fontSize: 13),
            ),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onJoinTap,
                  icon: const Icon(Icons.group_add, size: 16),
                  label: const Text('Join',
                      style: TextStyle(fontFamily: 'Oswald')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KardiaxColors.textPrimary,
                    side: BorderSide(
                        color: KardiaxColors.gray.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onCreateTap,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create',
                      style: TextStyle(fontFamily: 'Oswald')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KardiaxColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool small;

  const _Fab({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.small,
  });

  @override
  Widget build(BuildContext context) {
    if (small) {
      return FloatingActionButton.extended(
        heroTag: label,
        onPressed: onTap,
        backgroundColor: KardiaxColors.card,
        foregroundColor: KardiaxColors.textPrimary,
        elevation: 2,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontFamily: 'Oswald', fontWeight: FontWeight.w600)),
      );
    }
    return FloatingActionButton.extended(
      heroTag: label,
      onPressed: onTap,
      backgroundColor: KardiaxColors.red,
      foregroundColor: Colors.white,
      icon: Icon(icon),
      label: Text(label,
          style: const TextStyle(
              fontFamily: 'Oswald',
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
    );
  }
}
