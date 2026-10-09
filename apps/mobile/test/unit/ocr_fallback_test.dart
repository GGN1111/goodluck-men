import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:signalready_pocket/core/app_graph.dart';
import 'package:signalready_pocket/data/database.dart';
import 'package:signalready_pocket/data/repositories/checklist_repository.dart';
import 'package:signalready_pocket/data/repositories/incident_repository.dart';
import 'package:signalready_pocket/data/repositories/warning_repository.dart';
import 'package:signalready_pocket/domain/analyze_advisory.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/inference/fastpath_classifier.dart';
import 'package:signalready_pocket/inference/template_checklists.dart';
import 'package:signalready_pocket/ingest/intake.dart';
import 'package:signalready_pocket/ingest/ocr_service.dart';
import 'package:signalready_pocket/ui/home_screen.dart';
import 'package:signalready_pocket/ui/image_intake.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T033 — US4 failure path (quickstart V3, FR-007/014, contract A3):
/// unreadable image → trilingual fallback notice + preserved source
/// attempt + **no fabricated record**; clear image → same brief as paste
/// with `source_type = ocr`.
void main() {
  sqfliteFfiInit();
  setUpAll(() => databaseFactory = databaseFactoryFfi);

  const noticePath = '/tmp/notice.png';
  const floodText = 'FLASH FLOOD: Lumikas na agad! Marikina River alarm 2. '
      'Tumaas ang tubig sa Zone 4. Hotline 0917-123-4567.';

  group('OcrService failure path', () {
    test('empty extraction fails with notice and preserved attempt', () async {
      final service =
          OcrService(engine: (_) async => '   \n  ');
      final result = await service.extract(noticePath);

      expect(result.success, isFalse);
      expect(result.text, isNull, reason: 'no text → nothing to analyze');
      expect(result.attempt, noticePath, reason: 'FR-014 source preserved');
      expect(result.notice, isNotNull);
      expect(result.notice!.isComplete, isTrue,
          reason: 'fallback must be trilingual (FR-009)');
      expect(result.notice!.en, contains('paste'),
          reason: 'A3 requires the type/paste offer');
    });

    test('unreadable fragment falls below the readable threshold', () async {
      final service = OcrService(engine: (_) async => 'bl r');
      final result = await service.extract(noticePath);

      expect(result.success, isFalse);
      expect(result.failureReason, 'no_readable_text');
      expect(result.attempt, noticePath);
    });

    test('engine crash degrades to failure, attempt preserved', () async {
      final service =
          OcrService(engine: (_) async => throw StateError('boom'));
      final result = await service.extract(noticePath);

      expect(result.success, isFalse);
      expect(result.attempt, noticePath);
      expect(result.failureReason, contains('ocr_error'));
      expect(result.notice!.isComplete, isTrue);
    });

    test('readable extraction succeeds with no fallback notice', () async {
      final service = OcrService(engine: (_) async => floodText);
      final result = await service.extract(noticePath);

      expect(result.success, isTrue);
      expect(result.text, floodText);
      expect(result.notice, isNull);
      expect(result.attempt, isNull);
    });
  });

  group('ImageIntakeController flow', () {
    test('cancelled pick returns to idle without a failure', () async {
      final controller =
          ImageIntakeController(pickImage: (_) async => null);
      await controller.capture(ImageSource.gallery);

      expect(controller.state.value, isA<IntakeIdle>());
      controller.dispose();
    });

    test('OCR failure surfaces the attempt for the fallback banner',
        () async {
      final controller = ImageIntakeController(
        pickImage: (_) async => noticePath,
        ocr: OcrService(engine: (_) async => ''),
      );
      await controller.capture(ImageSource.camera);

      final failed = controller.state.value;
      expect(failed, isA<IntakeFailed>());
      expect((failed as IntakeFailed).result.attempt, noticePath);
      controller.dispose();
    });

    test('successful OCR yields the extracted text for analysis', () async {
      ImageSource? requested;
      final controller = ImageIntakeController(
        pickImage: (source) async {
          requested = source;
          return noticePath;
        },
        ocr: OcrService(engine: (_) async => floodText),
      );
      await controller.capture(ImageSource.gallery);

      expect(requested, ImageSource.gallery);
      final ready = controller.state.value;
      expect(ready, isA<IntakeReady>());
      expect((ready as IntakeReady).text, floodText);
      controller.dispose();
    });
  });

  group('Home screen A3 wiring', () {
    // testWidgets runs in FakeAsync — real DB I/O must be driven through
    // tester.runAsync or it deadlocks (sqflite_ffi + path_provider).
    Future<AppGraph> openGraph(WidgetTester tester, String name) async {
      final graph = await tester.runAsync(
        () => AppGraph.open(
          dbOverridePath:
              p.join(Directory.systemTemp.path, 'ocr_fallback_$name.db'),
          enableEngine: false,
        ),
      );
      return graph!;
    }

    Future<List<IncidentRecord>> incidents(WidgetTester tester, AppGraph g) async {
      final rows = await tester
          .runAsync(() => IncidentRepository(g.store.db).getAll());
      return rows!;
    }

    testWidgets('unreadable image shows fallback and fabricates no record',
        (tester) async {
      final graph = await openGraph(tester, 'fail');
      addTearDown(graph.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            graph: graph,
            pickImage: (_) async => noticePath,
            ocr: OcrService(engine: (_) async => '  '),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan image'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      // Default AppSettings language is Tagalog (AppLanguage.tl).
      expect(find.textContaining('Hindi mabasa ang larawan'),
          findsOneWidget, reason: 'A3 fallback message visible');
      expect(find.textContaining('paste'), findsOneWidget);

      expect(await incidents(tester, graph), isEmpty,
          reason: 'failed OCR must never persist a fabricated brief');
    });
  });

  // Contract A2 happy path: real-DB analysis cannot run inside the
  // FakeAsync widget-test zone — exercise the intake → analyze join the
  // same way the Home screen wires it (Ready → analyze(sourceType: ocr)).
  test('clear image flows into analysis as source_type=ocr', () async {
    final dbPath = p.join(
        Directory.systemTemp.createTempSync('ocr_ok_').path, 'ok.db');
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

    ImageSource? requested;
    final controller = ImageIntakeController(
      pickImage: (source) async {
        requested = source;
        return noticePath;
      },
      ocr: OcrService(engine: (_) async => floodText),
    );
    addTearDown(controller.dispose);
    await controller.capture(ImageSource.camera);

    expect(requested, ImageSource.camera);
    final ready = controller.state.value;
    expect(ready, isA<IntakeReady>());

    final outcome = await analyze((ready as IntakeReady).text,
        sourceType: SourceType.ocr);
    expect(outcome, isA<AnalyzedOutcome>());
    final record = (outcome as AnalyzedOutcome).record;
    expect(record.sourceType, SourceType.ocr, reason: 'contract A2');
    expect(record.crisisType, CrisisType.flood);
    expect(record.sourceText, contains('FLASH FLOOD'),
        reason: 'OCR text flows through the same verbatim intake');

    final saved = await IncidentRepository(store.db).getAll();
    expect(saved, hasLength(1));
    expect(saved.first.sourceType, SourceType.ocr);
  });
}
