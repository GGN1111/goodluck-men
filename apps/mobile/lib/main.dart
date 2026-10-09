import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app_graph.dart';
import 'core/theme/app_theme.dart';
import 'ui/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Last-resort guard: an unhandled error during/after bootstrap must never
  // leave the process on the blank Android launch window with no feedback.
  await runZonedGuarded(
    _bootstrap,
    (Object error, StackTrace stack) =>
        debugPrint('Unhandled startup error: $error\n$stack'),
  );
}

Future<void> _bootstrap() async {
  try {
    // Single composition root: database + repositories + offline inference
    // graph open once, before the first frame (T021).
    final graph = await AppGraph.open();
    final settings = await graph.settings.get();

    runApp(SignalReadyApp(graph: graph, lowPower: settings.lowPowerMode));
  } catch (e) {
    // Any failure before the first frame used to hard-hang on the splash.
    // Surface it with a retry path instead of dying silently.
    runApp(StartupErrorApp(message: '$e', onRetry: _bootstrap));
  }
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

/// Shown when the offline stack fails to open (e.g. an unrecoverable
/// database error). Gives the user a visible reason and a retry instead of an
/// infinite blank splash.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignalReady Pocket',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'SignalReady could not start.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => onRetry(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
