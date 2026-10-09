import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalready_pocket/domain/analysis_validator.dart';

/// T013 — Contract test: validator mirrors
/// contracts/bantay-analysis.schema.json. Accepts the golden enriched
/// payload; rejects every structural violation the schema forbids.
void main() {
  const validator = AnalysisValidator();

  /// Golden payload (spec §5 example, extended to v1.0 contract:
  /// trilingual triplets, step/warning objects, envelope fields).
  Map<String, dynamic> goldenPayload() => {
        'schema_version': '1.0',
        'analysis_id': '6f9619ff-8b86-4d01-b42d-00cf4fc964ff',
        'source': {'type': 'text', 'text': 'Marikina River Alarm 2 advisory'},
        'crisis_type': 'FLOOD',
        'bantay_state': 'ALERT',
        'status': 'enriched',
        'location': 'Zone 4, Barangay Tumana',
        'time_or_status': 'As of 4:30 PM',
        'summary': {
          'en': 'Marikina River reached Alarm 2.',
          'tl': 'Umabot sa Alarm 2 ang Marikina River.',
          'ceb': 'Abot sa Alarm 2 ang Marikina River.',
        },
        'bantay_speech': {
          'en': 'Evacuate now!',
          'tl': 'Lumikas agad!',
          'ceb': 'Dali paglikas!',
        },
        'action_checklist': [
          {
            'id': 's1',
            'priority': 1,
            'text': {
              'en': 'Turn off the main breaker.',
              'tl': 'Patayin ang main breaker.',
              'ceb': 'Patara ang main breaker.',
            },
            'origin': 'llm',
            'state': 'pending',
          },
          {
            'id': 's2',
            'priority': 2,
            'text': {
              'en': 'Grab your go-bag.',
              'tl': 'Kunin ang go-bag.',
              'ceb': 'Kuha ang go-bag.',
            },
            'origin': 'llm',
            'state': 'done',
          },
        ],
        'missing_warnings': [
          {
            'id': 'w1',
            'code': 'EVAC_CENTER',
            'text': {
              'en': 'No evacuation center provided.',
              'tl': 'Walang evacuation center.',
              'ceb': 'Walang evacuation center.',
            },
            'origin': 'llm',
          },
        ],
        'model_notice': null,
      };

  Map<String, dynamic> mutate(void Function(Map<String, dynamic>) fn) {
    final payload = goldenPayload();
    fn(payload);
    return payload;
  }

  group('golden payload', () {
    test('validates with zero errors', () {
      final result = validator.validate(goldenPayload());
      expect(result.errors, isEmpty,
          reason: 'golden payload must pass: ${result.errors}');
      expect(result.isValid, isTrue);
    });

    test('survives JSON round-trip (decoder output shape)', () {
      final decoded =
          jsonDecode(jsonEncode(goldenPayload())) as Map<String, dynamic>;
      final result = validator.validate(decoded);
      expect(result.errors, isEmpty, reason: '${result.errors}');
    });

    test('core fields map to domain enums', () {
      final core = validator.toCoreFields(goldenPayload());
      expect(core, isNotNull);
      expect(core!.crisisType.contractName, 'FLOOD');
      expect(core.severity.contractName, 'ALERT');
    });
  });

  group('structural rejections', () {
    test('wrong schema_version', () {
      final r = validator.validate(mutate((p) => p['schema_version'] = '2.0'));
      expect(r.isValid, isFalse);
      expect(r.errors.join(), contains('schema_version'));
    });

    test('unknown crisis_type', () {
      final r = validator.validate(mutate((p) => p['crisis_type'] = 'ZOMBIE'));
      expect(r.errors.join(), contains('crisis_type'));
    });

    test('unknown bantay_state', () {
      final r = validator.validate(mutate((p) => p['bantay_state'] = 'MEH'));
      expect(r.errors.join(), contains('bantay_state'));
    });

    test('missing Cebuano summary (FR-009)', () {
      final r = validator.validate(mutate((p) {
        (p['summary'] as Map<String, dynamic>)['ceb'] = '';
      }));
      expect(r.errors.join(), contains('summary.ceb'));
    });

    test('empty checklist rejected', () {
      final r = validator.validate(mutate((p) => p['action_checklist'] = <dynamic>[]));
      expect(r.errors.join(), contains('action_checklist'));
    });

    test('more than 5 checklist items rejected', () {
      final r = validator.validate(mutate((p) {
        final steps = List<Map<String, dynamic>>.from(
            (p['action_checklist'] as List).cast());
        while (steps.length <= AnalysisValidator.maxChecklistItems) {
          steps.add({
            'id': 's${steps.length + 1}',
            'priority': steps.length + 1,
            'text': {'en': 'a', 'tl': 'b', 'ceb': 'c'},
            'origin': 'llm',
            'state': 'pending',
          });
        }
        p['action_checklist'] = steps;
      }));
      expect(r.errors.join(), contains('at most 5'));
    });

    test('duplicate priorities rejected', () {
      final r = validator.validate(mutate((p) {
        final steps = (p['action_checklist'] as List).cast<Map<String, dynamic>>();
        steps[1]['priority'] = steps[0]['priority'];
      }));
      expect(r.errors.join(), contains('unique'));
    });

    test('bad warning code rejected', () {
      final r = validator.validate(mutate((p) {
        (p['missing_warnings'] as List).first['code'] = 'MAYBE';
      }));
      expect(r.errors.join(), contains('EVAC_CENTER'));
    });

    test('empty source text rejected', () {
      final r = validator.validate(mutate((p) {
        (p['source'] as Map<String, dynamic>)['text'] = '';
      }));
      expect(r.errors.join(), contains('source.text'));
    });

    test('oversized source text rejected (contract maxLength)', () {
      final r = validator.validate(mutate((p) {
        (p['source'] as Map<String, dynamic>)['text'] =
            'x' * (AnalysisValidator.maxSourceChars + 1);
      }));
      expect(r.errors.join(), contains('20000'));
    });

    test('missing bantay_speech object rejected', () {
      final r = validator.validate(mutate((p) => p['bantay_speech'] = null));
      expect(r.errors.join(), contains('bantay_speech'));
    });
  });

  group('provenance leniency (FR-005 friendly)', () {
    test('null location/time pass with no errors', () {
      final r = validator.validate(mutate((p) {
        p['location'] = null;
        p['time_or_status'] = null;
      }));
      expect(r.errors, isEmpty, reason: '${r.errors}');
    });

    test('empty location warns but does not fail', () {
      final r = validator.validate(mutate((p) => p['location'] = '  '));
      expect(r.isValid, isTrue);
      expect(r.warnings.join(), contains('location'));
    });
  });
}
