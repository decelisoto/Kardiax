// lib/services/invite_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class InviteService {
  static final _db = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  static String get _uid => FirebaseAuth.instance.currentUser!.uid;
  static String get _email => FirebaseAuth.instance.currentUser!.email!;

  /// Look up a public profile by email. Returns a map with 'uid' + profile
  /// fields, or null if no Kardiax account exists for that email.
  static Future<Map<String, dynamic>?> lookupByEmail(String email) async {
    final q = await _db
        .collection('userProfiles')
        .where('email', isEqualTo: email.toLowerCase().trim())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return {'uid': q.docs.first.id, ...q.docs.first.data()};
  }

  /// Creates a circle invite and, if the recipient has no Kardiax account,
  /// calls the Cloud Function to send them an email/SMS.
  /// Pass [toUid] when the recipient already has an account.
  static Future<String> createCircleInvite({
    required String circleDocId,
    required String toEmail,
    required String toName,
    String? toPhone,
    required String fromName,
    String? toUid,
  }) async {
    final token = _uuid.v4();
    final expiresAt = DateTime.now().add(const Duration(days: 7));

    await _db.collection('invites').doc(token).set({
      'type': 'circleInvite',
      'fromUid': _uid,
      'fromName': fromName,
      'toEmail': toEmail,
      'toName': toName,
      'toPhone': toPhone,
      'toUid': toUid,
      'circleDocId': circleDocId,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'status': 'pending',
    });

    if (toUid == null) {
      try {
        await FirebaseFunctions.instance.httpsCallable('sendCircleInvite').call({
          'token': token,
          'toEmail': toEmail,
          'toPhone': toPhone,
          'toName': toName,
          'fromName': fromName,
        });
      } catch (_) {
        // Non-fatal — invite is in Firestore and visible in-app.
      }
    }

    return token;
  }

  /// Creates a group invite for an existing Kardiax user.
  /// Returns null if the email has no Kardiax account (caller shows invite code instead).
  static Future<Map<String, dynamic>?> createGroupInvite({
    required String groupId,
    required String groupName,
    required String inviteCode,
    required String toEmail,
    required String fromName,
  }) async {
    // Always check the DB first.
    final profile = await lookupByEmail(toEmail);
    if (profile == null) return null; // no account — caller handles fallback

    final token = _uuid.v4();
    await _db.collection('invites').doc(token).set({
      'type': 'groupInvite',
      'fromUid': _uid,
      'fromName': fromName,
      'toEmail': toEmail.toLowerCase().trim(),
      'toUid': profile['uid'],
      'groupId': groupId,
      'groupName': groupName,
      'inviteCode': inviteCode,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    return profile; // returns found profile so caller can show their name
  }

  /// Accept a circle invite — updates both the invite doc and the sender's circle doc.
  static Future<void> acceptCircleInvite(String token) async {
    final snap = await _db.collection('invites').doc(token).get();
    if (!snap.exists) throw Exception('Invite not found');

    final data = snap.data()!;
    final fromUid = data['fromUid'] as String;
    final circleDocId = data['circleDocId'] as String;

    final batch = _db.batch();
    batch.update(_db.collection('invites').doc(token), {
      'status': 'accepted',
      'acceptedByUid': _uid,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
    batch.update(
      _db.collection('users').doc(fromUid).collection('circle').doc(circleDocId),
      {
        'inviteStatus': 'accepted',
        'memberUid': _uid,
        'acceptedAt': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  /// Accept a group invite — joins the group and marks the invite accepted.
  static Future<void> acceptGroupInvite(String token) async {
    final snap = await _db.collection('invites').doc(token).get();
    if (!snap.exists) throw Exception('Invite not found');

    final inviteCode = snap.data()!['inviteCode'] as String;

    // joinGroup uses the invite code, which keeps the Firestore rules happy.
    // Import is avoided by inlining the join logic here to break circular deps.
    final codeSnap = await _db.collection('groupInvites').doc(inviteCode).get();
    if (!codeSnap.exists) throw Exception('Group no longer exists');

    final groupId = codeSnap.data()!['groupId'] as String;
    final groupRef = _db.collection('groups').doc(groupId);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw Exception('Group not found');

    final memberUids =
        List<String>.from(groupSnap.data()!['memberUids'] as List);
    final displayName =
        FirebaseAuth.instance.currentUser?.displayName ??
        FirebaseAuth.instance.currentUser?.email ??
        'Unknown';

    final batch = _db.batch();
    if (!memberUids.contains(_uid)) {
      batch.update(groupRef, {
        'memberUids': FieldValue.arrayUnion([_uid]),
        'members.$_uid': {
          'displayName': displayName,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        },
      });
    }
    batch.update(_db.collection('invites').doc(token), {
      'status': 'accepted',
      'acceptedByUid': _uid,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Decline any invite type.
  static Future<void> declineInvite(String token) async {
    final snap = await _db.collection('invites').doc(token).get();
    if (!snap.exists) throw Exception('Invite not found');

    final data = snap.data()!;
    final type = data['type'] as String? ?? 'circleInvite';
    final batch = _db.batch();

    batch.update(_db.collection('invites').doc(token), {
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
    });

    // For circle invites, also update the sender's circle doc.
    if (type == 'circleInvite') {
      final fromUid = data['fromUid'] as String;
      final circleDocId = data['circleDocId'] as String;
      batch.update(
        _db.collection('users').doc(fromUid).collection('circle').doc(circleDocId),
        {
          'inviteStatus': 'declined',
          'declinedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    await batch.commit();
  }

  /// Live stream of all pending invites for the current user's email.
  static Stream<QuerySnapshot> pendingInvites() {
    return _db
        .collection('invites')
        .where('toEmail', isEqualTo: _email)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  static Future<DocumentSnapshot> getInvite(String token) {
    return _db.collection('invites').doc(token).get();
  }
}
