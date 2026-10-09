import 'dart:convert';

import 'package:signalready_pocket/inference/inference_types.dart';

/// Deterministic [InferenceEngine] for tests (T023) — no FFI, no sockets.
///
/// Feed it a payload builder (or an explicit event script) and it replays
/// completed generations for every request, letting the full pipeline
/// (decode → normalize → validate → repair) run against golden output.
class FakeInferenceEngine implements InferenceEngine {
  FakeInferenceEngine({this.payloadBuilder});

  /// Called per request; the returned map is JSON-encoded and emitted as a
  /// single [CompletedEvent].
  final Map<String, dynamic> Function(InferenceRequest request)?
      payloadBuilder;

  /// When non-null, every stream instead emits this failure (engine-down
  /// scenario, FR-014 degraded path).
  FailedEvent? failure;

  /// Raw text emitted verbatim when [payloadBuilder] is null.
  String? rawText;

  /// Per-request scripts for repair-path tests: first call plays script[0],
  /// second call script[1], ... (beyond that it falls back to the builder).
  final List<List<InferenceEvent>> scripts = [];

  final List<InferenceRequest> requests = [];

  @override
  Stream<InferenceEvent> generateStream(InferenceRequest request) async* {
    requests.add(request);
    final failureEvent = failure;
    if (failureEvent != null) {
      yield failureEvent;
      return;
    }
    final scriptIndex = requests.length - 1;
    if (scriptIndex < scripts.length) {
      yield* Stream.fromIterable(scripts[scriptIndex]);
      return;
    }
    final raw = rawText ??
        (payloadBuilder == null
            ? null
            : jsonEncode(payloadBuilder!(request)));
    if (raw == null) {
      yield const FailedEvent('lib_missing', 'Fake has no output configured.');
      return;
    }
    yield TokenEvent(raw.substring(0, raw.length ~/ 2));
    yield CompletedEvent(raw);
  }
}

/// Golden valid payload (contract bantay-analysis.schema.json) for the
/// flood fixture used by the US1 smoke test.
Map<String, dynamic> floodPayload(InferenceRequest request) => {
      'schema_version': '1.0',
      'analysis_id': request.analysisId,
      'source': {'type': 'text', 'text': request.userText},
      'crisis_type': 'FLOOD',
      'bantay_state': 'ALERT',
      'status': 'enriched',
      'location': 'Marikina River',
      'time_or_status': 'now',
      'model_notice': null,
      'summary': {
        'en': 'Flash flood alert for Marikina: move to high ground now.',
        'tl': 'Flash flood alert sa Marikina: umakyat sa mataas na lugar.',
        'ceb': 'Flash flood alert sa Marikina: Sakay sa taas nga lugar.',
      },
      'bantay_speech': {
        'en': 'Alert! Follow the checklist below now.',
        'tl': 'Alerto! Sundin ang checklist sa ibaba ngayon na.',
        'ceb': 'Alerto! Sunod sa checklist ubos karon.',
      },
      'action_checklist': [
        {
          'id': 'a1',
          'priority': 1,
          'origin': 'llm',
          'state': 'pending',
          'text': {
            'en': 'Switch off the main breaker before water reaches outlets.',
            'tl': 'Patayin ang main breaker bago umabot ang tubig sa outlet.',
            'ceb': 'Patara ang main breaker una moabot ang tubig sa outlet.',
          },
        },
        {
          'id': 'a2',
          'priority': 2,
          'origin': 'llm',
          'state': 'pending',
          'text': {
            'en': 'Bring the go-bag and climb to the barangay hall roof.',
            'tl': 'Dalhin ang go-bag at umakyat sa bubong ng barangay hall.',
            'ceb': 'Dala ang go-bag ug saha sa atubang sa barangay hall.',
          },
        },
      ],
      'missing_warnings': [
        {
          'code': 'HOTLINE',
          'origin': 'llm',
          'text': {
            'en': 'No rescue hotline was included in the notice.',
            'tl': 'Walang hotline ng tulong sa anunsyo.',
            'ceb': 'Walay hotline sa tabang sa pahibalo.',
          },
        },
      ],
    };
