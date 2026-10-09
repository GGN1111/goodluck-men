import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/inference/fastpath_classifier.dart';

/// T029 — Provenance corpus test (FR-005 / SC-002):
/// every `location` / `time_or_status` the fast path extracts must appear
/// **verbatim** (exact substring) in `source_text` — extraction may only
/// copy, never invent. Also re-checks the corpus `location_contains`
/// expectations across the whole set.
void main() {
  const classifier = FastPathClassifier();

  final corpus = jsonDecode(File('test/corpus/corpus.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = (corpus['cases'] as List).cast<Map<String, dynamic>>();

  var extracted = 0;

  for (final c in cases) {
    final id = c['id'] as String;
    final text = c['text'] as String;
    final expected = c['expected'] as Map<String, dynamic>;

    test('provenance $id', () {
      final result = classifier.classify(text);
      if (expected['no_emergency'] == true) {
        expect(result, isNull);
        return;
      }
      expect(result, isNotNull);

      final location = result!.location;
      final time = result.timeOrStatus;

      if (location != null) {
        extracted++;
        expect(text.contains(location), isTrue,
            reason: '$id location "$location" must be a verbatim substring '
                'of source_text (FR-005/SC-002) — extraction cannot invent');
        final locationPart = expected['location_contains'] as String?;
        if (locationPart != null) {
          expect(locationPart.contains(location), isTrue,
              reason: '$id corpus expects "$locationPart" to cover "$location"');
        }
      }

      if (time != null) {
        extracted++;
        expect(text.contains(time), isTrue,
            reason: '$id time "$time" must be a verbatim substring '
                'of source_text (FR-005/SC-002)');
      }

      final locationPart = expected['location_contains'] as String?;
      if (locationPart != null) {
        expect(location, isNotNull,
            reason: '$id expects a location but none was extracted');
      }
    });
  }

  test('provenance path exercised by the corpus', () {
    expect(extracted, greaterThanOrEqualTo(4),
        reason: 'at least four cases must exercise verbatim extraction');
  });
}
