import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase/firestore_user_profile_service.dart';
import '../data/firebase/technician_location_service.dart';

final userProfileServiceProvider =
    Provider<UserProfileService>((ref) => UserProfileService());

final technicianLocationServiceProvider =
    Provider<TechnicianLocationService>((ref) => TechnicianLocationService());

/// Live location for a single technician, keyed by technician id — see
/// TrackingScreen in lib/features/tracking/tracking_screen.dart.
final technicianLocationProvider =
    StreamProvider.autoDispose.family<TechnicianLocation?, String>(
  (ref, technicianId) =>
      ref.watch(technicianLocationServiceProvider).watchLocation(technicianId),
);
