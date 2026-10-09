import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config.dart';
import '../../core/geo.dart';
import '../../core/models.dart';
import '../../services/child_controller.dart';
import '../../services/platform_services.dart';
import '../common/legal.dart';
import '../common/widgets.dart';

class ChildHome extends StatelessWidget {
  const ChildHome({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = context.watch<ChildController>();
    final child = c.child;
    final now = DateTime.now();
    final paused = child.isPaused(now);
    final issues = c.health?.issues ?? const <String>[];

    return Stack(children: [
      Scaffold(
        appBar: AppBar(
          title: Text('Hi ${child.name} ${child.emoji}'),
          actions: [
            if (app.viewingDemoChild)
              TextButton.icon(
                onPressed: app.backToParent,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Parent view'),
              )
            else
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'privacy':
                      await openLink(privacyPolicyUrl);
                    case 'help':
                      await emailSupport();
                    case 'leave':
                      await _confirmLeave(context, app);
                    case 'delete':
                      if (await confirmDeletion(context, child: true) && context.mounted) {
                        await runGuarded(context, app.deleteAccount);
                      }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'privacy', child: Text('Privacy policy')),
                  PopupMenuItem(value: 'help', child: Text('Help & contact')),
                  PopupMenuItem(value: 'leave', child: Text('Leave family')),
                  PopupMenuItem(value: 'delete', child: Text('Delete my data and leave')),
                ],
              ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          if (issues.isNotEmpty) _SetupCard(issues: issues),
          if (c.lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(c.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          _StatusCard(controller: c, paused: paused),
          const SizedBox(height: 8),
          Center(child: _SosButton(controller: c)),
          const SectionTitle('Quick check-in'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final text in const ["I'm OK 👍", 'On my way 🚶', 'Running late ⏰', 'Pick me up please 🚗'])
                ActionChip(
                  label: Text(text),
                  onPressed: () => runGuarded(context, () => c.checkIn(text), success: 'Sent to your family'),
                ),
              ActionChip(
                avatar: const Icon(Icons.edit, size: 16),
                label: const Text('Write…'),
                onPressed: () => _customCheckIn(context, c),
              ),
            ]),
          ),
          const SectionTitle('What your family can see'),
          _VisibilityCard(controller: c),
          const SectionTitle('Who looked recently'),
          _ViewsList(controller: c),
          const SectionTitle('My tasks'),
          _TasksList(controller: c),
        ]),
      ),
      if (c.ringing != null) _RingOverlay(controller: c),
      if (!app.viewingDemoChild) const _FirstRunPermission(),
    ]);
  }

  Future<void> _customCheckIn(BuildContext context, ChildController c) async {
    final text = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message your family'),
        content: TextField(controller: text, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (send == true && text.text.trim().isNotEmpty && context.mounted) {
      await runGuarded(context, () => c.checkIn(text.text.trim()), success: 'Sent');
    }
    text.dispose();
  }

  Future<void> _confirmLeave(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave family?'),
        content: const Text('Sharing stops and your parents are no longer able to see this phone. '
            'Talk to them first: pausing might be what you need.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) await app.signOut();
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller, required this.paused});

  final ChildController controller;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final spec = c.spec;
    final intervalText = spec == null
        ? ''
        : spec.interval.inMinutes >= 1
            ? 'every ${spec.interval.inMinutes} min'
            : 'every ${spec.interval.inSeconds} s';
    return Card(
      margin: const EdgeInsets.all(16),
      color: paused ? scheme.surfaceContainerHighest : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(paused ? Icons.pause_circle : Icons.share_location, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  paused ? 'Sharing paused until ${hm.format(c.child.pausedUntil!)}' : privacyLabel(c.child.privacyMode),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!paused && spec != null)
                  Text('${spec.label} · checks $intervalText to save battery'),
                if (paused) const Text('SOS still works while paused.'),
              ]),
            ),
            BatteryChip(c.health),
          ]),
          const SizedBox(height: 12),
          if (paused)
            FilledButton.icon(
              onPressed: () => runGuarded(context, c.resume),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Share again now'),
            )
          else if (c.settings.maxPauseMinutes > 0)
            OutlinedButton.icon(
              onPressed: () => _pause(context),
              icon: const Icon(Icons.pause),
              label: const Text('Pause sharing'),
            ),
        ]),
      ),
    );
  }

  Future<void> _pause(BuildContext context) async {
    final max = controller.settings.maxPauseMinutes;
    final options = [15, 30, 60, 120, 240].where((m) => m <= max).toList();
    if (options.isEmpty || options.last != max) options.add(max);
    var minutes = options.first;
    final reason = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pause sharing', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Your family is told you paused and when it ends. It turns back on by itself.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final m in options)
                ChoiceChip(
                  label: Text(m >= 60 ? '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}' : '$m min'),
                  selected: minutes == m,
                  onSelected: (_) => setState(() => minutes = m),
                ),
            ]),
            TextField(
              controller: reason,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: "e.g. surprise for mum's birthday"),
            ),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pause')),
          ]),
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await runGuarded(context, () => controller.pause(Duration(minutes: minutes), reason.text.trim()));
    }
    reason.dispose();
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.controller});

  final ChildController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (controller.sosActive) {
      return Column(children: [
        Text('SOS sent. Your family can see where you are.',
            style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => runGuarded(context, controller.cancelSos),
          icon: const Icon(Icons.verified_user),
          label: const Text("I'm safe now"),
        ),
      ]);
    }
    return Column(children: [
      GestureDetector(
        onLongPress: () => _countdown(context),
        child: Container(
          width: 150,
          height: 150,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.error,
            boxShadow: [BoxShadow(color: scheme.error.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)],
          ),
          child: Text('SOS', style: TextStyle(color: scheme.onError, fontSize: 40, fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 8),
      const Text('Press and hold if you need help'),
    ]);
  }

  /// Five seconds to cancel an accidental press before anyone is alarmed.
  Future<void> _countdown(BuildContext context) async {
    final send = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CountdownDialog(),
    );
    if (send == true && context.mounted) await runGuarded(context, controller.sos);
  }
}

