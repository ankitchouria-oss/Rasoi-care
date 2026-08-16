import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// What AccountScreen shows for the signed-in person. All fields fall back
/// to whatever Firebase Auth itself knows (displayName/email/phoneNumber)
/// when the Firestore doc hasn't caught up yet or a field was never filled
/// in — see [UserProfileService.watchProfile].
class UserProfile {
  const UserProfile({
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
  });
  final String name;
  final String phone;
  final String email;
  final String address;
}

/// Best-effort profile write-through to Firestore, called once right after
/// someone finishes the "about you" step of registration. Never blocks
/// onboarding: in mock mode (no Firebase project configured yet) or if the
/// write fails for any reason, this is a silent no-op and the person still
/// gets into the app — see RegisterScreen in auth_screens.dart.
class UserProfileService {
  /// Live view of the signed-in person's profile — null in mock mode or
  /// when nobody's signed in, so AccountScreen knows to show its own demo
  /// fallback instead. Streamed (not a one-off get) so the screen updates
  /// the moment [saveProfile]'s write actually lands, rather than showing
  /// stale/blank fields if it's opened right after registration.
  Stream<UserProfile?> watchProfile() {
    if (Firebase.apps.isEmpty) return Stream.value(null);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(null);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      return UserProfile(
        name: (data?['name'] as String?)?.trim().isNotEmpty == true
            ? data!['name'] as String
            : (user.displayName ?? ''),
        phone: (data?['phone'] as String?) ?? (user.phoneNumber ?? ''),
        email: (data?['email'] as String?)?.trim().isNotEmpty == true
            ? data!['email'] as String
            : (user.email ?? ''),
        address: (data?['address'] as String?) ?? '',
      );
    });
  }

  Future<void> saveProfile({
    required String name,
    required String email,
    required String address,
    required Set<String> ownedAppliances,
  }) async {
    if (Firebase.apps.isEmpty) return; // mock mode — nothing to write to
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': email,
        'address': address,
        'phone': user.phoneNumber,
        'ownedAppliances': ownedAppliances.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 6));
    } catch (_) {
      // Profile is convenience data — a Firestore hiccup (including one
      // that would otherwise hang, e.g. no Firestore database created yet
      // in the console) shouldn't strand someone mid-onboarding. The
      // timeout above turns a silent hang into a catchable error here.
    }
  }
}
