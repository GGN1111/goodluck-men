import 'package:flutter/material.dart';

import '../core/app_graph.dart';
import '../domain/entities.dart';

/// HOUSEHOLD PROFILE screen (T052 / US-polish, contract C6): one local row
/// of optional personal context. Append-only by design — profile data may
/// personalize *future* checklists but never merges into source-derived
/// brief fields (FR-005 provenance).
class HouseholdProfileScreen extends StatefulWidget {
  const HouseholdProfileScreen({super.key, required this.graph});

  final AppGraph graph;

  @override
  State<HouseholdProfileScreen> createState() => _HouseholdProfileScreenState();
}

class _HouseholdProfileScreenState extends State<HouseholdProfileScreen> {
  final _meetingController = TextEditingController();
  final _evacController = TextEditingController();
  final _notesController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _meetingController.dispose();
    _evacController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.graph.profile.get();
      if (!mounted) return;
      _meetingController.text = profile?.meetingPoint ?? '';
      _evacController.text = profile?.evacDestination ?? '';
      _notesController.text = profile?.notes ?? '';
    } catch (_) {
      // Start blank — the row is optional.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    String? blankToNull(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    try {
      await widget.graph.profile.save(HouseholdProfile(
        meetingPoint: blankToNull(_meetingController.text),
        evacDestination: blankToNull(_evacController.text),
        notes: blankToNull(_notesController.text),
        updatedAt: DateTime.now(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Household profile saved on this device.')),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the profile.')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Household profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Optional context stored only on this device. It may be appended '
            'to future action checklists — it never changes what an advisory '
            'itself says (provenance rule).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _meetingController,
            decoration: const InputDecoration(
              labelText: 'Meeting point',
              hintText: 'e.g. Barangay hall covered court',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _evacController,
            decoration: const InputDecoration(
              labelText: 'Evacuation destination',
              hintText: 'e.g. School gymnasium on the hill',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'e.g. Elderly parent on the second floor; pets.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save profile'),
          ),
        ],
      ),
    );
  }
}
