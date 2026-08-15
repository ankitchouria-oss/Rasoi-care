// Live technician GPS, read-only from the Customer app's side. The Partner
// (technician) app writes documents in exactly this shape — field names
// must match exactly for this to work:
//
//   technician_locations/{technicianId}
//     lat: double
//     lng: double
//     updatedAt: Firestore server timestamp
//
// Guarded the same way as UserProfileService
// (lib/data/firebase/firestore_user_profile_service.dart): a no-op / empty
// stream in mock mode (no Firebase project configured), and any failure —
// missing doc, permission error, offline — degrades to "no live location"
// rather than throwing. The tracking screen falls back to its static
// placeholder whenever this has nothing to show, gated by
// MapsConfig.isConfigured — see lib/core/config/maps_config.dart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class TechnicianLocation {
  const TechnicianLocation({required this.lat, required this.lng, this.updatedAt});
  final double lat;
  final double lng;
  final DateTime? updatedAt;
}

class TechnicianLocationService {
  /// Emits the technician's latest known position, or null when there's
  /// nothing to show (Firebase unconfigured, no doc yet, malformed data,
  /// or a stream error). Never throws.
  Stream<TechnicianLocation?> watchLocation(String technicianId) {
    if (Firebase.apps.isEmpty) return Stream.value(null); // mock mode
    try {
      return FirebaseFirestore.instance
          .collection('technician_locations')
          .doc(technicianId)
          .snapshots()
          .map<TechnicianLocation?>((snap) {
            final data = snap.data();
            if (data == null) return null;
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) return null;
            final ts = data['updatedAt'];
            return TechnicianLocation(
              lat: lat,
              lng: lng,
              updatedAt: ts is Timestamp ? ts.toDate() : null,
            );
          })
          .handleError((_) {}); // swallow — see file header
    } catch (_) {
      return Stream.value(null);
    }
  }
}
