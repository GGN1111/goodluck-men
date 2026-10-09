import '../domain/entities.dart';

/// T045 — Trilingual copy detection (research R5, US6).
///
/// The system prompt asks the model to translate rather than copy between
/// the `en`/`tl`/`ceb` fields, but a small on-device model sometimes emits
/// byte-identical text for two languages. Instead of failing the analysis,
/// we surface a warning badge so the user knows a translation may be
/// untranslated.
/// Human-readable warning appended to the brief (en only — the badge
/// carries the meaning, and this is a model-quality note not user copy).
const String kCopyCheckNotice =
    'Some translations look identical — verify the Tagalog/Cebuano copy.';

class TranslationCopyReport {
  const TranslationCopyReport({required this.duplicatePairs});

  /// Language pairs whose trimmed bytes are identical, e.g.
  /// `['en==tl', 'en==ceb']`. Empty when every language is distinct.
  final List<String> duplicatePairs;

  bool get hasCopies => duplicatePairs.isNotEmpty;

  String get notice => kCopyCheckNotice;
}

/// Language codes paired in the same order the report uses.
const List<(AppLanguage, AppLanguage)> _pairs = [
  (AppLanguage.en, AppLanguage.tl),
  (AppLanguage.en, AppLanguage.ceb),
  (AppLanguage.tl, AppLanguage.ceb),
];

String _code(AppLanguage l) => l.name;

/// Scans one triplet for byte-identical language pairs. Empty/blank fields
/// are ignored (an absent translation is not a copy).
TranslationCopyReport checkTranslationCopy(LocalizedText text) {
  final duplicates = <String>[];
  for (final (a, b) in _pairs) {
    final ta = text.forLang(a).trim();
    final tb = text.forLang(b).trim();
    if (ta.isEmpty || tb.isEmpty) continue;
    if (ta == tb) duplicates.add('${_code(a)}==${_code(b)}');
  }
  return TranslationCopyReport(duplicatePairs: duplicates);
}

/// Runs the check across every triplet on an enriched brief and merges the
/// findings into one report. The first non-empty notice wins.
TranslationCopyReport checkBrief(
  Iterable<LocalizedText> texts,
) {
  final all = <String>[];
  for (final t in texts) {
    all.addAll(checkTranslationCopy(t).duplicatePairs);
  }
  return TranslationCopyReport(duplicatePairs: all.toSet().toList());
}
