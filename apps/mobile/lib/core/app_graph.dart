import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/repositories/alarm_repository.dart';
import '../data/repositories/checklist_repository.dart';
import '../data/repositories/guide_repository.dart';
import '../data/repositories/incident_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/warning_repository.dart';
import '../domain/analyze_advisory.dart';
import '../inference/enrichment_pipeline.dart';
import '../inference/fastpath_classifier.dart';
import '../inference/llama_engine.dart';
import '../inference/template_checklists.dart';
import '../ingest/intake.dart';
import '../notifications/alarm_reconciler.dart';
import '../notifications/alarm_scheduler.dart';

/// Composition root (T021) — opens the local database once, builds the
/// repository set, best-effort loads the llama.cpp engine, wires the
/// US1 analysis pipeline, and on launch reconciles re-check alarms from
/// the DB (research R8 / T039). UI receives this graph instead of reaching
/// for globals (spec: zero network, single-writer SQLite).
class AppGraph {
  AppGraph._({
    required this.store,
    required this.settings,
    required this.profile,
    required this.incidents,
    required this.steps,
    required this.warnings,
    required this.alarms,
    required this.guides,
    required this.analyze,
    required this.scheduler,
    required this.reconcileReport,
    required this.modelReady,
  });

  final SignalReadyDatabase store;
  final SettingsRepository settings;
  final ProfileRepository profile;
  final IncidentRepository incidents;
  final ChecklistRepository steps;
  final WarningRepository warnings;
  final AlarmRepository alarms;
  final GuideRepository guides;
  final AnalyzeAdvisory analyze;

  /// Exact-alarm scheduling (US5 / FR-008).
  final AlarmScheduler scheduler;

  /// Result of the launch reconciliation pass — lets the UI surface a
  /// "reschedule" notice when alarms were missed while the device was off.
  final ReconcileReport reconcileReport;

  /// True when a native engine + model are available; false on dev hosts or
  /// before the GGUF ships — analysis then degrades to the fast-path
  /// skeleton (FR-014 / research R11).
  final bool modelReady;

  /// Primary model asset name (research R2 primary pick). The file is only
  /// present once the (large) GGUF is bundled — absent → skeleton-only.
  static const String primaryModelAsset = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';

  static Future<AppGraph> open({
    String? dbOverridePath,
    bool enableEngine = true,
  }) async {
    final store = await SignalReadyDatabase.open(overridePath: dbOverridePath);
    final db = store.db;

    final settings = SettingsRepository(db);
    final profile = ProfileRepository(db);
    final incidents = IncidentRepository(db);
    final steps = ChecklistRepository(db);
    final warnings = WarningRepository(db);
    final alarms = AlarmRepository(db);
    final guides = GuideRepository(db);

    final engine = enableEngine ? await _loadEngine() : null;
    final modelReady = engine != null;
    try {
      await settings.setModelVariant(modelReady ? 'primary' : 'missing');
    } catch (_) {
      // Settings persistence is non-critical for startup.
    }

    final pipeline =
        engine != null ? EnrichmentPipeline(engine: engine) : null;

    final analyze = AnalyzeAdvisory(
      intake: IntakeService(),
      classifier: const FastPathClassifier(),
      templates: const TemplateChecklists(),
      incidents: incidents,
      steps: steps,
      warnings: warnings,
      pipeline: pipeline,
    );

    // US5 / T039: reconcile re-check alarms from the DB at every launch.
    // Best-effort — a failure here must never block the app from opening.
    final scheduler = AlarmScheduler();
    var reconcileReport = const ReconcileReport();
    try {
      await scheduler.init();
      reconcileReport = await AlarmReconciler(
        alarms: alarms,
        schedule: scheduler.schedule,
        cancelPlatform: scheduler.cancel,
      ).reconcile();
    } catch (_) {
      // Exact-alarm/permission unavailable on this host — degrade to
      // in-app prompts (contract C4 / research R8).
    }

    return AppGraph._(
      store: store,
      settings: settings,
      profile: profile,
      incidents: incidents,
      steps: steps,
      warnings: warnings,
      alarms: alarms,
      guides: guides,
      analyze: analyze,
      scheduler: scheduler,
      reconcileReport: reconcileReport,
      modelReady: modelReady,
    );
  }

  /// Best-effort native engine load: missing GGUF (research R11) or a host
  /// without llama.cpp resolves to null → skeleton-only analysis.
  static Future<LlamaCppEngine?> _loadEngine() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = await LlamaCppEngine.ensureModelAsset(
        assetName: primaryModelAsset,
        destinationDir: p.join(dir.path, 'models'),
      );
      if (modelPath == null) return null;
      return LlamaCppEngine.tryCreate(modelPath: modelPath);
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() => store.close();
}
