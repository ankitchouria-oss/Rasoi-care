// GET /api/legal/{terms|privacy} — the real Terms of Service / Privacy
// Policy text served by the shared backend (see app.py). Best-effort, same
// failure handling as the rest of lib/data/api: returns null on any
// failure (backend not deployed, offline) rather than throwing.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

const _legalTimeout = Duration(seconds: 8);

Future<Map<String, dynamic>?> fetchLegalDocument(String kind) async {
  try {
    final res = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/api/legal/$kind'))
        .timeout(_legalTimeout);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
    }
  } catch (_) {
    // Best-effort — see file header.
  }
  return null;
}
