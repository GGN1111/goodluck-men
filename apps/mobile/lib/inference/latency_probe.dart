/// T022 — Latency instrumentation for the SC-001 two-number method
/// (research R4): skeleton display time AND enrichment completion time are
/// recorded separately — never conflated (quickstart V1, validation-results).
class LatencyProbe {
  LatencyProbe() : _sw = Stopwatch()..start();

  final Stopwatch _sw;
  int? _skeletonMs;
  int? _enrichedMs;

  /// Call when the skeleton brief is rendered/persisted (FR-013 budget: ≤2s).
  int markSkeleton() => _skeletonMs = _sw.elapsedMilliseconds;

  /// Call when validated enrichment has been applied (p95 target ≤15s).
  int markEnriched() => _enrichedMs = _sw.elapsedMilliseconds;

  int? get skeletonMs => _skeletonMs;
  int? get enrichmentMs => _enrichedMs;

  int get totalMs => _sw.elapsedMilliseconds;

  void stop() => _sw.stop();
}
