import 'dart:io';

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
    final result = await recognizer.processImage(input);
    return _parseAddress(result.text);
  } catch (_) {
    return null;
  } finally {
    await recognizer.close();
  }
}

final _addressLabelRe = RegExp(r'address[:\s]*', caseSensitive: false);
final _pincodeRe = RegExp(r'\d{6}');

String? _parseAddress(String fullText) {
  final labelMatch = _addressLabelRe.firstMatch(fullText);
  if (labelMatch == null) return null;
  final afterLabel = fullText.substring(labelMatch.end);
  final pinMatch = _pincodeRe.firstMatch(afterLabel);
  final raw = pinMatch == null ? afterLabel : afterLabel.substring(0, pinMatch.end);
  final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? null : cleaned;
}
