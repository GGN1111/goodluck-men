import 'package:flutter/material.dart';

import '../core/app_graph.dart';
import '../core/theme/app_theme.dart';
import 'app_router.dart';
import 'guides_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Primary shell: bottom navigation across the four screens
/// (Brief, History, Guides, Settings) per ui-actions.md.
///
/// Owns the app-wide theme layer: low-power mode (FR-011 / contract C3)
/// rethemes every tab to blackout high-contrast instantly when toggled on
/// the Settings screen.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.graph,
    this.initialIndex = AppRoutes.briefTab,
  });

  final AppGraph graph;
  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;
  bool _lowPower = false;

  @override
  void initState() {
    super.initState();
    _loadLowPower();
  }

  Future<void> _loadLowPower() async {
    try {
      final settings = await widget.graph.settings.get();
      if (mounted) setState(() => _lowPower = settings.lowPowerMode);
    } catch (_) {
      // Default (off) stands.
    }
  }

  void _onSelect(int index) {
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Neutral INFO accent as the shell base; the Brief tab layers its own
      // severity theme on top. Low-power swaps in the pure-black surfaces.
      data: appThemeFor('INFO', lowPower: _lowPower),
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _index,
            children: [
              HomeScreen(graph: widget.graph),
              HistoryScreen(graph: widget.graph),
              GuidesScreen(graph: widget.graph),
              SettingsScreen(
                graph: widget.graph,
                onLowPowerChanged: (enabled) =>
                    setState(() => _lowPower = enabled),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onSelect,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              label: 'Brief',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Guides',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
