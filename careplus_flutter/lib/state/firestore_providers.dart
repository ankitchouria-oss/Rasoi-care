import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase/firestore_user_profile_service.dart';

final userProfileServiceProvider =
    Provider<UserProfileService>((ref) => UserProfileService());
