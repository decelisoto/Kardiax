// lib/services/group_service.dart

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupService {
  static final _db = FirebaseFirestore.instance;

  static String get _uid => FirebaseAuth.instance.currentUser!.uid;
  static String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      'Unknown';

  static String _generateCode() {
    // Avoids visually ambiguous chars (0/O, 1/I/L).
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Create a named group. Returns the new group's document ID.
  static Future<String> createGroup(String name) async {
    final code = _generateCode();

    final docRef = await _db.collection('groups').add({
      'name': name.trim(),
      'createdBy': _uid,
      'inviteCode': code,
      'memberUids': [_uid],
      'members': {
        _uid: {
          'displayName': _displayName,
          'role': 'admin',
          'joinedAt': FieldValue.serverTimestamp(),
        },
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Index invite code → groupId for O(1) join lookup.
    await _db.collection('groupInvites').doc(code).set({'groupId': docRef.id});

    return docRef.id;
  }

  /// Join a group by its 6-character invite code.
  static Future<String> joinGroup(String code) async {
    final codeSnap = await _db
        .collection('groupInvites')
        .doc(code.trim().toUpperCase())
        .get();
    if (!codeSnap.exists) throw Exception('Invalid invite code');

    final groupId = codeSnap.data()!['groupId'] as String;
    final groupRef = _db.collection('groups').doc(groupId);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw Exception('Group no longer exists');

    final memberUids =
        List<String>.from(groupSnap.data()!['memberUids'] as List);
    if (memberUids.contains(_uid)) throw Exception('Already in this group');

    await groupRef.update({
      'memberUids': FieldValue.arrayUnion([_uid]),
      'members.$_uid': {
        'displayName': _displayName,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      },
    });

    return groupId;
  }

  /// Leave a group. If you're the creator, the group is deleted entirely.
  static Future<void> leaveGroup(String groupId) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final snap = await groupRef.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final createdBy = data['createdBy'] as String;

    if (createdBy == _uid) {
      final code = data['inviteCode'] as String?;
      final batch = _db.batch();
      batch.delete(groupRef);
      if (code != null) {
        batch.delete(_db.collection('groupInvites').doc(code));
      }
      await batch.commit();
    } else {
      await groupRef.update({
        'memberUids': FieldValue.arrayRemove([_uid]),
        'members.$_uid': FieldValue.delete(),
      });
    }
  }

  /// Rename a group (admin only).
  static Future<void> renameGroup(String groupId, String newName) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .update({'name': newName.trim()});
  }

  /// Live stream of groups the current user belongs to.
  static Stream<QuerySnapshot> myGroups() {
    return _db
        .collection('groups')
        .where('memberUids', arrayContains: _uid)
        .orderBy('createdAt')
        .snapshots();
  }

  /// Live stream of `/userStatus` docs for a set of member UIDs.
  /// Returns null if [uids] is empty (no Firestore query needed).
  static Stream<QuerySnapshot>? memberStatuses(List<String> uids) {
    if (uids.isEmpty) return null;
    // Firestore whereIn supports up to 30 values; more than enough for circle groups.
    return _db
        .collection('userStatus')
        .where(FieldPath.documentId, whereIn: uids)
        .snapshots();
  }
}
