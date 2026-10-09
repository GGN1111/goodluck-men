import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/inference/fastpath_classifier.dart';

/// T014 — Corpus test: the deterministic fast path classifies every golden
/// advisory to the expected crisis_type + bantay_state (quickstart V1/V2
/// foundation). Missing-detail warnings are asserted separately in T028.
void main() {
  final classifier = FastPathClassifier();

  final corpus = jsonDecode(File('test/corpus/corpus.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = (corpus['cases'] as List).cast<Map<String, dynamic>>();

  test('corpus has at least 20 cases covering all five crisis types', () {
    expect(cases.length, greaterThanOrEqualTo(20));
    final types = cases
        .map((c) => ((c['expected'] as Map)['crisis_type']) as String?)
        .whereType<String>()
        .toSet();
    expect(types,
        containsAll(['FLOOD', 'FIRE', 'SECURITY', 'BLACKOUT', 'GENERAL']));
  });

  for (final c in cases) {
    final id = c['id'] as String;
    final text = c['text'] as String;
    final expected = c['expected'] as Map<String, dynamic>;

    test('classify $id', () {
      final result = classifier.classify(text);

      if (expected['no_emergency'] == true) {
        expect(result, isNull,
            reason: '$id must yield no emergency (never a fabricated crisis)');
        return;
      }

      expect(result, isNotNull, reason: '$id must be classified');
      expect(result!.crisisType.contractName, expected['crisis_type'],
          reason: '$id crisis_type');
      expect(result.severity.contractName, expected['bantay_state'],
          reason: '$id bantay_state');

      // Provenance hooks (SC-002): extracted fields must be substrings of
      // the source text — never invented.
      final locationPart = expected['location_contains'] as String?;
      if (locationPart != null) {
        expect(result.location, isNotNull, reason: '$id location extracted');
        expect(text, contains(result.location),
            reason: '$id location must appear verbatim in source');
        expect(locationPart, contains(result.location!));
      }
    });
  }
}
