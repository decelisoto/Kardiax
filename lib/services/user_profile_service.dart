// lib/services/user_profile_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfileService {
  static final _db = FirebaseFirestore.instance;

  /// Creates /userProfiles/{uid} if it doesn't exist yet.
  /// Safe to call on every login — no-ops if the doc already exists.
  static Future<void> ensureProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final profileRef = _db.collection('userProfiles').doc(user.uid);
    final snap = await profileRef.get();
    if (snap.exists) return;

    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!
        : user.email!.split('@').first;

    final batch = _db.batch();
    batch.set(profileRef, {
      'displayName': displayName,
      'email': user.email!.toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Seed the private user doc so subcollections can be created.
    batch.set(
      _db.collection('users').doc(user.uid),
      {'createdAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Creates /userProfiles/{uid} during registration.
  static Future<void> createProfile({
    required String uid,
    required String displayName,
    required String email,
  }) async {
    final batch = _db.batch();
    batch.set(_db.collection('userProfiles').doc(uid), {
      'displayName': displayName,
      'email': email.toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _db.collection('users').doc(uid),
      {'createdAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await batch.commit();
  }
}
