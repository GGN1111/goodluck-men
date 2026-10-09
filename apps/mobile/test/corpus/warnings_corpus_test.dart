import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/domain/entities.dart';
import 'package:signalready_pocket/inference/fastpath_classifier.dart';
import 'package:signalready_pocket/inference/warning_rules.dart';

/// T028 — Corpus test (quickstart V2, FR-004/005, SC-002):
/// - complete fixtures (`required_warning_codes: []`) must yield **exactly
///   zero** warnings — no fabrication,
/// - incomplete fixtures must contain every required code,
/// - every emitted warning carries a complete EN/TL/CEB triplet (FR-009).
void main() {
  const classifier = FastPathClassifier();
  const rules = WarningRules();

  final corpus = jsonDecode(File('test/corpus/corpus.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = (corpus['cases'] as List).cast<Map<String, dynamic>>();

  var emergencyCases = 0;
  var completeCases = 0;

  for (final c in cases) {
    final id = c['id'] as String;
    final text = c['text'] as String;
    final expected = c['expected'] as Map<String, dynamic>;
    final required =
        ((expected['required_warning_codes'] as List?) ?? const [])
            .cast<String>();

    test('warnings $id', () {
      final classified = classifier.classify(text);

      if (expected['no_emergency'] == true) {
        expect(classified, isNull,
            reason: '$id: no-emergency input must not spawn warnings');
        return;
      }
      expect(classified, isNotNull);

      if (required.isEmpty) completeCases++;
      emergencyCases++;

      final warnings = rules.detect(
        crisisType: classified!.crisisType,
        severity: classified.severity,
        sourceText: text,
        incidentId: 0,
      );
      final codes = warnings.map((w) => w.code.contractName).toSet();

      if (required.isEmpty) {
        expect(codes, isEmpty,
            reason: '$id is a complete fixture — zero warnings expected '
                '(FR-005 no fabrication); got $codes');
      } else {
        expect(codes, containsAll(required),
            reason: '$id must warn about every omitted critical detail '
                '(FR-004); required=$required got=$codes');
      }

      for (final w in warnings) {
        expect(w.text.isComplete, isTrue,
            reason: '$id/${w.code.contractName} warning must be trilingual');
        expect(w.origin, WarningOrigin.fastpath);
      }
    });
  }

  test('corpus covers complete and incomplete warning fixtures', () {
    expect(emergencyCases, greaterThanOrEqualTo(15));
    expect(completeCases, greaterThanOrEqualTo(4),
        reason: 'complete fixtures must prove the zero-warning path');
  });
}
