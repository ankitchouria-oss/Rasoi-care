import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Uploads a technician's application photos (profile photo, ID document)
/// to Firebase Storage during signup — see TechApplyScreen. Returns null on
/// mock mode / not-signed-in / any upload failure; the caller (TechApplyScreen)
/// treats a null result for a photo that was actually picked as a hard
/// failure and blocks submission rather than silently dropping it — this
/// used to fail the exact same way with no error shown at all, so a
/// technician's application could reach "awaiting review" missing every
/// document they'd picked, with nothing telling them that had happened.
class TechnicianUploadService {
  Future<String?> upload(File file, {required String kind}) async {
    if (Firebase.apps.isEmpty) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final ext = file.path.split('.').last;
      final ref = FirebaseStorage.instance
          .ref('technician_applications/$uid/$kind.$ext');
      await ref.putFile(file).timeout(const Duration(seconds: 30));
      return await ref.getDownloadURL();
    } catch (e) {
      // Logged (not surfaced here — the caller shows the user-facing
      // error) so a Storage-rules/permission problem is diagnosable from
      // logs instead of just vanishing.
      debugPrint('TechnicianUploadService: upload of $kind failed — $e');
      return null;
    }
  }
}
