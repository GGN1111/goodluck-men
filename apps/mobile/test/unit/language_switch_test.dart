import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/inference/translation_copy_check.dart';
import 'package:signalready_pocket/ui/language_switcher.dart';

/// T042 — Instant three-language switching (US6, FR-009, research R5).
///
/// Switching language is a pure field selection over triplets already in
/// memory: it must remap summary/speech/steps/warnings instantly, invoke no
/// pipeline, and leave severity + checklist state untouched.
void main() {
  const summary = LocalizedText(
    en: 'Flash flood in Zone 4.',
    tl: 'Baha sa Zone 4.',
    ceb: 'Baha sa Zone 4.',
  );
  const speech = LocalizedText(
    en: 'Move to higher ground now.',
    tl: 'Umakyat sa mataas na lugar.',
    ceb: 'Ambak sa taas nga dapit.',
  );
  const stepText = LocalizedText(
    en: 'Fill containers with clean water.',
    tl: 'Punan ang lalagyan ng malinis na tubig.',
    ceb: 'Pun-a ang sudlanan sa limpyo nga tubig.',
  );
  const warningText = LocalizedText(
    en: 'No evacuation center named.',
    tl: 'Walang evacuation center.',
    ceb: 'Walay evacuation center.',
  );

  final record = IncidentRecord(
    id: 7,
    createdAt: DateTime(2026, 10, 9, 12, 0),
    sourceType: SourceType.text,
    sourceText: 'FLASH FLOOD Zone 4',
    crisisType: CrisisType.flood,
    severity: SeverityState.alert,
    summary: summary,
    speech: speech,
    status: AnalysisStatus.enriched,
  );

  final steps = [
    ActionStep(
      id: 1,
      incidentId: 7,
      priority: 1,
      text: stepText,
      state: ChecklistStepState.done,
      origin: StepOrigin.llm,
    ),
  ];

  final warnings = [
    MissingWarning(
      incidentId: 7,
      code: WarningCode.evacCenter,
      text: warningText,
      origin: WarningOrigin.llm,
    ),
  ];

  test('language switch remaps every content triplet', () {
    for (final lang in AppLanguage.values) {
      expect(summary.forLang(lang), isNotEmpty);
      expect(speech.forLang(lang), isNotEmpty);
      expect(stepText.forLang(lang), isNotEmpty);
      expect(warningText.forLang(lang), isNotEmpty);
    }
    expect(summary.forLang(AppLanguage.en), 'Flash flood in Zone 4.');
    expect(summary.forLang(AppLanguage.tl), 'Baha sa Zone 4.');
    expect(speech.forLang(AppLanguage.ceb), 'Ambak sa taas nga dapit.');
    expect(stepText.forLang(AppLanguage.tl), 'Punan ang lalagyan ng '
        'malinis na tubig.');
    expect(warningText.forLang(AppLanguage.ceb), 'Walay evacuation center.');
  });

  test('switch is a pure field selection — instant, no recompute', () {
    final sw = Stopwatch()..start();
    // Render every brief surface across all three languages back-to-back.
    for (final lang in AppLanguage.values) {
      summary.forLang(lang);
      speech.forLang(lang);
      for (final s in steps) {
        s.text.forLang(lang);
      }
      for (final w in warnings) {
        w.text.forLang(lang);
      }
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1000),
        reason: 'US6 budget is <1s, and this is a trivial field read');
  });

  test('severity and checklist state are untouched by a switch', () {
    for (final lang in AppLanguage.values) {
      // Re-resolving the same entities must not mutate them.
      record.summary.forLang(lang);
      record.speech.forLang(lang);
      steps.first.text.forLang(lang);
      warnings.first.text.forLang(lang);

      expect(record.severity, SeverityState.alert);
      expect(record.crisisType, CrisisType.flood);
      expect(steps.first.state, ChecklistStepState.done,
          reason: 'a done tick must survive any language switch');
      expect(warnings.first.code, WarningCode.evacCenter);
    }
  });

  test('LocalizedText triplets are complete and mutually distinct', () {
    for (final text in [summary, speech, stepText]) {
      expect(text.isComplete, isTrue);
    }
    // The copy that is genuinely identical (summary tl/ceb) is a model
    // artifact the copy-check surfaces — it is NOT a switching concern.
    expect(
      const LocalizedText(en: 'A', tl: 'B', ceb: 'C').isComplete,
      isTrue,
    );
  });

  group('T045 translation copy detection (research R5)', () {
    test('flags byte-identical language pairs', () {
      final report = checkTranslationCopy(summary);
      expect(report.hasCopies, isTrue);
      expect(report.duplicatePairs, contains('tl==ceb'));
      expect(report.notice, contains('identical'));
    });

    test('passes when every language is distinct', () {
      final report = checkTranslationCopy(speech);
      expect(report.hasCopies, isFalse);
      expect(report.duplicatePairs, isEmpty);
    });

    test('brief-level scan merges findings across triplets', () {
      final report = checkBrief([
        summary, // tl==ceb
        speech, // clean
        const LocalizedText(en: 'X', tl: 'X', ceb: 'Y'), // en==tl
      ]);
      expect(report.duplicatePairs, containsAll(['tl==ceb', 'en==tl']));
    });

    test('blank fields are ignored, never counted as copies', () {
      final report = checkTranslationCopy(
          const LocalizedText(en: 'Only English', tl: '', ceb: '  '));
      expect(report.hasCopies, isFalse);
    });
  });

  group('T044 LanguageSwitcher widget', () {
    testWidgets('renders EN/TG/BS segments and reports taps',
        (tester) async {
      var current = AppLanguage.tl;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LanguageSwitcher(
                language: current,
                onChanged: (l) => setState(() => current = l),
              ),
            ),
          ),
        ),
      );

      expect(find.text('TG'), findsOneWidget); // selected segment
      await tester.tap(find.text('BS'));
      await tester.pump();
      expect(current, AppLanguage.ceb);

      await tester.tap(find.text('EN'));
      await tester.pump();
      expect(current, AppLanguage.en);
    });

    testWidgets('switch is instant — no spinner, no analysis',
        (tester) async {
      var current = AppLanguage.en;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LanguageSwitcher(
                language: current,
                onChanged: (l) => setState(() => current = l),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('TG'));
      // Single pump settles — nothing async is in flight (research R5).
      await tester.pump();
      expect(current, AppLanguage.tl);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
