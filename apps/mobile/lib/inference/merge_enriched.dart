import 'dart:math';

import '../data/repositories/checklist_repository.dart';
import '../domain/entities.dart';

/// T027 — Enrichment checklist merge (contracts/ui-actions.md A5):
/// the LLM's refined step texts replace skeleton template text **in place**,
/// while SQLite step ids and the user's `pending⇄done` ticks are preserved.
/// Never fabricates steps: incoming items come from a validated payload
/// (≤5, trilingual, unique priorities — AnalysisValidator).
class EnrichedStep {
  const EnrichedStep({
    required this.priority,
    required this.origin,
    required this.text,
  });

  /// Parses one validated `action_checklist[i]` payload object.
  factory EnrichedStep.fromPayload(Map<String, dynamic> item) => EnrichedStep(
        priority: item['priority'] as int,
        origin: StepOrigin.fromName(item['origin'] as String),
        text: LocalizedText.fromMap(
            (item['text'] as Map).cast<String, Object?>()),
      );

  final int priority;
  final StepOrigin origin;
  final LocalizedText text;
}

/// In-place replacement of an existing step's content (id + state untouched).
class StepReplacement {
  const StepReplacement({
    required this.stepId,
    required this.priority,
    required this.text,
    required this.origin,
  });

  final int stepId;
  final int priority;
  final LocalizedText text;
  final StepOrigin origin;
}

/// Resulting plan: rewrite matched steps, insert surplus incoming steps,
/// remove surplus existing steps. All lists are capped at
/// [ChecklistRepository.maxSteps] in total.
class ChecklistMergePlan {
  const ChecklistMergePlan({
    required this.incidentId,
    required this.replacements,
    required this.inserts,
    required this.removeIds,
  });

  final int incidentId;
  final List<StepReplacement> replacements;
  final List<ActionStep> inserts;
  final List<int> removeIds;

  int get finalStepCount => replacements.length + inserts.length;
}

/// Pairs existing and incoming steps by priority order (index pairing):
/// - both have step i → replace text/priority/origin, keep id + user state
/// - incoming longer → surplus becomes fresh `pending` inserts
/// - existing longer → surplus removed (LLM returned fewer steps)
ChecklistMergePlan mergeEnrichedChecklist({
  required int incidentId,
  required List<ActionStep> existing,
  required List<EnrichedStep> incoming,
}) {
  final cap = ChecklistRepository.maxSteps;
  final sortedExisting = [...existing]
    ..sort((a, b) => a.priority.compareTo(b.priority));
  final sortedIncoming = [...incoming]
    ..sort((a, b) => a.priority.compareTo(b.priority));

  // Defensive cap: the validator already rejects >5, but the merge must
  // never be the component that breaks the data-model invariant.
  final incomingCapped = sortedIncoming.length > cap
      ? sortedIncoming.sublist(0, cap)
      : sortedIncoming;

  final pairCount = min(sortedExisting.length, incomingCapped.length);

  return ChecklistMergePlan(
    incidentId: incidentId,
    replacements: [
      for (var i = 0; i < pairCount; i++)
        StepReplacement(
          stepId: sortedExisting[i].id!,
          priority: incomingCapped[i].priority,
          text: incomingCapped[i].text,
          origin: incomingCapped[i].origin,
        ),
    ],
    inserts: [
      for (var i = pairCount; i < incomingCapped.length; i++)
        ActionStep(
          incidentId: incidentId,
          priority: incomingCapped[i].priority,
          text: incomingCapped[i].text,
          state: ChecklistStepState.pending,
          origin: incomingCapped[i].origin,
        ),
    ],
    removeIds: [
      for (var i = pairCount; i < sortedExisting.length; i++)
        sortedExisting[i].id!,
    ],
  );
}

/// Applies a plan through the repository in the only order that keeps the
/// 5-step cap true at every moment: rewrite → prune → insert, then reloads
/// the authoritative rows (ids/states/texts) for the UI.
Future<List<ActionStep>> applyChecklistMerge(
  ChecklistRepository repo,
  ChecklistMergePlan plan,
) async {
  for (final r in plan.replacements) {
    await repo.updateContent(
      r.stepId,
      priority: r.priority,
      text: r.text,
      origin: r.origin,
    );
  }
  // Surviving rows are exactly the replaced ones; inserts do not exist yet,
  // so pruning first can never delete a fresh step.
  await repo.deleteExcept(
      plan.incidentId, plan.replacements.map((r) => r.stepId).toList());
  if (plan.inserts.isNotEmpty) {
    await repo.insertAll(plan.inserts);
  }
  return repo.forIncident(plan.incidentId);
}
