import 'entities.dart';

/// Validation result for a parsed analysis payload.
class ValidationResult {
  const ValidationResult({required this.errors, required this.warnings});

  final List<String> errors;
  final List<String> warnings; // non-blocking (e.g. translation copy notes)

  bool get isValid => errors.isEmpty;

  @override
  String toString() =>
      'ValidationResult(isValid: $isValid, errors: $errors, warnings: $warnings)';
}

/// Hand-written validation mirroring `contracts/bantay-analysis.schema.json`
/// (no external schema dependency — rules kept 1:1 with the contract file).
///
/// Structural failures (enums, required fields, trilingual triplets) are
/// *errors*; quality observations (empty optional fields) are *warnings*.
/// Consumed by the enrichment pipeline (T019) and contract tests (T013).
class AnalysisValidator {
  const AnalysisValidator();

  static const String supportedSchemaVersion = '1.0';
  static const int maxSourceChars = 20000;
  static const int maxChecklistItems = 5;
  static const int maxWarnings = 10;

  ValidationResult validate(Map<String, dynamic> payload) {
    final errors = <String>[];
    final warnings = <String>[];

    void err(String message) => errors.add(message);

    // --- envelope ---------------------------------------------------------
    if (payload['schema_version'] != supportedSchemaVersion) {
      err('schema_version must be "$supportedSchemaVersion"');
    }
    if (payload['analysis_id'] is! String ||
        (payload['analysis_id'] as String).isEmpty) {
      err('analysis_id must be a non-empty string');
    }

    // --- source -----------------------------------------------------------
    final source = payload['source'];
    if (source is! Map<String, dynamic>) {
      err('source must be an object');
    } else {
      final type = source['type'];
      if (type != 'text' && type != 'ocr') {
        err('source.type must be "text" or "ocr"');
      }
      final text = source['text'];
      if (text is! String || text.isEmpty) {
        err('source.text must be a non-empty string');
      } else if (text.length > maxSourceChars) {
        err('source.text exceeds $maxSourceChars chars (intake must truncate)');
      }
    }

    // --- enums ------------------------------------------------------------
    const validTypes = ['FLOOD', 'FIRE', 'SECURITY', 'BLACKOUT', 'GENERAL'];
    if (!validTypes.contains(payload['crisis_type'])) {
      err('crisis_type must be one of $validTypes');
    }
    const validStates = ['ALERT', 'CAUTION', 'INFO'];
    if (!validStates.contains(payload['bantay_state'])) {
      err('bantay_state must be one of $validStates');
    }
    const validStatuses = ['skeleton', 'enriched', 'failed'];
    if (!validStatuses.contains(payload['status'])) {
      err('status must be one of $validStatuses');
    }

    // --- nullable strings (location/time) ---------------------------------
    for (final field in ['location', 'time_or_status', 'model_notice']) {
      final value = payload[field];
      if (value != null && value is! String) {
        err('$field must be a string or null');
      }
      if (value is String && value.trim().isEmpty) {
        warnings.add('$field is empty — prefer null when absent (FR-005)');
      }
    }

    // --- trilingual triplets ----------------------------------------------
    _validateTriplet(payload['summary'], 'summary', errors, required: true);
    _validateTriplet(payload['bantay_speech'], 'bantay_speech', errors,
        required: true);

    // --- action_checklist --------------------------------------------------
    final checklist = payload['action_checklist'];
    if (checklist is! List || checklist.isEmpty) {
      err('action_checklist must be a non-empty array');
    } else if (checklist.length > maxChecklistItems) {
      err('action_checklist must have at most $maxChecklistItems items');
    } else {
      for (var i = 0; i < checklist.length; i++) {
        final item = checklist[i];
        final label = 'action_checklist[$i]';
        if (item is! Map<String, dynamic>) {
          err('$label must be an object');
          continue;
        }
        if (item['id'] is! String || (item['id'] as String).isEmpty) {
          err('$label.id must be a non-empty string');
        }
        final priority = item['priority'];
        if (priority is! int || priority < 1) {
          err('$label.priority must be an integer >= 1');
        }
        if (!['template', 'llm'].contains(item['origin'])) {
          err('$label.origin must be "template" or "llm"');
        }
        if (!['pending', 'done'].contains(item['state'])) {
          err('$label.state must be "pending" or "done"');
        }
        _validateTriplet(item['text'], '$label.text', errors,
            required: true);
      }
      final priorities = checklist
          .whereType<Map<String, dynamic>>()
          .map((e) => e['priority'])
          .whereType<int>()
          .toList();
      if (priorities.length != checklist.length) {
        // priority errors already recorded above
      } else if (priorities.toSet().length != priorities.length) {
        err('action_checklist priorities must be unique');
      }
    }

    // --- missing_warnings ---------------------------------------------------
    final missing = payload['missing_warnings'];
    if (missing is! List) {
      err('missing_warnings must be an array');
    } else if (missing.length > maxWarnings) {
      err('missing_warnings must have at most $maxWarnings items');
    } else {
      const validCodes = ['EVAC_CENTER', 'HOTLINE', 'ZONE', 'OTHER'];
      for (var i = 0; i < missing.length; i++) {
        final item = missing[i];
        final label = 'missing_warnings[$i]';
        if (item is! Map<String, dynamic>) {
          err('$label must be an object');
          continue;
        }
        if (!validCodes.contains(item['code'])) {
          err('$label.code must be one of $validCodes');
        }
        if (!['fastpath', 'llm'].contains(item['origin'])) {
          err('$label.origin must be "fastpath" or "llm"');
        }
        _validateTriplet(item['text'], '$label.text', errors,
            required: true);
      }
    }

    return ValidationResult(errors: errors, warnings: warnings);
  }

  void _validateTriplet(
    Object? value,
    String label,
    List<String> errors, {
    required bool required,
  }) {
    if (value is! Map<String, dynamic>) {
      if (required) errors.add('$label must be an object with en/tl/ceb');
      return;
    }
    for (final lang in ['en', 'tl', 'ceb']) {
      final text = value[lang];
      if (text is! String || text.trim().isEmpty) {
        errors.add('$label.$lang must be a non-empty string (FR-009)');
      }
    }
  }

  /// Maps a validated contract payload into core domain fields.
  /// Returns null when validation fails (callers must check first).
  ({CrisisType crisisType, SeverityState severity})? toCoreFields(
      Map<String, dynamic> payload) {
    final result = validate(payload);
    if (!result.isValid) return null;
    return (
      crisisType: CrisisType.fromContract(payload['crisis_type'] as String),
      severity: SeverityState.fromContract(payload['bantay_state'] as String),
    );
  }
}