class _CountdownDialog extends StatefulWidget {
  const _CountdownDialog();

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  int left = 5;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (left <= 1) {
        t.cancel();
        Navigator.pop(context, true);
      } else {
        setState(() => left--);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Sending SOS in $left…'),
        content: const Text('Your family gets a loud alert with your exact location.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send now')),
        ],
      );
}

class _VisibilityCard extends StatelessWidget {
  const _VisibilityCard({required this.controller});

  final ChildController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.child.privacyMode;
    Widget row(bool on, String text) => ListTile(
          dense: true,
          leading: Icon(on ? Icons.visibility : Icons.visibility_off, color: on ? null : Colors.grey),
          title: Text(text),
        );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        row(mode == PrivacyMode.live, 'Where you are on the map'),
        row(mode == PrivacyMode.live, "Today's route"),
        row(mode != PrivacyMode.checkInOnly, 'Arriving at and leaving saved places'),
        row(true, 'Battery level and whether sharing works'),
        row(true, 'Your check-ins and SOS (with location)'),
        row(false, 'Your messages, photos, apps or microphone: never'),
      ]),
    );
  }
}

class _ViewsList extends StatelessWidget {
  const _ViewsList({required this.controller});

  final ChildController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.session;
    return StreamBuilder<List<ViewRecord>>(
      stream: controller.backend.watchViews(s.familyId, s.memberId),
      builder: (context, snap) {
        final views = (snap.data ?? const <ViewRecord>[]).take(5).toList();
        if (views.isEmpty) return const ListTile(dense: true, title: Text('Nobody has opened your location yet.'));
        final now = DateTime.now();
        return Column(children: [
          for (final v in views)
            ListTile(
              dense: true,
              leading: const Icon(Icons.remove_red_eye_outlined),
              title: Text('${v.viewer} checked your location'),
              trailing: Text(ago(v.at, now)),
            ),
        ]);
      },
    );
  }
}

class _TasksList extends StatelessWidget {
  const _TasksList({required this.controller});

  final ChildController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.session;
    return StreamBuilder<List<FamilyTask>>(
      stream: controller.backend.watchTasks(s.familyId),
      builder: (context, snap) {
        final tasks =
            (snap.data ?? const <FamilyTask>[]).where((t) => t.childId == s.memberId && t.status != TaskStatus.approved);
        return Column(children: [
          ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: Text('${controller.child.points} points'),
          ),
          for (final t in tasks)
            CheckboxListTile(
              value: t.status == TaskStatus.done,
              title: Text(t.title),
              subtitle: Text(t.status == TaskStatus.done ? 'Waiting for approval' : '${t.points} points'),
              onChanged: t.status == TaskStatus.done
                  ? null
                  : (_) => runGuarded(context, () => controller.markTaskDone(t), success: 'Nice! Sent for approval'),
            ),
          if (tasks.isEmpty) const ListTile(dense: true, title: Text('No tasks right now.')),
        ]);
      },
    );
  }
}

/// Walks the child through the settings that most often break tracking,
/// in plain words, instead of failing silently.
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.issues});

  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final c = context.read<ChildController>();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Finish setup so SOS and sharing work', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final i in issues) Text('• $i'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: () async {
                await requestLocationWithDisclosure(context);
                await c.refreshHealth();
              },
              child: const Text('Fix location permission'),
            ),
            OutlinedButton(
              onPressed: () async {
                await Geolocator.openLocationSettings();
                await c.refreshHealth();
              },
              child: const Text('Location settings'),
            ),
            OutlinedButton(
              onPressed: () async {
                await Notifier.instance.requestPermission();
                await c.refreshHealth();
              },
              child: const Text('Allow notifications'),
            ),
            TextButton(onPressed: c.refreshHealth, child: const Text('Check again')),
          ]),
        ]),
      ),
    );
  }
}

class _RingOverlay extends StatelessWidget {
  const _RingOverlay({required this.controller});

  final ChildController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      child: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.notifications_active, size: 96, color: scheme.onPrimary),
            const SizedBox(height: 16),
            Text('${controller.ringing?.from ?? 'Your parent'} is trying to reach you',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onPrimary)),
            const SizedBox(height: 32),
            FilledButton.tonal(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20)),
              onPressed: controller.acknowledgeRing,
              child: const Text('I hear you', style: TextStyle(fontSize: 20)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Right after joining, explains location sharing (Play's prominent
/// disclosure) and asks for permission once. The setup card covers retries.
class _FirstRunPermission extends StatefulWidget {
  const _FirstRunPermission();

  @override
  State<_FirstRunPermission> createState() => _FirstRunPermissionState();
}

class _FirstRunPermissionState extends State<_FirstRunPermission> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await Geolocator.checkPermission() == LocationPermission.always) return;
      if (!mounted) return;
      final c = context.read<ChildController>();
      await requestLocationWithDisclosure(context);
      await c.refreshHealth();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
