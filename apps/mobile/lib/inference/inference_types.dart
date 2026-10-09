/// Inference contract shared by the engine (T017), pipeline (T019), and
/// test fakes — mirrors contracts/local-inference.md.
library;

import 'dart:convert';

class SamplingConfig {
  const SamplingConfig({
    this.temperature = 0.3,
    this.topP = 0.9,
    this.seed,
    this.maxTokens = 768,
  });

  final double temperature;
  final double topP;
  final int? seed;
  final int maxTokens;
}

enum InferenceStage { enrich, repair }

class InferenceRequest {
  const InferenceRequest({
    required this.analysisId,
    required this.systemPrompt,
    required this.userText,
    this.grammarId = 'bantay-json-v1',
    this.sampling = const SamplingConfig(),
    this.stage = InferenceStage.enrich,
    this.repairErrors = const [],
  });

  final String analysisId;
  final String systemPrompt;
  final String userText;
  final String grammarId;
  final SamplingConfig sampling;
  final InferenceStage stage;

  /// Populated on [InferenceStage.repair]: validation errors to correct.
  final List<String> repairErrors;
}

/// Stream events (contracts/local-inference.md "Events" table).
sealed class InferenceEvent {
  const InferenceEvent();
}

final class TokenEvent extends InferenceEvent {
  const TokenEvent(this.text);
  final String text;
}

final class ProgressEvent extends InferenceEvent {
  const ProgressEvent({required this.tokensGenerated, required this.elapsedMs});
  final int tokensGenerated;
  final int elapsedMs;
}

final class CompletedEvent extends InferenceEvent {
  const CompletedEvent(this.raw);
  final String raw;
}

final class FailedEvent extends InferenceEvent {
  const FailedEvent(this.code, this.message);

  /// `oom | model_missing | timeout | grammar_violation | cancelled | lib_missing`
  final String code;
  final String message;
}

/// In-process inference interface — opens zero sockets (SC-007).
abstract class InferenceEngine {
  Stream<InferenceEvent> generateStream(InferenceRequest request);
}

/// Decodes a completed raw payload, tolerating common small-model slips
/// (markdown fences, leading prose) that GBNF may still let through when the
/// grammar is disabled on fallback paths. Returns null when unparseable.
Map<String, dynamic>? decodeAnalysisPayload(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    text = text.trim();
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start == -1 || end <= start) return null;
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
