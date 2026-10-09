import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/core/theme/app_theme.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/ui/bantay_mascot.dart';

/// T053 — Golden coverage for the three Bantay severity states/themes
/// (spec §3 state machine, ui-actions A1). Each severity pins the mascot
/// card AND its theme accents so a regression in accent mapping or layout
/// fails visibly.
///
/// Regenerate baselines with: flutter test --update-goldens test/golden/
void main() {
  const speech = LocalizedText(
    en: 'Move to higher ground now.',
    tl: 'Umakyat sa mataas na lugar.',
    ceb: 'Ambak sa taas nga dapit.',
  );

  Widget host(SeverityState severity, String bantayState) {
    return MaterialApp(
      theme: appThemeFor(bantayState, lowPower: false),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: BantayMascot(
            severity: severity,
            speech: speech,
            language: AppLanguage.en,
          ),
        ),
      ),
    );
  }

  testWidgets('ALERT state (crimson)', (tester) async {
    await tester.pumpWidget(host(SeverityState.alert, 'ALERT'));
    await tester.pumpAndSettle();
    expect(find.text('ALERT'), findsOneWidget);
    expect(find.text('Move to higher ground now.'), findsOneWidget);
    await expectLater(
      find.byType(BantayMascot),
      matchesGoldenFile('goldens/bantay_alert.png'),
    );
  });

  testWidgets('CAUTION state (amber)', (tester) async {
    await tester.pumpWidget(host(SeverityState.caution, 'CAUTION'));
    await tester.pumpAndSettle();
    expect(find.text('CAUTION'), findsOneWidget);
    await expectLater(
      find.byType(BantayMascot),
      matchesGoldenFile('goldens/bantay_caution.png'),
    );
  });

  testWidgets('INFO state (blue)', (tester) async {
    await tester.pumpWidget(host(SeverityState.info, 'INFO'));
    await tester.pumpAndSettle();
    expect(find.text('INFO'), findsOneWidget);
    await expectLater(
      find.byType(BantayMascot),
      matchesGoldenFile('goldens/bantay_info.png'),
    );
  });

  testWidgets('low-power theme keeps mascot readable on pure black',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: appThemeFor('ALERT', lowPower: true),
      home: Scaffold(
        body: BantayMascot(
          severity: SeverityState.alert,
          speech: speech,
          language: AppLanguage.tl,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(BantayMascot),
      matchesGoldenFile('goldens/bantay_alert_low_power.png'),
    );
  });
}
