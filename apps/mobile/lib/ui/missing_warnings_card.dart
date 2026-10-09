import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/entities.dart';

/// T031 — US3 red-flag card (FR-004, A1): renders the missing-information
/// warnings collected by the fast path and/or LLM. Amber regardless of
/// severity (deliberate bump — quickstart V2), empty list renders nothing.
class MissingWarningsCard extends StatelessWidget {
  const MissingWarningsCard({
    super.key,
    required this.warnings,
    required this.language,
  });

  final List<MissingWarning> warnings;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.warningAmber),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warningAmber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Missing details — verify before acting',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                container: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.error_outline,
                          size: 16, color: AppColors.warningAmber),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(w.text.forLang(language))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
