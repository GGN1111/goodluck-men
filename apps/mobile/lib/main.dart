import 'package:flutter/material.dart';

import 'core/app_graph.dart';
import 'core/theme/app_theme.dart';
import 'ui/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Single composition root: database + repositories + offline inference
  // graph open once, before the first frame (T021).
  final graph = await AppGraph.open();
  final settings = await graph.settings.get();

  runApp(SignalReadyApp(graph: graph, lowPower: settings.lowPowerMode));
}

class SignalReadyApp extends StatelessWidget {
  const SignalReadyApp({
    super.key,
    required this.graph,
    required this.lowPower,
  });

  final AppGraph graph;
  final bool lowPower;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignalReady Pocket',
      debugShowCheckedModeBanner: false,
      // App-wide default; the Brief tab swaps to severity themes locally
      // (T021). Persisted language/low-power defaults land with T050.
      theme: appThemeFor('INFO', lowPower: lowPower),
      initialRoute: AppRoutes.home,
      onGenerateRoute: (settings) => onGenerateAppRoute(graph, settings),
    );
  }
}
