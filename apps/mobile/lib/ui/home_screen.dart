import 'package:flutter/material.dart';

import '../core/app_graph.dart';
import '../core/theme/app_theme.dart';
import '../domain/analyze_advisory.dart';
import '../domain/entities.dart';
import '../ingest/ocr_service.dart';
import '../inference/translation_copy_check.dart';
import 'action_checklist.dart';
import 'bantay_mascot.dart';
import 'image_intake.dart';
import 'language_switcher.dart';
import 'missing_warnings_card.dart';
import 'permission_notice.dart';
import 'recheck_alarm_button.dart';

/// HOME / BRIEF screen (T021, contracts/ui-actions.md):
/// paste intake → fast-path skeleton (≤2s) → streamed enrichment, with
/// severity theming that swaps instantly per analysis.
///
/// Later stories layer onto this screen: checklist toggle (T025), red flags
/// (T031), OCR source (T036), alarm control (T040), language switch (T044).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.graph,
    this.pickImage,
    this.ocr,
  });

  final AppGraph graph;

  /// Injected seams for host tests (US4); production uses the defaults.
  final ImagePickerFn? pickImage;
  final OcrService? ocr;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();

  AnalysisOutcome? _outcome;
  bool _busy = false;
  AppSettings _settings = const AppSettings();
  late final ImageIntakeController _intake;
  bool _enablingNotifications = false;

  /// Re-check reminders that expired while the device was off (launch
  /// reconciliation) — surfaced as an explicit reschedule notice so nothing
  /// is lost silently (research R8 / reboot edge case).
  int get _missedAlarms => widget.graph.reconcileReport.missed;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _syncNotificationPermission();
    _intake = ImageIntakeController(
      pickImage: widget.pickImage ?? defaultImagePicker,
      ocr: widget.ocr,
    );
    _intake.state.addListener(_onIntakeStateChanged);
  }

  @override
  void dispose() {
    _intake.state.removeListener(_onIntakeStateChanged);
    _intake.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// A2/A3 (US4): ready OCR text joins the paste path as `source_type=ocr`;
  /// a failed extraction only refreshes the fallback banner — it never
  /// starts an analysis, so no record is fabricated (FR-007).
  void _onIntakeStateChanged() {
    if (!mounted) return;
    final value = _intake.state.value;
    if (value is IntakeReady) {
      _intake.reset();
      _controller.text = value.text; // FR-014: extracted text stays visible
      _runAnalysis(value.text, sourceType: SourceType.ocr);
      return;
    }
    setState(() {});
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await widget.graph.settings.get();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Defaults already in place.
    }
  }

  /// T044 (US6, FR-009): persist the chosen language and repaint instantly —
  /// every brief surface reads `_settings.language`, so nothing else runs.
  Future<void> _onLanguageChanged(AppLanguage language) async {
    if (language == _settings.language) return;
    setState(() => _settings = _settings.copyWith(language: language));
    try {
      await widget.graph.settings.setLanguage(language);
    } catch (_) {
      // In-memory swap still applied; persistence retries next launch.
    }
  }

  /// C4: mirror the real notification state into settings on launch so the
  /// permission banner reflects the OS, not just the stored flag.
  Future<void> _syncNotificationPermission() async {
    try {
      final granted = await widget.graph.scheduler.notificationsEnabled();
      await widget.graph.settings.setNotificationsGranted(granted);
      if (mounted) {
        setState(() => _settings = _settings.copyWith(
            notificationsGranted: granted));
      }
    } catch (_) {
      // Leave the stored flag as-is.
    }
  }

  Future<void> _enableNotifications() async {
    if (_enablingNotifications) return;
    setState(() => _enablingNotifications = true);
    try {
      final granted = await widget.graph.scheduler.requestPermissions();
      await widget.graph.settings.setNotificationsGranted(granted);
      if (mounted) {
        setState(() {
          _settings = _settings.copyWith(notificationsGranted: granted);
          _enablingNotifications = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(granted
                ? 'Reminders enabled.'
                : 'Still blocked — enable notifications in system settings.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _enablingNotifications = false);
    }
  }

  Future<void> _onAlarmPermissionResult(bool granted) async {
    await widget.graph.settings.setNotificationsGranted(granted);
    if (mounted) {
      setState(() =>
          _settings = _settings.copyWith(notificationsGranted: granted));
    }
  }

  Future<void> _analyze() =>
      _runAnalysis(_controller.text, sourceType: SourceType.text);

  Future<void> _runAnalysis(
    String rawText, {
    required SourceType sourceType,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _outcome = null;
    });
    try {
      final outcome = await widget.graph.analyze(
        rawText,
        sourceType: sourceType,
        onSkeletonReady: (skeleton) {
          // First number of SC-001: skeleton visible before enrichment ends.
          if (mounted) setState(() => _outcome = skeleton);
        },
      );
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outcome = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
    }
  }

  /// B1: optimistic toggle — persist through the repository, then mirror
  /// the new state locally without re-running analysis.
  Future<void> _toggleStep(ActionStep step) async {
    final outcome = _outcome;
    final stepId = step.id;
    if (outcome is! AnalyzedOutcome || stepId == null || _busy) return;
    try {
      final nextState = await widget.graph.steps.toggle(stepId);
      if (!mounted) return;
      setState(() {
        _outcome = AnalyzedOutcome(
          record: outcome.record,
          steps: [
            for (final s in outcome.steps)
              s.id == stepId ? s.copyWith(state: nextState) : s,
          ],
          skeletonMs: outcome.skeletonMs,
          enrichmentMs: outcome.enrichmentMs,
          enriched: outcome.enriched,
          notice: outcome.notice,
          warnings: outcome.warnings,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update checklist: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    final severityName = switch (outcome) {
      AnalyzedOutcome(:final record) => record.severity.contractName,
      _ => 'INFO',
    };
    final theme = appThemeFor(severityName, lowPower: _settings.lowPowerMode);

    return Theme(
      data: theme,
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Header(modelReady: widget.graph.modelReady),
            const SizedBox(height: 8),
            // T044/T046 (US6): instant three-language switch — a pure field
            // selection over the brief already on screen (no re-analysis).
            Row(
              children: [
                const Text('Language', style: TextStyle(fontSize: 12)),
                const Spacer(),
                LanguageSwitcher(
                  language: _settings.language,
                  onChanged: _onLanguageChanged,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 6,
              minLines: 4,
              decoration: InputDecoration(
                hintText:
                    'Paste an SMS, barangay GC announcement, or OCR text…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<ImageIntakeState>(
              valueListenable: _intake.state,
              builder: (context, intakeState, _) {
                final reading = intakeState is IntakeReading;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy || reading ? null : _analyze,
                            icon: const Icon(Icons.search),
                            label: Text(
                                _busy ? 'Analyzing…' : 'Analyze offline'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ScanImageButton(
                          controller: _intake,
                          enabled: !_busy && !reading,
                        ),
                        if (_busy || reading) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                    if (intakeState is IntakeFailed) ...[
                      const SizedBox(height: 12),
                      _NoticeBanner(
                        text: intakeState.result.notice!
                            .forLang(_settings.language),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            ..._body(outcome),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(AnalysisOutcome? outcome) {
    switch (outcome) {
      case null:
        return const [
          _HintCard(
            icon: Icons.paste,
            text:
                'Everything runs on this device — no signal needed. Paste a '
                'notice to parse its crisis type, severity, and next steps.',
          ),
        ];
      case NoEmergencyOutcome():
        return const [
          _HintCard(
            icon: Icons.search_off,
            text:
                'No emergency content detected. Paste the full notice — '
                'keywords for fires, floods, outages, or security threats '
                'were not found.',
          ),
        ];
      case AnalyzedOutcome():
        return _analyzed(outcome);
    }
  }

  List<Widget> _analyzed(AnalyzedOutcome outcome) {
    final record = outcome.record;
    final lang = _settings.language;
    final statusLabel = switch (record.status) {
      AnalysisStatus.skeleton => 'SKELETON',
      AnalysisStatus.enriched => 'ENRICHED',
      AnalysisStatus.failed => 'DEGRADED',
    };

    return [
      BantayMascot(
        severity: record.severity,
        speech: record.speech,
        language: lang,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            avatar: Icon(
              Icons.bolt,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: Text('$statusLabel · brief ${outcome.skeletonMs}ms'),
          ),
          if (outcome.enrichmentMs != null)
            Chip(label: Text('enriched ${outcome.enrichmentMs}ms')),
          Chip(label: Text(record.crisisType.contractName)),
          if (record.location != null) Chip(label: Text(record.location!)),
          // T045: model copied one language into another — flag it instead of
          // silently showing an untranslated line.
          if ((record.modelNotice ?? '').contains(kCopyCheckNotice))
            Chip(
              avatar: const Icon(Icons.translate, size: 16),
              label: const Text('Verify translations'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Summary', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(record.summary.forLang(lang)),
            ],
          ),
        ),
      ),
      if (outcome.notice != null) ...[
        const SizedBox(height: 12),
        _NoticeBanner(text: outcome.notice!),
      ],
      if (outcome.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        MissingWarningsCard(warnings: outcome.warnings, language: lang),
      ],
      if (_missedAlarms > 0) ...[
        const SizedBox(height: 12),
        _NoticeBanner(
          text: '$_missedAlarms re-check reminder(s) passed while the app '
              'was closed. Set a new one below.',
        ),
      ],
      if (!_settings.notificationsGranted) ...[
        const SizedBox(height: 12),
        PermissionNotice(
          language: lang,
          enabling: _enablingNotifications,
          onEnable: _enableNotifications,
        ),
      ],
      const SizedBox(height: 12),
      RecheckAlarmButton(
        incidentId: record.id ?? 0,
        alarms: widget.graph.alarms,
        scheduler: widget.graph.scheduler,
        language: lang,
        onPermissionResult: _onAlarmPermissionResult,
      ),
      const SizedBox(height: 16),
      Text(
        'Action checklist',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      ActionChecklist(
        steps: outcome.steps,
        language: lang,
        onToggle: _toggleStep,
      ),
      const SizedBox(height: 8),
      Text(
        'Saved to History automatically.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.modelReady});

  final bool modelReady;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.shield, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'SignalReady Pocket',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Chip(
          avatar: Icon(
            modelReady ? Icons.smart_toy_outlined : Icons.bolt,
            size: 16,
          ),
          label: Text(modelReady ? 'BANTAY READY' : 'FAST-PATH ONLY',
              style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.infoBlue),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text});

  final String text;

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
          const Icon(Icons.priority_high,
              color: AppColors.warningAmber, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
