import 'dart:math';

import '../data/repositories/checklist_repository.dart';
import '../data/repositories/incident_repository.dart';
import '../data/repositories/warning_repository.dart';
import '../domain/entities.dart';
import '../inference/enrichment_pipeline.dart';
import '../inference/fastpath_classifier.dart';
import '../inference/latency_probe.dart';
import '../inference/merge_enriched.dart';
import '../inference/template_checklists.dart';
import '../inference/translation_copy_check.dart';
import '../inference/warning_rules.dart';
import '../ingest/intake.dart';

/// Result of one analysis run (spec US1).
sealed class AnalysisOutcome {
  const AnalysisOutcome();
}

/// Input held no emergency content — never a fabricated crisis
/// (spec edge cases; corpus `no_emergency`).
final class NoEmergencyOutcome extends AnalysisOutcome {
  const NoEmergencyOutcome();
}

/// Skeleton brief produced (and persisted); enrichment may or may not have
/// landed — see [enriched] and [notice].
final class AnalyzedOutcome extends AnalysisOutcome {
  const AnalyzedOutcome({
    required this.record,
    required this.steps,
    required this.skeletonMs,
    this.enrichmentMs,
    required this.enriched,
    this.notice,
    this.warnings = const [],
  });

  final IncidentRecord record;
  final List<ActionStep> steps;

  /// Missing-info red flags (FR-004): fast-path at skeleton time, LLM
  /// merged alongside after enrichment (T032).
  final List<MissingWarning> warnings;

  /// SC-001 first number — must be ≤2000ms.
  final int skeletonMs;

  /// SC-001 second number (research R4) — target p95 ≤15s.
  final int? enrichmentMs;

  final bool enriched;
  final String? notice;
}

/// T020 — Orchestrates research R4's two-stage pipeline:
/// intake → fast-path skeleton (≤2s, persisted) → streamed LLM enrichment
/// (validate → one repair → apply/fail) with separate latency marks.
class AnalyzeAdvisory {
  AnalyzeAdvisory({
    required this.intake,
    required this.classifier,
    required this.templates,
    required this.incidents,
    required this.steps,
    this.warnings,
    this.pipeline,
    this.warningRules = const WarningRules(),
  });

  final IntakeService intake;
  final FastPathClassifier classifier;
  final TemplateChecklists templates;
  final IncidentRepository incidents;
  final ChecklistRepository steps;

  /// Optional — null skips red-flag persistence entirely (pure-unit use).
  final WarningRepository? warnings;

  /// Null when the on-device model/engine is unavailable → skeleton-only.
  final EnrichmentPipeline? pipeline;

  /// Fast-path omission rules (FR-004) applied at skeleton time.
  final WarningRules warningRules;

  static final Random _rng = Random.secure();

