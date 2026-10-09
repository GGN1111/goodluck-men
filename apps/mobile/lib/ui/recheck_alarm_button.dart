import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/repositories/alarm_repository.dart';
import '../domain/entities.dart';
import '../notifications/alarm_scheduler.dart';

/// T040 — Re-check alarm controls on the Brief (contract B2/B3):
/// 15m / 1h / custom chips, confirmation with the exact fire time, and
/// cancel. Offline by construction — scheduling never touches the network
/// (FR-008, SC-006).
class RecheckAlarmButton extends StatefulWidget {
  const RecheckAlarmButton({
    super.key,
    required this.incidentId,
    required this.alarms,
    required this.scheduler,
    required this.language,
    this.onPermissionResult,
  });

  final int incidentId;
  final AlarmRepository alarms;
  final AlarmScheduler scheduler;
  final AppLanguage language;

  /// Reports the post-schedule permission state so the host can refresh
  /// the settings-backed banner (C4).
  final Future<void> Function(bool granted)? onPermissionResult;

  @override
  State<RecheckAlarmButton> createState() => _RecheckAlarmButtonState();
}

class _RecheckAlarmButtonState extends State<RecheckAlarmButton> {
  ReCheckAlarm? _active;
  bool _busy = false;

  static String _messageFor(AppLanguage language) => switch (language) {
        AppLanguage.en => 'Time to re-check the emergency advisory.',
        AppLanguage.tl => 'Oras na para suriin muli ang abiso sa emergency.',
        AppLanguage.ceb => 'Panahon na aron susihon pag-usab ang abiso.',
      };

  static String _timeLabel(DateTime fireAt, AppLanguage language) {
    final h = fireAt.hour % 12 == 0 ? 12 : fireAt.hour % 12;
    final mm = fireAt.minute.toString().padLeft(2, '0');
    final ampm = fireAt.hour < 12 ? 'AM' : 'PM';
    return '$h:$mm $ampm';
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await widget.alarms.forIncident(widget.incidentId);
    if (!mounted) return;
    setState(() {
      ReCheckAlarm? active;
      for (final a in rows) {
        if (a.status == AlarmStatus.scheduled) {
          active = a;
          break;
        }
      }
      _active = active;
    });
  }

  Future<void> _schedule(Duration offset) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final granted = await widget.scheduler.requestPermissions();
      await widget.onPermissionResult?.call(granted);

      final fireAt =
          AlarmScheduler.fireAtFromNow(offset, now: DateTime.now());
      final toInsert = ReCheckAlarm(
        incidentId: widget.incidentId,
        fireAt: fireAt,
        message: _messageFor(widget.language),
        status: AlarmStatus.scheduled,
      );
      final id = await widget.alarms.insert(toInsert);
      final persisted = toInsert.copyWith(id: id);
      final handle = await widget.scheduler.schedule(persisted);
      await widget.alarms
          .updateStatus(id, status: AlarmStatus.scheduled, platformHandle: handle);

      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted
              ? 'Re-check set for ${_timeLabel(fireAt, widget.language)}.'
              : 'Reminder saved, but notifications are off — enable them '
                  'to hear the alarm.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not set reminder: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final active = _active;
    if (active == null || _busy) return;
    setState(() => _busy = true);
    try {
      final handle = active.platformHandle;
      if (handle != null) await widget.scheduler.cancel(handle);
      await widget.alarms.updateStatus(active.id!,
          status: AlarmStatus.cancelled, clearPlatformHandle: true);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Re-check reminder cancelled.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel reminder: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _custom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final fireAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final offset = fireAt.difference(now);
    if (offset <= Duration.zero) return;
    await _schedule(offset);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (active != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.alarm_on, color: AppColors.warningAmber),
          title: Text(
              'Re-check ${_timeLabel(active.fireAt, widget.language)}'),
          subtitle: const Text('Tap to cancel'),
          trailing: IconButton(
            icon: const Icon(Icons.cancel_outlined),
            onPressed: _busy ? null : _cancel,
            tooltip: 'Cancel re-check',
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.alarm, size: 18),
          label: const Text('Re-check in 15 min'),
          onPressed: _busy ? null : () => _schedule(const Duration(minutes: 15)),
        ),
        ActionChip(
          avatar: const Icon(Icons.alarm, size: 18),
          label: const Text('Re-check in 1 hour'),
          onPressed: _busy ? null : () => _schedule(const Duration(hours: 1)),
        ),
        ActionChip(
          avatar: const Icon(Icons.edit_calendar, size: 18),
          label: const Text('Custom…'),
          onPressed: _busy ? null : _custom,
        ),
      ],
    );
  }
}
