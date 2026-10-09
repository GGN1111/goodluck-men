import '../domain/entities.dart';

/// Fast text intake (plan.md data flow: paste/OCR → raw string <50ms).
///
/// Provenance rules (FR-005):
/// - The raw text is NEVER reworded — only edge whitespace is trimmed; the
///   body is preserved verbatim so every extracted fact can be traced back
///   to `source_text`.
/// - Inputs beyond the contract limit (20,000 chars) are truncated with an
///   explicit notice flag — never silently (research R4 / edge cases).
class IntakeResult {
  const IntakeResult({
    required this.rawText,
    required this.effectiveText,
    required this.sourceType,
    required this.truncated,
    required this.isEmpty,
    this.notice,
  });

  final String rawText;
  final String effectiveText;
  final SourceType sourceType;
  final bool truncated;
  final bool isEmpty;

  /// Set when the input was cut (FR-014-friendly, shown to the user).
  final String? notice;
}

class IntakeService {
  static const int maxChars = 20000;

  /// Prepares pasted/typed text. O(n) trim — well under the 50ms budget.
  IntakeResult prepareText(String raw) =>
      _prepare(raw, SourceType.text);

  /// OCR output enters the same pipeline with `source_type = ocr`.
  IntakeResult prepareOcrText(String extracted) =>
      _prepare(extracted, SourceType.ocr);

  IntakeResult _prepare(String raw, SourceType type) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return IntakeResult(
        rawText: raw,
        effectiveText: '',
        sourceType: type,
        truncated: false,
        isEmpty: true,
      );
    }
    if (trimmed.length <= maxChars) {
      return IntakeResult(
        rawText: raw,
        effectiveText: trimmed,
        sourceType: type,
        truncated: false,
        isEmpty: false,
      );
    }
    return IntakeResult(
      rawText: raw,
      effectiveText: trimmed.substring(0, maxChars),
      sourceType: type,
      truncated: true,
      isEmpty: false,
      notice: 'Input exceeded $maxChars characters and was truncated.',
    );
  }
}
