import 'package:flutter/material.dart';

import '../core/app_graph.dart';
import '../domain/entities.dart';
import 'household_profile_screen.dart';
import 'language_switcher.dart';

/// SETTINGS screen (T050 / US7, contract C3): language default, low-power
/// high-contrast mode (FR-011), notification + model status. Every toggle
/// persists to the single settings row so the flag survives restart and is
/// honoured app-wide.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.graph,
    this.onLowPowerChanged,
  });

  final AppGraph graph;

  /// Notified after a low-power toggle so the shell can retheme instantly
  /// (contract C3: "all screens render high-contrast dark theme").
  final ValueChanged<bool>? onLowPowerChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings _settings = const AppSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.graph.settings.get();
      if (mounted) setState(() { _settings = settings; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setLanguage(AppLanguage language) async {
    setState(() => _settings = _settings.copyWith(language: language));
    try {
      await widget.graph.settings.setLanguage(language);
    } catch (_) {
      // In-memory selection stands; persistence retries next visit.
    }
  }

  Future<void> _setLowPower(bool enabled) async {
    setState(() => _settings = _settings.copyWith(lowPowerMode: enabled));
    widget.onLowPowerChanged?.call(enabled);
    try {
      await widget.graph.settings.setLowPowerMode(enabled);
    } catch (_) {
      // Theme already swapped in-memory; flag re-persists next visit.
    }
  }

  String _modelLabel() => switch (_settings.modelVariant) {
        'primary' => 'Primary model ready (offline LLM)',
        'fallback' => 'Fallback model (offline LLM)',
        _ => 'Fast-path only — model not bundled yet',
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Language', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Brief content is always generated in all three languages; this '
          'chooses which one the app shows.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: LanguageSwitcher(
            language: _settings.language,
            onChanged: _setLanguage,
          ),
        ),
        const SizedBox(height: 24),
        Text('Display', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Low-power mode'),
          subtitle: const Text(
              'Blackout-friendly high-contrast theme: pure-black surfaces, '
              'maximum text contrast (FR-011).'),
          value: _settings.lowPowerMode,
          onChanged: _setLowPower,
        ),
        const Divider(),
        Text('Personalization', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.home_outlined),
          title: const Text('Household profile'),
          subtitle:
              const Text('Meeting point, evacuation destination, notes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HouseholdProfileScreen(graph: widget.graph),
              ),
            );
          },
        ),
        const Divider(),
        Text('Status', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _settings.notificationsGranted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
          ),
          title: const Text('Re-check reminders'),
          subtitle: Text(_settings.notificationsGranted
              ? 'Enabled'
              : 'Blocked — allow notifications in system settings'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.smart_toy_outlined),
          title: const Text('Offline analysis'),
          subtitle: Text(_modelLabel()),
        ),
      ],
    );
  }
}
