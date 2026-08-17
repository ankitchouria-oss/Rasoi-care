import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Uploads a technician's application photos (profile photo, ID document)
/// to Firebase Storage during signup — see TechApplyScreen. Guarded the
/// same way as every other Firebase-backed service in this app: a no-op
/// (returns null) in mock mode or on any failure, so a storage hiccup
/// never strands someone mid-application.
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
    } catch (_) {
      return null;
    }
  }
}
