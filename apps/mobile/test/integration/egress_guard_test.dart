import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/core/app_graph.dart';
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/checklist_repository.dart';
import 'package:signalready_pocket/data/repositories/guide_repository.dart';
import 'package:signalready_pocket/data/repositories/incident_repository.dart';
import 'package:signalready_pocket/data/repositories/settings_repository.dart';
import 'package:signalready_pocket/data/repositories/warning_repository.dart';
import 'package:signalready_pocket/domain/analyze_advisory.dart';
import 'package:signalready_pocket/domain/delete_incident.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/inference/fastpath_classifier.dart';
import 'package:signalready_pocket/inference/template_checklists.dart';
import 'package:signalready_pocket/ingest/intake.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T054 — Automated egress guard (SC-007 / G1 / quickstart V7).
///
/// `IOOverrides.socketConnect` intercepts every `Socket.connect` — the
/// strongest host-side hook available. The full offline workflow (open
/// graph → analyze → guides → settings → checklist toggle → delete) must
/// complete with zero socket opens.
final class _NoEgressIOOverrides extends IOOverrides {
  int attempts = 0;

  Never _block(dynamic host, int port) {
    attempts++;
    throw StateError(
        'NETWORK EGRESS ATTEMPTED (SC-007): $host:$port — this app must be '
        '100% offline');
  }

  @override
  Future<Socket> socketConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) =>
      _block(host, port);

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) =>
      _block(host, port);
}

void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  test('full workflow completes with zero socket opens (SC-007)', () async {
    final guard = _NoEgressIOOverrides();
    final previous = IOOverrides.current;
    IOOverrides.global = guard;
    addTearDown(() => IOOverrides.global = previous);

    final dbPath = p.join(
        Directory.systemTemp.createTempSync('egress_').path, 'egress.db');
    final graph = await AppGraph.open(dbOverridePath: dbPath, enableEngine: false);
    addTearDown(graph.dispose);

    // 1. Analyze a flood advisory (paste path).
    final outcome = await graph.analyze(
      'FLASH FLOOD: Marikina River critical level. Evacuate Zone 4 now.',
    );
    expect(outcome, isA<AnalyzedOutcome>());
    final record = (outcome as AnalyzedOutcome).record;
    expect(record.crisisType, CrisisType.flood);

    // 2. Read guides (bundled seed — offline reference).
    expect(await graph.guides.count(), greaterThan(0));
    await graph.guides.byCrisis(CrisisType.flood);

    // 3. Settings round-trip.
    await graph.settings.setLanguage(AppLanguage.en);
    await graph.settings.setLowPowerMode(true);
    expect((await graph.settings.get()).lowPowerMode, isTrue);

    // 4. Checklist toggle (persistence).
    final steps = await graph.steps.forIncident(record.id!);
    expect(steps, isNotEmpty);
    await graph.steps.toggle(steps.first.id!);

    // 5. History + permanent delete.
    expect(await graph.incidents.getAll(), hasLength(1));
    await DeleteIncident(
      incidents: graph.incidents,
      alarms: graph.alarms,
    ).call(record.id!);
    expect(await graph.incidents.getAll(), isEmpty);

    // 6. Raw DB still reachable without sockets.
    final store = await SignalReadyDatabase.open(overridePath: dbPath);
    addTearDown(store.close);
    expect(await IncidentRepository(store.db).getAll(), isEmpty);
    expect(await ChecklistRepository(store.db).forIncident(record.id!),
        isEmpty);
    expect(await GuideRepository(store.db).count(), greaterThan(0));
    expect(await SettingsRepository(store.db).get(), isNotNull);

    expect(guard.attempts, 0,
        reason: 'SC-007 — zero bytes across the entire workflow');
  });

  test('AnalyzeAdvisory alone never touches Socket.connect', () async {
    final guard = _NoEgressIOOverrides();
    final previous = IOOverrides.current;
    IOOverrides.global = guard;
    addTearDown(() => IOOverrides.global = previous);

    final dbPath = p.join(
        Directory.systemTemp.createTempSync('egress2_').path, 'e2.db');
    final store = await SignalReadyDatabase.open(overridePath: dbPath);
    addTearDown(store.close);

    final analyze = AnalyzeAdvisory(
      intake: IntakeService(),
      classifier: const FastPathClassifier(),
      templates: const TemplateChecklists(),
      incidents: IncidentRepository(store.db),
      steps: ChecklistRepository(store.db),
      warnings: WarningRepository(store.db),
      pipeline: null,
    );
    final outcome = await analyze('FIRE: leave the building now.');
    expect(outcome, isA<AnalyzedOutcome>());
    expect(guard.attempts, 0);
  });
}
