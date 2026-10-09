import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models.dart';
import '../../config.dart';
import '../common/legal.dart';
import '../common/widgets.dart';
import 'parent_data.dart';
import 'zones_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  String _t(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = context.watch<ParentData>();
    final s = d.settings;
    Future<void> save(FamilySettings next) => d.backend.saveSettings(d.familyId, next);

    return SafeArea(
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SectionTitle('Family'),
        ListTile(
          leading: const Icon(Icons.person_add),
          title: const Text('Add family member'),
          subtitle: const Text('A child, or another parent or guardian'),
          onTap: () => _invite(context, d),
        ),
        ListTile(
          leading: const Icon(Icons.place),
          title: const Text('Places'),
          subtitle: Text('${d.zones.length} saved'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(value: d, child: const ZonesScreen())),
          ),
        ),
        const SectionTitle('Notifications'),
        SwitchListTile(
          secondary: const Icon(Icons.bedtime),
          title: const Text('Quiet hours'),
          subtitle: Text(s.quietHours == null
              ? 'Off'
              : '${_t(s.quietHours!.startMinute)}–${_t(s.quietHours!.endMinute)}. '
                  'Place and battery alerts wait for a morning summary. SOS always rings.'),
          value: s.quietHours != null,
          onChanged: (on) => save(on
              ? s.copyWith(
                  quietHours: const TimeWindow(weekdays: {1, 2, 3, 4, 5, 6, 7}, startMinute: 22 * 60, endMinute: 7 * 60))
              : s.copyWith(clearQuietHours: true)),
        ),
        if (s.quietHours != null)
          Row(children: [
            const SizedBox(width: 56),
            TextButton(
              onPressed: () async {
                final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: s.quietHours!.startMinute ~/ 60, minute: s.quietHours!.startMinute % 60));
                if (t != null) {
                  await save(s.copyWith(
                      quietHours: TimeWindow(
                          weekdays: s.quietHours!.weekdays,
                          startMinute: t.hour * 60 + t.minute,
                          endMinute: s.quietHours!.endMinute)));
                }
              },
              child: Text('From ${_t(s.quietHours!.startMinute)}'),
            ),
            TextButton(
              onPressed: () async {
                final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: s.quietHours!.endMinute ~/ 60, minute: s.quietHours!.endMinute % 60));
                if (t != null) {
                  await save(s.copyWith(
                      quietHours: TimeWindow(
                          weekdays: s.quietHours!.weekdays,
                          startMinute: s.quietHours!.startMinute,
                          endMinute: t.hour * 60 + t.minute)));
                }
              },
              child: Text('To ${_t(s.quietHours!.endMinute)}'),
            ),
          ]),
        ListTile(
          leading: const Icon(Icons.battery_alert),
          title: Text('Low battery alert at ${s.lowBatteryPct}%'),
          subtitle: Slider(
            min: 5,
            max: 30,
            divisions: 5,
            value: s.lowBatteryPct.toDouble(),
            onChanged: (v) => save(s.copyWith(lowBatteryPct: v.round())),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.location_disabled),
          title: Text('Warn me after ${s.staleAfterMinutes} min without updates'),
          subtitle: Slider(
            min: 15,
            max: 120,
            divisions: 7,
            value: s.staleAfterMinutes.toDouble().clamp(15, 120),
            onChanged: (v) => save(s.copyWith(staleAfterMinutes: v.round())),
          ),
        ),
        const SectionTitle('Kids\' privacy'),
        ListTile(
          leading: const Icon(Icons.pause_circle_outline),
          title: Text(s.maxPauseMinutes == 0 ? 'Kids cannot pause sharing' : 'Kids can pause for up to ${s.maxPauseMinutes} min'),
          subtitle: Slider(
            min: 0,
            max: 240,
            divisions: 8,
            value: s.maxPauseMinutes.toDouble().clamp(0, 240),
            onChanged: (v) => save(s.copyWith(maxPauseMinutes: v.round())),
          ),
        ),
        const ListTile(
          leading: Icon(Icons.visibility),
          title: Text('Kids see when you check on them'),
          subtitle: Text('Always on. Covert listening and hidden mode are deliberately not offered.'),
        ),
        const SectionTitle('Plan'),
        const ListTile(
          leading: Icon(Icons.favorite_outline),
          title: Text('Free: SOS, places, alerts, history, ring'),
          subtitle: Text('No ads. No pay-per-minute features. If a paid tier is added, '
              'cancelling will be one tap here, with a reminder before every renewal.'),
        ),
        const SectionTitle('About'),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text('Backend: ${d.backend.name}'),
          subtitle: Text('Signed in as ${d.session.displayName}'),
        ),
        if (app.isDemo)
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Demo: open Mia\'s phone'),
            subtitle: const Text('See the child app the simulated child is using'),
            onTap: app.openDemoChildPhone,
          ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          onTap: () => openLink(privacyPolicyUrl),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Terms of use'),
          onTap: () => openLink(termsUrl),
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Help & contact'),
          subtitle: const Text(supportEmail),
          onTap: emailSupport,
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Sign out?'),
                content: Text(app.isDemo ? 'Demo data will be cleared.' : 'You can join again with a family code.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
                ],
              ),
            );
            if (ok == true) await app.signOut();
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
          title: Text('Delete my account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          subtitle: const Text('Erases your data; the whole family if you are the last parent'),
          onTap: () async {
            if (await confirmDeletion(context, child: false) && context.mounted) {
              await runGuarded(context, app.deleteAccount);
            }
          },
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _invite(BuildContext context, ParentData d) async {
    final messenger = ScaffoldMessenger.of(context);
    final role = await showModalBottomSheet<Role>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Who are you adding?')),
          ListTile(
            leading: const Icon(Icons.child_care),
            title: const Text('A child'),
            subtitle: const Text('Their phone shares location with the family'),
            onTap: () => Navigator.pop(context, Role.child),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Another parent or guardian'),
            subtitle: const Text('They see the kids and get alerts, like you'),
            onTap: () => Navigator.pop(context, Role.parent),
          ),
        ]),
      ),
    );
    if (role == null) return;
    String code;
    try {
      code = await d.backend.createInviteCode(d.familyId, role: role);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Family code'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Install Family Locator on their phone, tap "I have a family code", choose '
              '${role == Role.child ? '"I\'m the child"' : '"I\'m a guardian"'} and enter:'),
          const SizedBox(height: 16),
          SelectableText(code,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 6, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Expires in 24 hours. Use it for each new family member.'),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
              messenger.showSnackBar(const SnackBar(content: Text('Code copied')));
            },
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}
