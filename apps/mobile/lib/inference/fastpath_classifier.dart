import '../domain/entities.dart';

/// Deterministic, sub-millisecond crisis classification (research R4,
/// Stage 1 fast path). Emits only facts extractable from the source text —
/// never invents details (FR-005).
///
/// Returned for the skeleton brief (≤2s, FR-013); the LLM enrichment later
/// confirms or raises severity but never silently downgrades an ALERT
/// (data-model severity rule).
class FastPathResult {
  const FastPathResult({
    required this.crisisType,
    required this.severity,
    this.location,
    this.timeOrStatus,
  });

  final CrisisType crisisType;
  final SeverityState severity;

  /// Verbatim substring of the source, or null when absent.
  final String? location;
  final String? timeOrStatus;
}

class FastPathClassifier {
  const FastPathClassifier();

  static final Map<String, RegExp> _wordCache = {};

  /// Word-boundary match: prevents "bahay" from matching "baha" and
  /// "babayaran" from matching anything crisis-related.
  static bool _word(String haystack, String word) {
    final re = _wordCache.putIfAbsent(
      word,
      () => RegExp(r'\b' + RegExp.escape(word) + r'\b'),
    );
    return re.hasMatch(haystack);
  }

  /// Returns null for empty / non-emergency input — the UI then shows
  /// "No emergency content detected" (spec edge cases, corpus no_emergency).
  FastPathResult? classify(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return null;

    final crisis = _classifyCrisis(t);
    if (crisis == null) return null;

    return FastPathResult(
      crisisType: crisis,
      severity: _classifySeverity(t),
      location: _extractLocation(text),
      timeOrStatus: _extractTime(text),
    );
  }

  // -------------------------------------------------------------------------
  // Crisis taxonomy (FR-002) — check order matters: FIRE → FLOOD →
  // BLACKOUT → SECURITY → GENERAL so mixed signals (e.g. "Feeder 4 trip.
  // Marikina 16.5m. Alarm 2.") resolve to the life-safety threat first.
  // -------------------------------------------------------------------------

  CrisisType? _classifyCrisis(String t) {
    if (_any(t, const [], words: ['sunog', 'nasunog', 'bumbero', 'fire', 'apoy'])) {
      return CrisisType.fire;
    }
    if (_any(t, const [
      'flood',
      'umapaw',
      'tsunami',
      'alarm 1',
      'alarm 2',
      'alarm 3',
    ], words: [
      'baha',
      'dam',
      'suba',
      'ilog',
      'river',
      'tubig',
      'marikina',
      'likayi',
    ])) {
      return CrisisType.flood;
    }
    if (_any(t, const [
      'blackout',
      'brownout',
      'outage',
      'feeder',
      'kuryente',
      'power interruption',
      'cut-off',
      'linya',
    ])) {
      return CrisisType.blackout;
    }
    if (_any(t, const [
      'lockdown',
      'armad', // intentional prefix: armadong/armed
      'nagnanakaw',
      'magnanakaw',
      'robbery',
      'hold-up',
      'nakawan',
      'pulis',
      'suspect',
      'security',
    ])) {
      return CrisisType.security;
    }
    if (_any(t, const [
      'landslide',
      'relief',
      'babala',
      'paunawa',
      'first aid',
    ])) {
      return CrisisType.general;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Severity (FR-003): INFO (resolution/utility markers) → ALERT (explicit
  // life-threat markers) → CAUTION (default: unverified/incomplete).
  // -------------------------------------------------------------------------

  SeverityState _classifySeverity(String t) {
    // Resolution / utility markers — checked first so "fire controlled,
    // no injuries" reads INFO and scheduled outages read INFO.
    if (_any(t, const [
      'kontrolado',
      'naapula',
      'walang nasaktan',
      'normal na ang',
      'scheduled',
      'linya maintenance',
      'maintenance',
      'relief goods',
    ])) {
      return SeverityState.info;
    }
    // Explicit life-threat markers (imperative evacuation, active threat,
    // casualties). Plain evacuation mentions are deliberately NOT triggers —
    // "Wala pang iniaanunsyong evacuation" must stay CAUTION (corpus
    // flood-03, nongov-01).
    if (_any(t, const [
      'lumikas',
      'ilikas',
      'evacuation order',
      'mandatory evacuation',
      'flash flood',
      'alarm 2',
      'alarm 3',
      'kumakalat',
    ], words: [
      'lockdown',
      'armad',
      'nasawi',
      'namatay',
      'likayi',
      'sunog',
      'apoy',
    ])) {
      return SeverityState.alert;
    }
    return SeverityState.caution;
  }

  // -------------------------------------------------------------------------
  // Provenance-safe extraction (SC-002): results are verbatim substrings.
  // -------------------------------------------------------------------------

  static final RegExp _zoneRe = RegExp(r'Zone\s*\d+', caseSensitive: false);
  static final RegExp _barangayRe =
      RegExp(r'Barangay\s+[A-Za-z]+', caseSensitive: false);
  static final RegExp _gateRe = RegExp(r'Gate\s*\d+', caseSensitive: false);
  static final RegExp _timeRe =
      RegExp(r'\b\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?\b');

  String? _extractLocation(String text) {
    for (final re in [_zoneRe, _barangayRe, _gateRe]) {
      final match = re.firstMatch(text);
      if (match != null) return match.group(0);
    }
    return null;
  }

  String? _extractTime(String text) => _timeRe.firstMatch(text)?.group(0);

  bool _any(String t, List<String> phrases, {List<String> words = const []}) =>
      phrases.any(t.contains) || words.any((w) => _word(t, w));
}
