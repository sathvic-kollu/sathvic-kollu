import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../common/widgets.dart';
import 'history_screen.dart';
import 'parent_data.dart';

class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({super.key, required this.childId});

  final String childId;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    // The child sees this in "Who looked".
    context.read<ParentData>().recordView(widget.childId);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<ParentData>();
    final c = d.childById(widget.childId);
    if (c == null) return const Scaffold(body: Center(child: Text('This child left the family.')));
    final now = DateTime.now();
    final status = ChildStatus(c, d.zones, now, staleAfterMinutes: d.settings.staleAfterMinutes);
    final scheme = Theme.of(context).colorScheme;
    final showMap = (c.privacyMode == PrivacyMode.live || c.sosActiveSince != null) && c.lastFix != null;
    final issues = c.health?.issues ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: Text('${c.emoji} ${c.name}')),
      body: ListView(children: [
        if (showMap)
          SizedBox(
            height: 260,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(initialCenter: ll(c.lastFix!.lat, c.lastFix!.lng), initialZoom: 16),
              children: [
                osmTiles(),
                zoneCircles(d.zones.values, scheme.primary),
                zoneLabels(d.zones.values),
                accuracyCircles([c], scheme.tertiary),
                MarkerLayer(markers: [
                  Marker(point: ll(c.lastFix!.lat, c.lastFix!.lng), width: 48, height: 48, child: Avatar(c, size: 44)),
                ]),
              ],
            ),
          ),
        ListTile(
          leading: Avatar(c, alert: status.needsAttention),
          title: Text(status.headline, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(status.detail),
          trailing: BatteryChip(c.health),
        ),
        if (c.sosActiveSince != null)
          Card(
            color: scheme.errorContainer,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: const ListTile(
              leading: Icon(Icons.sos),
              title: Text('SOS is active'),
              subtitle: Text('Their phone is sending its exact location every few seconds until they cancel.'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.volume_up),
              label: const Text('Ring loudly'),
              onPressed: () => runGuarded(context, () => d.sendCommand(c.id, CommandType.ring),
                  success: 'Ringing ${c.name}\'s phone, even on silent'),
            ),
            if (c.privacyMode == PrivacyMode.live)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Live for 5 min'),
                onPressed: () => runGuarded(context, () => d.sendCommand(c.id, CommandType.liveMode),
                    success: 'Updates every few seconds for 5 minutes'),
              ),
            if (c.privacyMode == PrivacyMode.live)
              OutlinedButton.icon(
                icon: const Icon(Icons.timeline),
                label: const Text('Today\'s route'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(value: d, child: HistoryScreen(childId: c.id)),
                  ),
                ),
              ),
          ]),
        ),
        const SectionTitle('Phone health'),
        if (c.health == null)
          const ListTile(title: Text('No report from this phone yet.'))
        else ...[
          if (issues.isEmpty)
            const ListTile(
              leading: Icon(Icons.verified, color: Colors.green),
              title: Text('Everything needed for reliable sharing is on'),
            ),
          for (final issue in issues)
            ListTile(
              leading: Icon(Icons.warning_amber, color: scheme.error),
              title: Text(issue),
              subtitle: const Text('Ask them to open Family Locator. It walks them through the fix.'),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline),
            title: Text('Last report ${ago(c.health!.lastSeen, now)}'
                '${c.health!.appVersion.isEmpty ? '' : ' · app ${c.health!.appVersion}'}'),
          ),
        ],
        const SectionTitle('What they share'),
        RadioGroup<PrivacyMode>(
          groupValue: c.privacyMode,
          onChanged: (m) {
            if (m != null) runGuarded(context, () => d.backend.updateChild(d.familyId, c.copyWith(privacyMode: m)));
          },
          child: Column(children: [
            for (final m in PrivacyMode.values)
              RadioListTile<PrivacyMode>(
                value: m,
                title: Text(privacyLabel(m)),
                subtitle: Text(privacyExplainer(m)),
              ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Text(
            'Whatever you pick, SOS always shares exact location, and they can always see '
            'what is shared and when you looked.',
          ),
        ),
      ]),
    );
  }
}