  Future<AnalysisOutcome> call(
    String rawText, {
    SourceType sourceType = SourceType.text,
    void Function(AnalyzedOutcome skeleton)? onSkeletonReady,
    void Function(String rawSoFar)? onEnrichmentProgress,
  }) async {
    // --- Stage 0: intake (verbatim, truncation flagged — FR-005/014) ------
    final prepared = sourceType == SourceType.ocr
        ? intake.prepareOcrText(rawText)
        : intake.prepareText(rawText);
    if (prepared.isEmpty) return const NoEmergencyOutcome();

    // --- Stage 1: fast path (<100ms) --------------------------------------
    final fast = classifier.classify(prepared.effectiveText);
    if (fast == null) return const NoEmergencyOutcome();

    final probe = LatencyProbe();
    final analysisId = _newId();

    final skeletonTexts = _skeletonTexts(
      crisisType: fast.crisisType,
      severity: fast.severity,
      location: fast.location,
    );

    final draft = IncidentRecord(
      createdAt: DateTime.now(),
      sourceType: prepared.sourceType,
      sourceText: prepared.effectiveText,
      crisisType: fast.crisisType,
      severity: fast.severity,
      location: fast.location,
      timeOrStatus: fast.timeOrStatus,
      summary: skeletonTexts.summary,
      speech: skeletonTexts.speech,
      status: AnalysisStatus.skeleton,
      modelNotice: prepared.notice,
      analysisId: analysisId,
    );

    final recordId = await incidents.insert(draft);
    var stepRecords = <ActionStep>[
      for (final (i, text) in templates.forCrisis(fast.crisisType).indexed)
        ActionStep(
          incidentId: recordId,
          priority: i + 1,
          text: text,
          state: ChecklistStepState.pending,
          origin: StepOrigin.template,
        ),
    ];
    await steps.insertAll(stepRecords);

    // FR-004: fast-path red flags land with the skeleton (A1) so the amber
    // card renders in ≤2s — zero warnings for complete sources (FR-005).
    final warningRepo = warnings;
    var liveWarnings = const <MissingWarning>[];
    if (warningRepo != null) {
      final detected = warningRules.detect(
        crisisType: fast.crisisType,
        severity: fast.severity,
        sourceText: prepared.effectiveText,
        incidentId: recordId,
      );
      if (detected.isNotEmpty) {
        await warningRepo.insertAll(detected);
        liveWarnings = await warningRepo.forIncident(recordId);
      }
    }
    probe.markSkeleton();

    final skeleton = AnalyzedOutcome(
      record: draft.copyWith(id: recordId),
      steps: stepRecords,
      skeletonMs: probe.skeletonMs!,
      enriched: false,
      notice: prepared.notice,
      warnings: liveWarnings,
    );
    onSkeletonReady?.call(skeleton);

    // --- Stage 2: LLM enrichment (streamed) --------------------------------
    final activePipeline = pipeline;
    if (activePipeline == null) {
      return AnalyzedOutcome(
        record: skeleton.record,
        steps: stepRecords,
        skeletonMs: skeleton.skeletonMs,
        enriched: false,
        notice: prepared.notice ??
            'On-device model not ready — showing the fast-path brief.',
        warnings: liveWarnings,
      );
    }

    final enrichment = await activePipeline.enrich(
      analysisId: analysisId,
      sourceText: prepared.effectiveText,
      source: SourceDescriptor(
        type: prepared.sourceType.name,
        text: prepared.effectiveText,
      ),
      onProgress: onEnrichmentProgress,
    );

    if (!enrichment.success) {
      await incidents.markFailed(recordId,
          notice: enrichment.failureNotice ?? 'Analysis failed.');
      final failed = await incidents.getById(recordId);
      return AnalyzedOutcome(
        record: failed ?? skeleton.record,
        steps: stepRecords,
        skeletonMs: skeleton.skeletonMs,
        enriched: false,
        notice: enrichment.failureNotice,
        warnings: liveWarnings,
      );
    }

    final payload = enrichment.payload!;
    final enrichedFields = _fieldsFromPayload(payload);

    // Severity rule (data-model): LLM may raise or confirm, never downgrade.
    final severity = _raiseOnly(
        skeleton: fast.severity, llm: enrichedFields.severity);

    // T045: byte-identical "translations" (research R5) surface as a
    // model-quality notice + badge — never a silent untranslated line.
    final copyReport = checkBrief([
      enrichedFields.summary,
      enrichedFields.speech,
      for (final w in ((payload['missing_warnings'] as List?) ?? const [])
          .cast<Map<String, dynamic>>())
        LocalizedText.fromMap((w['text'] as Map).cast<String, Object?>()),
    ]);

    final qualityNotes = [
      if (enrichment.validation!.warnings.isNotEmpty)
        enrichment.validation!.warnings.join(' '),
      if (copyReport.hasCopies) copyReport.notice,
    ];

    await incidents.applyEnrichment(
      recordId,
      crisisType: enrichedFields.crisisType,
      severity: severity,
      location: enrichedFields.location ?? fast.location,
      timeOrStatus: enrichedFields.timeOrStatus ?? fast.timeOrStatus,
      summary: enrichedFields.summary,
      speech: enrichedFields.speech,
      modelNotice:
          prepared.notice ?? (qualityNotes.isEmpty ? null : qualityNotes.join(' ')),
    );

    // T032: LLM red flags surface *alongside* the fast-path ones — merged
    // by code (an enriched copy wins for the same omission so users never
    // see duplicate rows), distinct codes keep their origin.
    var finalWarnings = liveWarnings;
    if (warningRepo != null) {
      final rawWarnings = payload['missing_warnings'];
      if (rawWarnings is List && rawWarnings.isNotEmpty) {
        final merged = [...liveWarnings];
        for (final w in rawWarnings.cast<Map<String, dynamic>>()) {
          final parsed = MissingWarning(
            incidentId: recordId,
            code: WarningCode.fromContract(w['code'] as String),
            text: LocalizedText.fromMap(
                (w['text'] as Map).cast<String, Object?>()),
            origin: WarningOrigin.llm,
          );
          final existing = merged.indexWhere((e) => e.code == parsed.code);
          if (existing >= 0) {
            merged[existing] = parsed;
          } else {
            merged.add(parsed);
          }
        }
        await warningRepo.deleteForIncident(recordId);
        await warningRepo.insertAll(merged);
        finalWarnings = await warningRepo.forIncident(recordId);
      }
    }

    // A5: the LLM checklist rewrites template text in place — step ids and
    // any ticks the user set while streaming are preserved (US2/T027).
    final incomingSteps =
        (payload['action_checklist'] as List).cast<Map<String, dynamic>>();
    final mergePlan = mergeEnrichedChecklist(
      incidentId: recordId,
      existing: await steps.forIncident(recordId),
      incoming: incomingSteps.map(EnrichedStep.fromPayload).toList(),
    );
    stepRecords = await applyChecklistMerge(steps, mergePlan);

    probe.markEnriched();
    final enrichedRecord = await incidents.getById(recordId);
    return AnalyzedOutcome(
      record: enrichedRecord ?? skeleton.record,
      steps: stepRecords,
      skeletonMs: skeleton.skeletonMs,
      enrichmentMs: probe.enrichmentMs,
      enriched: true,
      notice: prepared.notice,
      warnings: finalWarnings,
    );
  }

