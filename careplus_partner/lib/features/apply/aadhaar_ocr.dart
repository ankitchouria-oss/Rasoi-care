import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Best-effort address extraction from an Aadhaar card's back-side photo.
/// Aadhaar prints the holder's address (and the QR code) on the back, under
/// an "Address:" label followed by the street/locality/city/state/pincode,
/// ending at a 6-digit PIN code. On-device OCR reads whatever text it can
/// find; this then looks for that "Address:" marker and takes everything up
/// to (and including) the first 6-digit number after it as the address.
///
/// This is heuristic, not authoritative — a misaligned photo, glare, or an
/// unusual card layout can all produce a wrong or empty result, which is why
/// the caller always leaves the address field editable rather than treating
/// this as ground truth. Genuine automatic verification of the printed
/// address would need a government-linked eKYC/DigiLocker integration,
/// which needs its own business registration and isn't part of this.
Future<String?> extractAddressFromImage(File file) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final input = InputImage.fromFile(file);
    // The very first OCR call on a device downloads the on-device text
    // model over the network (Google Play Services fetches it lazily,
    // not at app install) — that first call fails outright rather than
    // just running slow, which reads as "OCR never works" on a technician's
    // first-ever application even though every later attempt succeeds
    // fine once the model's cached. One short-delay retry turns that
    // one-time failure into a normal success without the technician
    // having to notice or do anything.
    for (var attempt = 0; ; attempt++) {
      try {
        final result = await recognizer.processImage(input);
        return _parseAddress(result.text);
      } catch (e) {
        if (attempt > 0) rethrow;
        debugPrint('extractAddressFromImage: OCR failed, retrying once — $e');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  } catch (e) {
    // Still failing after the retry — most likely Play Services isn't
    // available at all, or there's no network to fetch the model over.
    // Caught, not rethrown: the caller falls back to the manual address
    // field, which is why this is only ever a convenience, never a
    // requirement.
    debugPrint('extractAddressFromImage: OCR failed — $e');
    return null;
  } finally {
    await recognizer.close();
  }
}

// "Address" spelled correctly is the strongest signal, but OCR frequently
// mangles it (missing/extra letters, a stray line break mid-word) — so this
// tolerates a handful of common misreads rather than requiring an exact
// match.
final _addressLabelRe = RegExp(r'ad{1,2}ress[:\s]*', caseSensitive: false);
final _pincodeRe = RegExp(r'\b\d{6}\b');

String? _parseAddress(String fullText) {
  final labelMatch = _addressLabelRe.firstMatch(fullText);
  if (labelMatch != null) {
    final afterLabel = fullText.substring(labelMatch.end);
    final pinMatch = _pincodeRe.firstMatch(afterLabel);
    final raw = pinMatch == null ? afterLabel : afterLabel.substring(0, pinMatch.end);
    final cleaned = _clean(raw);
    if (cleaned != null) return cleaned;
  }
  // No usable "Address" label found (or nothing followed it) — a 6-digit
  // PIN code is a much more OCR-reliable anchor than a word, so fall back
  // to whatever text sits in the few lines right before the first one
  // found anywhere in the card.
  final pinMatch = _pincodeRe.firstMatch(fullText);
  if (pinMatch == null) return null;
  final start = _windowStart(fullText, pinMatch.start);
  return _clean(fullText.substring(start, pinMatch.end));
}

/// Walks back at most 5 lines before [pinStart] so the fallback window
/// stays roughly address-sized rather than dragging in the name/DOB/other
/// fields that appear earlier on the card.
int _windowStart(String text, int pinStart) {
  var idx = pinStart;
  var linesSeen = 0;
  while (idx > 0 && linesSeen < 5) {
    idx--;
    if (text[idx] == '\n') linesSeen++;
  }
  return idx == 0 ? 0 : idx + 1;
}

String? _clean(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? null : cleaned;
}
