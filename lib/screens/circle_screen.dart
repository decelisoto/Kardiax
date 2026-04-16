// lib/screens/circle_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';

class CircleScreen extends StatefulWidget {
  const CircleScreen({super.key});

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> {
  final _nameController  = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey         = GlobalKey<FormState>();
  bool _isAdding = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference get _circleRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('circle');

  Future<void> _addMember() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isAdding = true);

    await _circleRef.add({
      'name':    _nameController.text.trim(),
      'email':   _emailController.text.trim(),
      'status':  'offline',
      'addedAt': FieldValue.serverTimestamp(),
    });

    _nameController.clear();
    _emailController.clear();
    setState(() => _isAdding = false);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _removeMember(String docId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KardiaxColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove member', style: TextStyle(
          fontFamily: 'Rajdhani', color: KardiaxColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('Remove $name from your circle?', style: const TextStyle(
          fontFamily: 'Rajdhani', color: KardiaxColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(
              fontFamily: 'Rajdhani', color: KardiaxColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(
              fontFamily: 'Rajdhani', color: KardiaxColors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true) await _circleRef.doc(docId).delete();
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KardiaxColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add circle member', style: TextStyle(
                fontFamily: 'Rajdhani', fontSize: 18,
                fontWeight: FontWeight.w700, color: KardiaxColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('They will be notified if your alarm fires.', style: TextStyle(
                fontFamily: 'Rajdhani', color: KardiaxColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 20),

              _FieldLabel('NAME'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(fontFamily: 'Rajdhani', color: KardiaxColors.textPrimary),
                decoration: _inputDecoration('Full name', Icons.person_outline),
                validator: (v) => v == null || v.isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),

              _FieldLabel('EMAIL'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontFamily: 'Rajdhani', color: KardiaxColors.textPrimary),
                decoration: _inputDecoration('email@example.com', Icons.mail_outline),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter an email';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isAdding ? null : _addMember,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KardiaxColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isAdding
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('ADD TO CIRCLE', style: TextStyle(
                          fontFamily: 'Rajdhani', fontSize: 14,
                          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Rajdhani', color: KardiaxColors.textHint),
      prefixIcon: Icon(icon, color: KardiaxColors.gray, size: 18),
      filled: true,
      fillColor: KardiaxColors.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: KardiaxColors.gray.withOpacity(0.3))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: KardiaxColors.gray.withOpacity(0.2))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: KardiaxColors.red, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: KardiaxColors.red.withOpacity(0.5))),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
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
        title: RichText(
          text: const TextSpan(children: [
            TextSpan(text: 'My ', style: TextStyle(
              fontFamily: 'Rajdhani', fontSize: 20,
              fontWeight: FontWeight.w700, color: KardiaxColors.textPrimary)),
            TextSpan(text: 'Circle', style: TextStyle(
              fontFamily: 'Rajdhani', fontSize: 20,
              fontWeight: FontWeight.w700, color: KardiaxColors.red)),
          ]),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: KardiaxColors.red, size: 24),
            onPressed: _showAddSheet,
          ),
          const SizedBox(width: 8),
        ],
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: KardiaxColors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KardiaxColors.red.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: KardiaxColors.red, size: 16),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'These people will be notified if your alarm fires and you don\'t cancel.',
                  style: TextStyle(fontFamily: 'Rajdhani',
                      color: KardiaxColors.textSecondary, fontSize: 12),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _circleRef.orderBy('addedAt').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: KardiaxColors.red));
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_outline,
                            color: KardiaxColors.gray, size: 48),
                        const SizedBox(height: 12),
                        const Text('No circle members yet', style: TextStyle(
                          fontFamily: 'Rajdhani',
                          color: KardiaxColors.textSecondary, fontSize: 15)),
                        const SizedBox(height: 6),
                        const Text('Tap + to add someone', style: TextStyle(
                          fontFamily: 'Rajdhani',
                          color: KardiaxColors.textHint, fontSize: 13)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc    = docs[i];
                    final data   = doc.data() as Map<String, dynamic>;
                    final name   = data['name']   as String? ?? 'Unknown';
                    final email  = data['email']  as String? ?? '';
                    final status = data['status'] as String? ?? 'offline';

                    final (statusColor, statusLabel) = switch (status) {
                      'nearby'    => (KardiaxColors.green, 'Nearby'),
                      'online'    => (KardiaxColors.amber, 'Online'),
                      'notifying' => (KardiaxColors.red,   'Notifying...'),
                      _           => (KardiaxColors.gray,  'Offline'),
                    };

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: KardiaxColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: status == 'notifying'
                                ? KardiaxColors.red.withOpacity(0.4)
                                : KardiaxColors.gray.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: KardiaxColors.red.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontFamily: 'Rajdhani', color: KardiaxColors.red,
                                fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(
                                fontFamily: 'Rajdhani',
                                color: KardiaxColors.textPrimary,
                                fontSize: 15, fontWeight: FontWeight.w700)),
                              Text(email, style: const TextStyle(
                                fontFamily: 'Rajdhani',
                                color: KardiaxColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withOpacity(0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 6, height: 6,
                                decoration: BoxDecoration(
                                    color: statusColor, shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Text(statusLabel, style: TextStyle(
                              fontFamily: 'Rajdhani', color: statusColor,
                              fontSize: 11, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _removeMember(doc.id, name),
                          child: const Icon(Icons.remove_circle_outline,
                              color: KardiaxColors.gray, size: 20),
                        ),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: KardiaxColors.red,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(
      fontFamily: 'Rajdhani', color: KardiaxColors.textSecondary,
      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5));
  }
}
