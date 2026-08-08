import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Best-effort profile write-through to Firestore, called once right after
/// someone finishes the "about you" step of registration. Never blocks
/// onboarding: in mock mode (no Firebase project configured yet) or if the
/// write fails for any reason, this is a silent no-op and the person still
/// gets into the app — see RegisterScreen in auth_screens.dart.
class UserProfileService {
  Future<void> saveProfile({
    required String name,
    required String email,
    required Set<String> ownedAppliances,
  }) async {
    if (Firebase.apps.isEmpty) return; // mock mode — nothing to write to
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': email,
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
