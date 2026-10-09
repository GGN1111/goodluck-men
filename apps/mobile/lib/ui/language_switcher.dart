import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../domain/entities.dart';

/// T044 — Instant three-language switcher (US6, FR-009, contract layout).
///
/// A pure control over [Settings.language]: tapping a segment reports the
/// new value and the host persists it. No re-analysis, no loading state —
/// the swap is a field selection (research R5).
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({
    super.key,
    required this.language,
    required this.onChanged,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AppLanguage>(
      segments: [
        for (final l in AppLanguage.values)
          ButtonSegment<AppLanguage>(
            value: l,
            label: Text(languageLabel(l)),
            tooltip: languageName(l),
          ),
      ],
      selected: {language},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
