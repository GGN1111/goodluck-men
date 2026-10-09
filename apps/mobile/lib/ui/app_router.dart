import 'package:flutter/material.dart';

import '../core/app_graph.dart';
import 'home_shell.dart';

/// Named routes (ui-actions.md Screens).
abstract final class AppRoutes {
  static const String home = '/';
  static const String history = '/history';
  static const String guides = '/guides';
  static const String settings = '/settings';

  /// Tab indexes inside [HomeShell].
  static const int briefTab = 0;
  static const int historyTab = 1;
  static const int guidesTab = 2;
  static const int settingsTab = 3;
}

/// Central route table. The HomeShell hosts the four primary tabs; named
/// routes simply open the shell on the requested tab (deep-link style).
/// The [AppGraph] is threaded through so tab bodies share one database
/// handle instead of reopening files per route.
Route<dynamic> onGenerateAppRoute(AppGraph graph, RouteSettings settings) {
  final initialIndex = switch (settings.name) {
    AppRoutes.history => AppRoutes.historyTab,
    AppRoutes.guides => AppRoutes.guidesTab,
    AppRoutes.settings => AppRoutes.settingsTab,
    _ => AppRoutes.briefTab,
  };

  return MaterialPageRoute<void>(
    settings: settings,
    builder: (context) => HomeShell(graph: graph, initialIndex: initialIndex),
  );
}
