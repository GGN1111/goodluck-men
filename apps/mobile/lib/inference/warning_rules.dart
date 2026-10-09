import '../domain/entities.dart';

/// T030 — Fast-path missing-information rules (FR-004, research R4 Stage 1,
/// quickstart V2).
///
/// Deterministic, corpus-validated detectors that flag critical details the
/// source **genuinely omits** — never what it merely phrases differently
/// (FR-005: zero fabricated warnings, SC-002). Warnings are emitted at
/// skeleton time so the red flags render in ≤2s alongside the fast brief;
/// LLM `missing_warnings` merge alongside them in T032.
class WarningRules {
  const WarningRules();

  // --- trilingual copy (FR-009) — absence statements only, no facts -------

  static const LocalizedText _evacCenter = LocalizedText(
    en: 'No evacuation center is named in the notice — confirm your '
        'destination with barangay officials before leaving.',
    tl: 'Walang tinukoy na evacuation center sa anunsyo — kumpirmahin ang '
        'inyong destinasyon sa barangay bago umalis.',
    ceb: 'Walay gisulti nga evacuation center sa pahibalo — kompirmaha ang '
        'inyong destinasyon sa barangay una mogawas.',
  );

  static const LocalizedText _hotline = LocalizedText(
    en: 'No official hotline or contact number appears in the notice.',
    tl: 'Walang opisyal na hotline o numero ng kontak sa anunsyo.',
    ceb: 'Walay opisyal nga hotline o numero sa pahibalo.',
  );

  static const LocalizedText _zone = LocalizedText(
    en: 'The affected zone or area is not specified in the notice.',
    tl: 'Walang tinukoy na zone o apektadong lugar sa anunsyo.',
    ceb: 'Walay gisulti nga zone o apektadong lugar sa pahibalo.',
  );

  static const LocalizedText _other = LocalizedText(
    en: 'Key detail missing: no restoration time or full context — treat '
        'further updates as unconfirmed.',
    tl: 'Kulang ang mahalagang detalye: walang oras ng pagbabalik o buong '
        'konteksto — ituring na hindi kumpirmado ang susunod na update.',
    ceb: 'Kulang ang mahinungdanong detalye: walay orasan sa pagbalik o '
        'tibuok konteksto — tinguhaa nga dili kompirmado ang sunod.',
  );

  /// Emits warnings for genuinely omitted details applicable to [crisisType].
  ///
  /// Corpus-derived applicability (tests/corpus `required_warning_codes`):
  /// - INFO utility/resolution updates carry **no** red flags — except a
  ///   GENERAL notice still needs a hotline (relief distribution, etc.).
  /// - FLOOD: evacuation center + hotline + affected zone.
  /// - FIRE: affected/exclusion zone + hotline (an incident address is not
  ///   an evacuation zone).
  /// - SECURITY: zone + hotline.
  /// - BLACKOUT: hotline + restoration ETA (OTHER when absent).
  /// - GENERAL: hotline always; zone unless INFO.
  List<MissingWarning> detect({
    required CrisisType crisisType,
    required SeverityState severity,
    required String sourceText,
    required int incidentId,
  }) {
    final warnings = <MissingWarning>[];
    void add(WarningCode code, LocalizedText text) => warnings.add(
          MissingWarning(
            incidentId: incidentId,
            code: code,
            text: text,
            origin: WarningOrigin.fastpath,
          ),
        );

    final hasHotline = _hasHotline(sourceText);

    if (severity == SeverityState.info) {
      if (crisisType == CrisisType.general && !hasHotline) {
        add(WarningCode.hotline, _hotline);
      }
      return warnings;
    }

    switch (crisisType) {
      case CrisisType.flood:
        if (!_hasEvacCenter(sourceText)) add(WarningCode.evacCenter, _evacCenter);
        if (!hasHotline) add(WarningCode.hotline, _hotline);
        if (!_hasZone(sourceText)) add(WarningCode.zone, _zone);
      case CrisisType.fire:
        if (!_hasFireZone(sourceText)) add(WarningCode.zone, _zone);
        if (!hasHotline) add(WarningCode.hotline, _hotline);
      case CrisisType.security:
        if (!_hasZone(sourceText)) add(WarningCode.zone, _zone);
        if (!hasHotline) add(WarningCode.hotline, _hotline);
      case CrisisType.blackout:
        if (!hasHotline) add(WarningCode.hotline, _hotline);
        if (!_hasRestorationEta(sourceText)) add(WarningCode.other, _other);
      case CrisisType.general:
        if (!hasHotline) add(WarningCode.hotline, _hotline);
        if (!_hasZone(sourceText)) add(WarningCode.zone, _zone);
    }
    return warnings;
  }