  // -------------------------------------------------------------------------

  ({CrisisType crisisType, SeverityState severity, String? location,
      String? timeOrStatus, LocalizedText summary, LocalizedText speech})
      _fieldsFromPayload(Map<String, dynamic> payload) {
    return (
      crisisType: CrisisType.fromContract(payload['crisis_type'] as String),
      severity: SeverityState.fromContract(payload['bantay_state'] as String),
      location: payload['location'] as String?,
      timeOrStatus: payload['time_or_status'] as String?,
      summary: LocalizedText.fromMap(
          (payload['summary'] as Map).cast<String, Object?>()),
      speech: LocalizedText.fromMap(
          (payload['bantay_speech'] as Map).cast<String, Object?>()),
    );
  }

  SeverityState _raiseOnly(
      {required SeverityState skeleton, required SeverityState llm}) {
    const rank = {
      SeverityState.info: 0,
      SeverityState.caution: 1,
      SeverityState.alert: 2,
    };
    return rank[llm]! > rank[skeleton]! ? llm : skeleton;
  }

  /// Skeleton-stage trilingual texts (safe, source-grounded templates —
  /// replaced by LLM enrichment when it succeeds).
  ({LocalizedText summary, LocalizedText speech}) _skeletonTexts({
    required CrisisType crisisType,
    required SeverityState severity,
    required String? location,
  }) {
    final typeLabel = crisisType.contractName;
    final where = location == null ? '' : ' ($location)';
    final summary = LocalizedText(
      en: '$typeLabel advisory parsed$where. Full plain-language summary is '
          'being generated on-device.',
      tl: 'Na-parse ang $typeLabel na abiso$where. Ginagawa ang buod sa '
          'device.',
      ceb: 'Na-parse ang $typeLabel nga abiso$where. Gawas na ang buod sa '
          'device.',
    );
    final speech = switch (severity) {
      SeverityState.alert => const LocalizedText(
          en: 'Alert! Follow the checklist below now.',
          tl: 'Alerto! Sundin ang checklist sa ibaba ngayon na.',
          ceb: 'Alerto! Sunod sa checklist ubos karon.',
        ),
      SeverityState.caution => const LocalizedText(
          en: 'Be cautious — verify details before acting.',
          tl: 'Mag-ingat — kumpirmahin muna ang detalye.',
          ceb: 'Mag-atensiyon — kompirmahi una ang detalye.',
        ),
      SeverityState.info => const LocalizedText(
          en: 'Informational update — no immediate danger reported.',
          tl: 'Impormasyon lamang — walang agarang panganib.',
          ceb: 'Impormasyon ra — walay dayong peligro.',
        ),
    };
    return (summary: summary, speech: speech);
  }

  String _newId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // v4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
