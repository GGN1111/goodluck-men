import 'package:flutter/material.dart';

/// Design tokens per spec §6 (UI/UX Design System).
///
/// - Primary Slate `#1A202C`: high-contrast base, low-power dark mode
/// - Alert Crimson `#C53030`: active life-safety threats (ALERT)
/// - Warning Amber `#D69E2E`: missing-info red flags & rumors (CAUTION)
/// - Info Blue `#3182CE`: utility updates (INFO)
abstract final class AppColors {
  static const Color primarySlate = Color(0xFF1A202C);
  static const Color alertCrimson = Color(0xFFC53030);
  static const Color warningAmber = Color(0xFFD69E2E);
  static const Color infoBlue = Color(0xFF3182CE);

  static const Color surfaceDark = Color(0xFF2D3748);
  static const Color textOnDark = Color(0xFFF7FAFC);
  static const Color pureBlack = Color(0xFF000000); // OLED battery saving (FR-011)
}

/// Bantay threat states (spec §3 state machine).
enum BantayStateToken { alert, caution, info }

/// Maps a `bantay_state` value (from the analysis contract) to a theme token.
BantayStateToken bantayTokenFor(String bantayState) {
  switch (bantayState.toUpperCase()) {
    case 'ALERT':
      return BantayStateToken.alert;
    case 'CAUTION':
      return BantayStateToken.caution;
    case 'INFO':
      return BantayStateToken.info;
    default:
      return BantayStateToken.info;
  }
}

extension BantayStateTokenX on BantayStateToken {
  Color get accent {
    switch (this) {
      case BantayStateToken.alert:
        return AppColors.alertCrimson;
      case BantayStateToken.caution:
        return AppColors.warningAmber;
      case BantayStateToken.info:
        return AppColors.infoBlue;
    }
  }

  String get label {
    switch (this) {
      case BantayStateToken.alert:
        return 'ALERT';
      case BantayStateToken.caution:
        return 'CAUTION';
      case BantayStateToken.info:
        return 'INFO';
    }
  }
}

/// Builds the app theme for a severity state.
///
/// [bantayState] is the contract value (`ALERT | CAUTION | INFO`).
/// [lowPower] enables the blackout-friendly high-contrast variant (FR-011):
/// OLED pure-black surfaces, maximally opaque text, thicker separators.
ThemeData appThemeFor(String bantayState, {required bool lowPower}) {
  final token = bantayTokenFor(bantayState);
  final accent = token.accent;

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      primary: accent,
      surface: lowPower ? AppColors.pureBlack : AppColors.primarySlate,
      onSurface: AppColors.textOnDark,
    ),
    scaffoldBackgroundColor:
        lowPower ? AppColors.pureBlack : AppColors.primarySlate,
    appBarTheme: AppBarTheme(
      backgroundColor: lowPower ? AppColors.pureBlack : AppColors.primarySlate,
      foregroundColor: AppColors.textOnDark,
      elevation: 0,
    ),
    cardColor: lowPower ? AppColors.pureBlack : AppColors.surfaceDark,
    dividerTheme: DividerThemeData(
      color: AppColors.textOnDark.withValues(alpha: lowPower ? 0.6 : 0.2),
      thickness: lowPower ? 1.5 : 1.0,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppColors.textOnDark),
      bodyMedium: TextStyle(color: AppColors.textOnDark),
      titleMedium: TextStyle(
        color: AppColors.textOnDark,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  return base.copyWith(
    extensions: [
      SignalReadyTokens(
        severity: token,
        accent: accent,
        lowPower: lowPower,
      ),
    ],
  );
}

/// App-specific theme extension carrying severity + low-power state to
/// widgets (Bantay mascot card, warning cards) without prop drilling.
class SignalReadyTokens extends ThemeExtension<SignalReadyTokens> {
  const SignalReadyTokens({
    required this.severity,
    required this.accent,
    required this.lowPower,
  });

  final BantayStateToken severity;
  final Color accent;
  final bool lowPower;

  @override
  SignalReadyTokens copyWith({
    BantayStateToken? severity,
    Color? accent,
    bool? lowPower,
  }) {
    return SignalReadyTokens(
      severity: severity ?? this.severity,
      accent: accent ?? this.accent,
      lowPower: lowPower ?? this.lowPower,
    );
  }

  @override
  SignalReadyTokens lerp(SignalReadyTokens? other, double t) {
    if (other == null) return this;
    return SignalReadyTokens(
      severity: t < 0.5 ? severity : other.severity,
      accent: Color.lerp(accent, other.accent, t)!,
      lowPower: t < 0.5 ? lowPower : other.lowPower,
    );
  }
}
