import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/entities.dart';

/// Result of one offline OCR attempt (US4, FR-007/014, contract A3).
///
/// Success carries the extracted text; failure carries the *preserved
/// source attempt* plus a trilingual "couldn't read + type/paste instead"
/// notice — never a fabricated brief.
class OcrResult {
  const OcrResult.success(this.text)
      : success = true,
        attempt = null,
        failureReason = null,
        notice = null;

  const OcrResult.failure({required this.attempt, required String reason})
      : success = false,
        text = null,
        failureReason = reason,
        notice = _fallbackNotice;

  final bool success;
  final String? text;

  /// FR-014: original input kept for retry even when extraction fails
  /// (image path, or `image_picker`/engine marker on tool errors).
  final String? attempt;
  final String? failureReason;

  /// Contract A3 fallback copy — always a complete EN/TL/CEB triplet.
  final LocalizedText? notice;

  static const LocalizedText _fallbackNotice = LocalizedText(
    en: "Couldn't read this image. Try a clearer photo, or type/paste the "
        'notice text instead.',
    tl: 'Hindi mabasa ang larawan. Kumuha ng mas malinaw na litrato, o '
        'i-type/paste na lamang ang teksto ng anunsyo.',
    ceb: 'Dili mabasa niining hulagway. Kuha ug mas klaro nga litrato, o '
        'i-type/ipaste na lang ang teksto sa pahibalo.',
  );
}

/// Seam over a text-extraction engine — defaults to ML Kit (research R6),
/// injected as a plain function in host tests (no plugin on the host).
typedef OcrEngine = Future<String> Function(String imagePath);

/// T034 — Offline OCR service (FR-007): ML Kit text recognition with a
/// ≤1s extraction budget (plan.md performance goals) and a failure path
/// that never fabricates a brief.
class OcrService {
  OcrService({OcrEngine? engine}) : _engine = engine ?? _mlKitExtract;

  final OcrEngine _engine;

  /// Fewer readable characters than this ⇒ unreadable image (blur,
  /// text-free) — fragments must never reach the analysis pipeline
  /// (spec US4 acceptance 2 / FR-007).
  static const int minReadableChars = 10;

  Future<OcrResult> extract(String imagePath) async {
    try {
      final raw = await _engine(imagePath);
      final text = _normalize(raw);
      if (text.length < minReadableChars) {
        return OcrResult.failure(
            attempt: imagePath, reason: 'no_readable_text');
      }
      return OcrResult.success(text);
    } catch (e) {
      return OcrResult.failure(attempt: imagePath, reason: 'ocr_error: $e');
    }
  }

  /// Tidy OCR noise only — no rewording (FR-005 provenance).
  static String _normalize(String raw) =>
      raw.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

  static Future<String> _mlKitExtract(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return recognized.text;
    } finally {
      await recognizer.close();
    }
  }
}
