import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Best-effort GPS write-through to Firestore while a technician is en route
/// to or working a job, so the Customer app's tracking screen can show them
/// live on a map — see `technician_location_reporter.dart` for when this
/// gets called.
///
/// Document shape is a fixed contract with the Customer app (do not change
/// without updating that side too):
///   technician_locations/{technician's Firebase Auth uid}
///     { lat: double, lng: double, updatedAt: server timestamp }
///
/// In mock mode (no Firebase project configured yet) or if the write fails
/// for any reason, this is a silent no-op — same rule as
/// [TechnicianProfileService.touchProfile]: background telemetry must never
/// block or crash the app.
class TechnicianLocationService {
  Future<void> pushLocation({required double lat, required double lng}) async {
    if (Firebase.apps.isEmpty) return; // mock mode — nothing to write to
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('technician_locations')
          .doc(uid)
          .set({
            'lat': lat,
            'lng': lng,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort — a Firestore hiccup (or a hang, e.g. no Firestore
      // database created yet) shouldn't affect the technician's workflow.
      // The timeout above turns a silent hang into a catchable error here.
    }
  }
}
