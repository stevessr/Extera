// SPDX-FileCopyrightText: 2026 Extera contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/localized_exception_extension.dart';
import 'package:extera_next/utils/msc/msc4140_delayed_events.dart';
import 'package:extera_next/widgets/matrix.dart';

/// Opens the schedule picker; on selection schedules the current
/// composer text via MSC4140.
Future<void> showScheduleMessageSheet(
  BuildContext context,
  ChatController controller,
) async {
  final l10n = L10n.of(context);
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final tomorrowMorning = DateTime(
    tomorrow.year,
    tomorrow.month,
    tomorrow.day,
    8,
  );
  final choice = await showAdaptiveBottomSheet<Duration?>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.scheduleMessage,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(l10n.scheduleIn15Minutes),
            onTap: () => Navigator.of(context).pop(const Duration(minutes: 15)),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(l10n.scheduleIn1Hour),
            onTap: () => Navigator.of(context).pop(const Duration(hours: 1)),
          ),
          ListTile(
            leading: const Icon(Icons.update_outlined),
            title: Text(l10n.scheduleIn8Hours),
            onTap: () => Navigator.of(context).pop(const Duration(hours: 8)),
          ),
          ListTile(
            leading: const Icon(Icons.wb_twilight_outlined),
            title: Text(l10n.scheduleTomorrow),
            subtitle: Text(
              MaterialLocalizations.of(context).formatFullDate(tomorrowMorning),
            ),
            onTap: () => Navigator.of(
              context,
            ).pop(tomorrowMorning.difference(DateTime.now())),
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: Text(l10n.scheduleCustomTime),
            onTap: () => _pickCustomTime(context).then(
              (delay) =>
                  delay == null ? null : Navigator.of(context).pop(delay),
            ),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  await controller.sendScheduled(choice);
}

Future<Duration?> _pickCustomTime(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))),
  );
  if (time == null) return null;
  final target = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final delay = target.difference(DateTime.now());
  if (delay.isNegative || delay.inMilliseconds < 1000) {
    return const Duration(seconds: 5);
  }
  return delay;
}

/// Management surface listing pending delayed events of the room with
/// send-now / restart / cancel actions.
Future<void> showDelayedEventsSheet(
  BuildContext context,
  ChatController controller,
) async {
  await showAdaptiveBottomSheet(
    context: context,
    builder: (context) => DelayedEventsList(controller: controller),
  );
}

class DelayedEventsList extends StatefulWidget {
  final ChatController controller;

  const DelayedEventsList({required this.controller, super.key});

  @override
  State<DelayedEventsList> createState() => _DelayedEventsListState();
}

class _DelayedEventsListState extends State<DelayedEventsList> {
  List<ScheduledDelayedEvent>? events;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Matrix.of(
        context,
      ).client.listDelayedEvents(widget.controller.roomId);
      if (!mounted) return;
      setState(() {
        events = result;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e;
      });
    }
  }

  Future<void> _manage(
    ScheduledDelayedEvent event,
    DelayedEventAction action,
  ) async {
    final l10n = L10n.of(context);
    try {
      await Matrix.of(context).client.manageDelayedEvent(event.delayId, action);
      if (!mounted) return;
      if (action != DelayedEventAction.restart) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == DelayedEventAction.cancel
                  ? l10n.cancelScheduledMessage
                  : l10n.sendScheduledNow,
            ),
          ),
        );
      }
      await _load();
    } catch (e) {
      Logs().d('Managing delayed event failed', e);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  String _remainingLabel(ScheduledDelayedEvent event) {
    final remaining = event.parseRemaining();
    if (remaining.inHours >= 1) {
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes.remainder(60);
      return minutes > 0 ? '$hours h $minutes min' : '$hours h';
    }
    if (remaining.inMinutes >= 1) {
      return '${remaining.inMinutes} min';
    }
    return '${remaining.inSeconds} s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.scheduledMessagesTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: IconButton(
              tooltip: L10n.of(context).tryAgain,
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  events = null;
                });
                _load();
              },
            ),
          ),
          Flexible(
            child: Builder(
              builder: (context) {
                if (error != null) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      error.toString(),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  );
                }
                final list = events;
                if (list == null) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.noScheduledMessages),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final event = list[i];
                    return ListTile(
                      leading: const Icon(Icons.schedule_send_outlined),
                      title: Text(
                        event.bodyPreview ?? '[${event.type}]',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_remainingLabel(event)),
                      trailing: PopupMenuButton<DelayedEventAction>(
                        onSelected: (action) => _manage(event, action),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: DelayedEventAction.send,
                            child: Row(
                              children: [
                                const Icon(Icons.send_outlined),
                                const SizedBox(width: 12),
                                Text(l10n.sendScheduledNow),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: DelayedEventAction.restart,
                            child: Row(
                              children: [
                                const Icon(Icons.restart_alt),
                                const SizedBox(width: 12),
                                Text(l10n.rescheduleScheduledMessage),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: DelayedEventAction.cancel,
                            child: Row(
                              children: [
                                const Icon(Icons.cancel_outlined),
                                const SizedBox(width: 12),
                                Text(l10n.cancelScheduledMessage),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
