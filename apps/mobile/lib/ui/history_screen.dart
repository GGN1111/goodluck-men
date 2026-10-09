import 'package:flutter/material.dart';

import '../core/app_graph.dart';
import '../core/theme/app_theme.dart';
import '../domain/delete_incident.dart';
import '../domain/entities.dart';
import 'action_checklist.dart';
import 'missing_warnings_card.dart';

/// HISTORY screen (T048 / US7, contract C1): past IncidentRecords offline,
/// newest first; open a record for the full brief + checklist state; delete
/// permanently via T049 (FR-015).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.graph});

  final AppGraph graph;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  AppSettings _settings = const AppSettings();
  List<IncidentRecord> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.graph.settings.get();
      final records = await widget.graph.incidents.getAll();
      if (mounted) {
        setState(() {
          _settings = settings;
          _records = records;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _severityIcon(SeverityState severity) => switch (severity) {
        SeverityState.alert => Icons.warning,
        SeverityState.caution => Icons.error_outline,
        SeverityState.info => Icons.info_outline,
      };

  Color _severityColor(SeverityState severity) => switch (severity) {
        SeverityState.alert => AppColors.alertCrimson,
        SeverityState.caution => AppColors.warningAmber,
        SeverityState.info => AppColors.infoBlue,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No past incidents yet. Analyze a notice and it will be saved '
            'here automatically.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final lang = _settings.language;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = _records[index];
        final created = record.createdAt.toLocal().toString();
        return ListTile(
          leading: Icon(
            _severityIcon(record.severity),
            color: _severityColor(record.severity),
          ),
          title: Text(
            record.summary.forLang(lang).isNotEmpty
                ? record.summary.forLang(lang)
                : record.sourceText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${record.crisisType.contractName} · '
            '${created.substring(0, created.length > 16 ? 16 : created.length)}'
            '${record.status == AnalysisStatus.enriched ? ' · ENRICHED' : ''}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => HistoryDetailScreen(
                  graph: widget.graph,
                  record: record,
                ),
              ),
            );
            await _load();
          },
        );
      },
    );
  }
}

/// Full brief for one archived incident: summary, speech, red flags, and the
/// persisted checklist (toggleable — state is shared with the brief screen
/// through the same action_steps rows). Permanent delete lives here (C2).
class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({
    super.key,
    required this.graph,
    required this.record,
  });

  final AppGraph graph;
  final IncidentRecord record;

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  AppSettings _settings = const AppSettings();
  List<ActionStep> _steps = const [];
  List<MissingWarning> _warnings = const [];
  bool _deleting = false;

  IncidentRecord get _record => widget.record;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.graph.settings.get();
    final steps = await widget.graph.steps.forIncident(_record.id!);
    final warnings = await widget.graph.warnings.forIncident(_record.id!);
    if (mounted) {
      setState(() {
        _settings = settings;
        _steps = steps;
        _warnings = warnings;
      });
    }
  }

  Future<void> _toggleStep(ActionStep step) async {
    final stepId = step.id;
    if (stepId == null) return;
    final next = await widget.graph.steps.toggle(stepId);
    if (!mounted) return;
    setState(() {
      _steps = [
        for (final s in _steps)
          if (s.id == stepId)
            s.copyWith(state: next)
          else
            s,
      ];
    });
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this incident?'),
        content: const Text(
            'Its brief, checklist, warnings, and reminders are removed '
            'permanently. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.alertCrimson,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || _deleting) return;
    setState(() => _deleting = true);
    await DeleteIncident(
      incidents: widget.graph.incidents,
      alarms: widget.graph.alarms,
      cancelPlatform: widget.graph.scheduler.cancel,
    ).call(_record.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lang = _settings.language;
    final record = _record;
    final statusLabel = switch (record.status) {
      AnalysisStatus.skeleton => 'SKELETON',
      AnalysisStatus.enriched => 'ENRICHED',
      AnalysisStatus.failed => 'DEGRADED',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(record.crisisType.contractName),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete permanently',
            onPressed: _deleting ? null : _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(statusLabel)),
              if (record.location != null) Chip(label: Text(record.location!)),
              if (record.timeOrStatus != null)
                Chip(label: Text(record.timeOrStatus!)),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Summary',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(record.summary.forLang(lang)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bantay says',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(record.speech.forLang(lang)),
                ],
              ),
            ),
          ),
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            MissingWarningsCard(warnings: _warnings, language: lang),
          ],
          const SizedBox(height: 16),
          Text('Action checklist',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_steps.isEmpty)
            const Text('No checklist was saved for this incident.')
          else
            ActionChecklist(
              steps: _steps,
              language: lang,
              onToggle: _toggleStep,
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _deleting ? null : _confirmDelete,
            icon: const Icon(Icons.delete_outline, color: AppColors.alertCrimson),
            label: const Text('Delete',
                style: TextStyle(color: AppColors.alertCrimson)),
          ),
          if (_deleting) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
