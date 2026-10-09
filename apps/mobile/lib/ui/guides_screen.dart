import 'package:flutter/material.dart';

import '../core/app_graph.dart';
import '../domain/entities.dart';

/// GUIDES screen (T051 / US7): bundled EmergencyProtocolGuides from the
/// seeded cache, browsable by crisis type, fully offline (FR-012 — never
/// network-fetched).
class GuidesScreen extends StatefulWidget {
  const GuidesScreen({super.key, required this.graph});

  final AppGraph graph;

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  AppSettings _settings = const AppSettings();
  List<EmergencyProtocolGuide> _guides = const [];
  CrisisType? _filter;
  bool _loading = true;

  /// Crisis categories that actually ship guides, derived from the seed.
  List<CrisisType> get _categories {
    final seen = <CrisisType>{};
    for (final g in _guides) {
      seen.add(g.crisisType);
    }
    return CrisisType.values.where(seen.contains).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.graph.settings.get();
      final guides = await widget.graph.guides.all();
      if (mounted) {
        setState(() {
          _settings = settings;
          _guides = guides;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _categoryLabel(CrisisType type) => type.contractName;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_guides.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Guides are bundled at install — none found in the local cache.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final lang = _settings.language;
    final visible = _filter == null
        ? _guides
        : _guides.where((g) => g.crisisType == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Offline reference — bundled at install, no signal needed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('ALL'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
              ),
              for (final type in _categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_categoryLabel(type)),
                    selected: _filter == type,
                    onSelected: (_) => setState(() => _filter = type),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final guide = visible[index];
              return ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(guide.title.forLang(lang)),
                subtitle: Text(guide.crisisType.contractName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GuideDetailScreen(
                        guide: guide,
                        language: lang,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One guide, rendered in the user's selected language — content already
/// lives in the local SQLite cache (read-only, FR-012).
class GuideDetailScreen extends StatelessWidget {
  const GuideDetailScreen({
    super.key,
    required this.guide,
    required this.language,
  });

  final EmergencyProtocolGuide guide;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(guide.title.forLang(language))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Chip(label: Text(guide.crisisType.contractName)),
          const SizedBox(height: 12),
          Text(
            guide.body.forLang(language),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
