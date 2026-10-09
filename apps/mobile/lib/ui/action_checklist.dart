import 'package:flutter/material.dart';

import '../domain/entities.dart';

/// T025 — Toggleable action checklist (contracts/ui-actions.md B1):
/// rows in priority order, trilingual via [language], done-state visually
/// distinct (struck-through + filled check) with immediate optimistic
/// feedback; persistence is the caller's `onToggle` → repository `toggle`.
class ActionChecklist extends StatelessWidget {
  const ActionChecklist({
    super.key,
    required this.steps,
    required this.language,
    this.onToggle,
  });

  final List<ActionStep> steps;
  final AppLanguage language;
  final ValueChanged<ActionStep>? onToggle;

  @override
  Widget build(BuildContext context) {
    final sorted = [...steps]..sort((a, b) => a.priority.compareTo(b.priority));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final step in sorted) _StepRow(step: step, language: language, onToggle: onToggle)],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.language,
    required this.onToggle,
  });

  final ActionStep step;
  final AppLanguage language;
  final ValueChanged<ActionStep>? onToggle;

  @override
  Widget build(BuildContext context) {
    final done = step.state == ChecklistStepState.done;
    final accent = Theme.of(context).colorScheme.primary;
    final onTap = onToggle == null ? null : () => onToggle!(step);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: done
            ? accent.withValues(alpha: 0.10)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Semantics(
            button: true,
            checked: done,
            label: step.text.forLang(language),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  done
                      ? Icon(Icons.check_circle, color: accent, size: 26)
                      : Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 2),
                          ),
                          child: Text(
                            '${step.priority}',
                            style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step.text.forLang(language),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            decorationColor:
                                done ? accent.withValues(alpha: 0.7) : null,
                            color: done
                                ? Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color
                                    ?.withValues(alpha: 0.55)
                                : null,
                            height: 1.3,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
