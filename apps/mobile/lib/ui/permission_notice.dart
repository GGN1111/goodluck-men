import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/entities.dart';

/// T041 — Notifications-denied degradation (contract C4, FR-008 edge
/// case): a banner explains reminders won't ring, with a one-tap grant
/// and the in-app re-check prompt noted as the fallback.
class PermissionNotice extends StatelessWidget {
  const PermissionNotice({
    super.key,
    required this.language,
    required this.onEnable,
    this.enabling = false,
  });

  final AppLanguage language;
  final Future<void> Function() onEnable;
  final bool enabling;

  String get _title => switch (language) {
        AppLanguage.en => 'Reminders are blocked',
        AppLanguage.tl => 'Nakablock ang mga paalala',
        AppLanguage.ceb => 'Gi-block ang mga pahinumdom',
      };

  String get _body => switch (language) {
        AppLanguage.en =>
          'Notifications are off, so re-check alarms won\u2019t ring. '
              'You\u2019ll still see in-app re-check prompts on the brief.',
        AppLanguage.tl =>
          'Nakapatay ang notifications kaya hindi magri-ring ang mga '
              're-check alarm. Makikita mo pa rin ang re-check sa brief.',
        AppLanguage.ceb =>
          'Patay ang notifications mao nga dili molingaw ang re-check '
              'alarms. Makita gihapon nimo ang re-check sa brief.',
      };

  String get _button => switch (language) {
        AppLanguage.en => 'Enable reminders',
        AppLanguage.tl => 'Payagan ang mga paalala',
        AppLanguage.ceb => 'Pag-enable sa mga pahinumdom',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.warningAmber),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_off_outlined,
              color: AppColors.warningAmber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(_body),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: enabling ? null : onEnable,
                  icon: const Icon(Icons.notifications_active_outlined,
                      size: 18),
                  label: Text(_button),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
