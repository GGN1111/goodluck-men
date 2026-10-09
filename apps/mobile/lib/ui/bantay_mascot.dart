import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/entities.dart';

/// Bantay mascot card (contracts/ui-actions.md A1): severity-accented
/// container with the state icon and the trilingual speech line for the
/// current language. Pure vector fallback until the Lottie asset lands
/// (assets/bantay/) — never fetched from the network.
class BantayMascot extends StatelessWidget {
  const BantayMascot({
    super.key,
    required this.severity,
    required this.speech,
    required this.language,
  });

  final SeverityState severity;
  final LocalizedText speech;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final token = bantayTokenFor(severity.contractName);
    final accent = token.accent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(severity), color: accent, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StateBadge(token: token),
                    const Spacer(),
                    Text(
                      'Bantay',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: accent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  speech.forLang(language),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(SeverityState state) {
    switch (state) {
      case SeverityState.alert:
        return Icons.warning_amber_rounded;
      case SeverityState.caution:
        return Icons.error_outline;
      case SeverityState.info:
        return Icons.info_outline;
    }
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.token});

  final BantayStateToken token;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: token.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        token.label,
        style: const TextStyle(
          color: AppColors.textOnDark,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
