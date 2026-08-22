# google_mlkit_text_recognition (Aadhaar address autofill) bundles optional
# per-script recognizer variants (Chinese/Japanese/Korean/Devanagari) that
# this app never depends on directly — only the Latin-script one is used
# (see lib/features/apply/aadhaar_ocr.dart). R8 otherwise fails the release
# build over those unused classes; these are exactly the rules its own
# missing_rules.txt reports.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
