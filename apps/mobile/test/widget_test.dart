import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/ui/bantay_mascot.dart';

void main() {
  testWidgets('Bantay mascot renders severity badge and active language',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BantayMascot(
            severity: SeverityState.alert,
            speech: const LocalizedText(
              en: 'English speech',
              tl: 'Tagalog speech',
              ceb: 'Cebuano speech',
            ),
            language: AppLanguage.tl,
          ),
        ),
      ),
    );

    expect(find.text('ALERT'), findsOneWidget);
    expect(find.text('Bantay'), findsOneWidget);
    expect(find.text('Tagalog speech'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