  // --- presence detectors --------------------------------------------------

  /// Hotline/contact given: keyword, PH mobile, landline, or 911.
  static final RegExp _hotlineWord = RegExp(r'\bhotline\b', caseSensitive: false);
  static final RegExp _mobile = RegExp(r'\b09\d{2}[- ]?\d{3}[- ]?\d{4}\b');
  static final RegExp _landline = RegExp(r'\b\d{1,4}-\d{3}-\d{4}\b');
  static final RegExp _emergency911 = RegExp(r'\b911\b');

  bool _hasHotline(String text) =>
      _hotlineWord.hasMatch(text) ||
      _mobile.hasMatch(text) ||
      _landline.hasMatch(text) ||
      _emergency911.hasMatch(text);

  /// Evacuation center given — negation-aware so "Walang nakalagay na
  /// evacuation center" reads as *absent*, not present (corpus mixed-01).
  static final RegExp _evacCenterPos =
      RegExp(r'\b(evacuation|evac)\s+cent(er|re)\b', caseSensitive: false);
  static final RegExp _evacCenterNeg = RegExp(
      r'\b(walang|wala|walay|no|none|without)\b[^.!?\n]{0,60}\b(evacuation|evac)\s+cent(er|re)\b',
      caseSensitive: false);

  bool _hasEvacCenter(String text) =>
      _evacCenterPos.hasMatch(text) && !_evacCenterNeg.hasMatch(text);

  /// Zone/area designation for FLOOD/SECURITY/GENERAL: a `Zone N` in the
  /// source satisfies it (corpus flood-01, jargon-01, …).
  static final RegExp _zoneDesignation =
      RegExp(r'\bzone\s*\d', caseSensitive: false);

  /// FIRE variant: an incident "Zone N" is the *address*, not an evacuation
  /// zone — only an explicit affected/evacuation-zone phrase counts
  /// (corpus fire-03 requires the warning despite "Zone 7" in the address).
  static final RegExp _affectedZone = RegExp(
      r'\b(affected|evacuation|evac|danger|standoff|exclusion)\s+zone\b',
      caseSensitive: false);

  bool _hasZone(String text) => _zoneDesignation.hasMatch(text);

  bool _hasFireZone(String text) => _affectedZone.hasMatch(text);

  /// Blackout restoration ETA given (window or recovery wording, with
  /// negation handling for "Wala pang ... pagbabalik").
  static final RegExp _etaWindow =
      RegExp(r'\b(hanggang|until)\s+\d', caseSensitive: false);
  static final RegExp _etaWord = RegExp(
      r'\b(restore|restored|restoration|babalik|pagbabalik|estimated|resumption)\b',
      caseSensitive: false);
  static final RegExp _etaNegated = RegExp(
      r'\b(wala|walang|walay|no)\b[^.!?\n]{0,50}\b(oras|pagbabalik|babalik|restore|estimated)',
      caseSensitive: false);

  bool _hasRestorationEta(String text) {
    if (_etaWindow.hasMatch(text)) return true;
    if (!_etaWord.hasMatch(text)) return false;
    return !_etaNegated.hasMatch(text);
  }
}
