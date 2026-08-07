import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Best-effort profile write-through to Firestore, called once right after
/// a successful sign-in (any method). Never blocks getting into the job
/// feed: in mock mode (no Firebase project configured yet) or if the write
/// fails for any reason, this is a silent no-op.
class TechnicianProfileService {
  Future<void> touchProfile() async {
    if (Firebase.apps.isEmpty) return; // mock mode — nothing to write to
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('technicians').doc(user.uid).set({
        'phone': user.phoneNumber,
        'email': user.email,
        'lastSignInAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort — a Firestore hiccup shouldn't block a technician from
      // getting to their job feed.
    }
  }
}
