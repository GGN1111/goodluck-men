import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/ui/missing_warnings_card.dart';

/// T031 — MissingWarnings card: amber red flags, trilingual, hidden when
/// there is nothing to warn about (FR-004/005, quickstart V2).
void main() {
  MissingWarning warn(WarningCode code, LocalizedText text) => MissingWarning(
        incidentId: 1,
        code: code,
        text: text,
        origin: WarningOrigin.fastpath,
      );

  Future<void> pump(WidgetTester tester, List<MissingWarning> warnings,
      {AppLanguage language = AppLanguage.en}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child:
              MissingWarningsCard(warnings: warnings, language: language),
        ),
      ),
    ));
  }

  testWidgets('renders warning rows in the selected language',
      (tester) async {
    await pump(
      tester,
      [
        warn(
          WarningCode.evacCenter,
          const LocalizedText(
            en: 'No evacuation center is named in the notice.',
            tl: 'Walang tinukoy na evacuation center sa anunsyo.',
            ceb: 'Walay gisulti nga evacuation center sa pahibalo.',
          ),
        ),
        warn(
          WarningCode.hotline,
          const LocalizedText(
            en: 'No official hotline appears in the notice.',
            tl: 'Walang opisyal na hotline sa anunsyo.',
            ceb: 'Walay opisyal nga hotline sa pahibalo.',
          ),
        ),
      ],
    );

    expect(find.textContaining('No evacuation center'), findsOneWidget);
    expect(find.textContaining('No official hotline'), findsOneWidget);

    await pump(
      tester,
      [
        warn(
          WarningCode.evacCenter,
          const LocalizedText(
            en: 'No evacuation center is named in the notice.',
            tl: 'Walang tinukoy na evacuation center sa anunsyo.',
            ceb: 'Walay gisulti nga evacuation center sa pahibalo.',
          ),
        ),
      ],
      language: AppLanguage.tl,
    );
    expect(find.textContaining('Walang tinukoy na evacuation center'),
        findsOneWidget);
  });

  testWidgets('empty warning list renders nothing', (tester) async {
    await pump(tester, const []);
    expect(find.byType(MissingWarningsCard), findsOneWidget);
    expect(find.textContaining('Missing details'), findsNothing);
  });
}
