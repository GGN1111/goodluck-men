import 'package:flutter/foundation.dart' show debugPrint;

import '../domain/analysis_validator.dart';
import 'bantay_prompt.dart';
import 'inference_types.dart';

/// Result of the two-attempt enrichment flow (research R3):
/// valid payload on success; failure notice + code when the model could not
/// produce schema-valid output (FR-014 degraded path).
class EnrichmentOutcome {
  const EnrichmentOutcome.success({
    required this.payload,
    required this.validation,
  })  : success = true,
        failureCode = null,
        failureNotice = null;

  const EnrichmentOutcome.failure({
    required String code,
    required String notice,
  })  : success = false,
        payload = null,
        validation = null,
        failureCode = code,
        failureNotice = notice;

  final bool success;
  final Map<String, dynamic>? payload;
  final ValidationResult? validation;
  final String? failureCode;
  final String? failureNotice;
}

/// T019 — Streamed generation → schema validation → single repair retry →
/// degraded failure (contracts/local-inference.md post-processing contract).
///
/// Envelope fields the model must not get wrong are normalized after decode
/// (analysis_id, source, status) — normalization is *not* fabrication: it
/// only re-states facts the caller already provided.
class EnrichmentPipeline {
  EnrichmentPipeline({required this.engine, this.validator = const AnalysisValidator()});

  final InferenceEngine engine;
  final AnalysisValidator validator;

  Future<EnrichmentOutcome> enrich({
    required String analysisId,
    required String sourceText,
    required SourceDescriptor source,
    void Function(String rawSoFar)? onProgress,
  }) async {
    var errors = <String>[];
    var lastCode = 'grammar_violation';

    // Attempt 1: enrich; Attempt 2: repair (research R3 — exactly one retry).
    for (var attempt = 0; attempt < 2; attempt++) {
      final isRepair = attempt == 1;
      final request = InferenceRequest(
        analysisId: analysisId,
        systemPrompt: kBantaySystemPrompt,
        userText: isRepair
            ? BantayPrompt.repairTurn(sourceText, errors)
            : BantayPrompt.userTurn(sourceText),
        sampling: kDefaultSampling,
        stage: isRepair ? InferenceStage.repair : InferenceStage.enrich,
        repairErrors: errors,
      );

      final (raw, engineFailure) = await _collect(engine.generateStream(request),
          onProgress: onProgress);
      if (raw == null) {
        // Engine-level failure — retrying through the same engine will not
        // help; degrade per FR-014 with the specific code.
        lastCode = engineFailure ?? lastCode;
        debugPrint('llm: enrichment abort attempt=$attempt code=$lastCode');
        return EnrichmentOutcome.failure(
          code: lastCode,
          notice: _noticeFor(lastCode),
        );
      }
      debugPrint('llm: raw bytes=${raw.length} attempt=$attempt');

      final payload = decodeAnalysisPayload(raw);
      if (payload == null) {
        lastCode = 'grammar_violation';
        errors = ['output was not parseable JSON'];
        debugPrint('llm: unparseable JSON attempt=$attempt raw=${raw.length}');
        continue;
      }

      _normalizeEnvelope(payload,
          analysisId: analysisId, source: source);
      final result = validator.validate(payload);
      if (result.isValid) {
        debugPrint('llm: enrichment VALID attempt=$attempt');
        return EnrichmentOutcome.success(payload: payload, validation: result);
      }
      lastCode = 'grammar_violation';
      errors = result.errors;
      debugPrint('llm: validation errors attempt=$attempt ${result.errors.take(3)}');
    }

    debugPrint('llm: enrichment exhausted both attempts code=$lastCode');

    return EnrichmentOutcome.failure(
      code: lastCode,
      notice:
          'Analysis limited: the on-device model could not produce valid '
          'output after a retry. The fast-path brief above is still reliable '
          'for classification. (${errors.take(3).join('; ')})',
    );
  }

  /// Consumes the engine stream, forwarding progress. Resolves
  /// `(raw, null)` on the first [CompletedEvent], else `(null, failureCode)`.
  Future<(String?, String?)> _collect(
    Stream<InferenceEvent> events, {
    void Function(String rawSoFar)? onProgress,
  }) async {
    String failureCode = 'lib_missing';
    await for (final event in events) {
      switch (event) {
        case TokenEvent(:final text):
          onProgress?.call(text);
        case ProgressEvent():
          break;
        case CompletedEvent(:final raw):
          return (raw, null);
        case FailedEvent(:final code):
          failureCode = code;
      }
    }
    return (null, failureCode);
  }

  void _normalizeEnvelope(
    Map<String, dynamic> payload, {
    required String analysisId,
    required SourceDescriptor source,
  }) {
    payload['schema_version'] = '1.0';
    payload['analysis_id'] = analysisId;
    payload['status'] = 'enriched';
    payload['source'] = {'type': source.type, 'text': source.text};
  }

  String _noticeFor(String code) {
    switch (code) {
      case 'model_missing':
        return 'AI model not installed — showing the fast-path brief only.';
      case 'oom':
        return 'Device out of memory for analysis — showing the fast-path brief only.';
      case 'timeout':
        return 'Analysis timed out — showing the fast-path brief only.';
      case 'cancelled':
        return 'Analysis cancelled.';
      default:
        return 'On-device analysis unavailable — showing the fast-path brief only.';
    }
  }
}

/// Source identity for envelope normalization (mirrors contract `source`).
class SourceDescriptor {
  const SourceDescriptor({required this.type, required this.text});
  final String type; // 'text' | 'ocr'
  final String text;
}
