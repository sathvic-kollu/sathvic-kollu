import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../core/models.dart';
import '../common/widgets.dart';
import 'child_detail_screen.dart';
import 'parent_data.dart';
import 'zones_screen.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final _map = MapController();
  int _fittedPins = 0;

  List<LatLng> _points(ParentData d) => [
        for (final c in d.children) ?_pin(c, d),
        if (d.children.isEmpty) ...d.zones.values.map((z) => ll(z.lat, z.lng)),
      ];

  void _fit(ParentData d) {
    final pts = _points(d);
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.first, 15);
    } else {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(60), maxZoom: 16));
    }
  }

  /// Where to draw a child: their fix in live mode, else their place's centre.
  LatLng? _pin(ChildProfile c, ParentData d) {
    final showFix = c.privacyMode == PrivacyMode.live || c.sosActiveSince != null;
    if (showFix && c.lastFix != null) return ll(c.lastFix!.lat, c.lastFix!.lng);
    final z = d.zones[c.currentZoneId];
    return z == null ? null : ll(z.lat, z.lng);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<ParentData>();
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    // Refit when someone new appears on the map, not on every update.
    final pins = _points(d).length;
    if (pins > _fittedPins) {
      _fittedPins = pins;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(d));
    }
    final liveChildren =
        d.children.where((c) => c.privacyMode == PrivacyMode.live || c.sosActiveSince != null);

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: const MapOptions(initialCenter: LatLng(51.5390, -0.1030), initialZoom: 14),
        children: [
          osmTiles(),
          zoneCircles(d.zones.values, scheme.primary),
          zoneLabels(d.zones.values),
          accuracyCircles(liveChildren, scheme.tertiary),
          MarkerLayer(markers: [
            for (final c in d.children)
              if (_pin(c, d) != null)
                Marker(
                  point: _pin(c, d)!,
                  width: 48,
                  height: 48,
                  child: GestureDetector(
                    onTap: () => _open(context, c),
                    child: Avatar(c, size: 44, alert: ChildStatus(c, d.zones, now).needsAttention),
                  ),
                ),
          ]),
          const SimpleAttributionWidget(source: Text(tileAttribution)),
        ],
      ),
      SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              FloatingActionButton.small(
                heroTag: 'fit',
                tooltip: 'Show everyone',
                onPressed: () => _fit(d),
                child: const Icon(Icons.center_focus_strong),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'places',
                tooltip: 'Places',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(value: d, child: const ZonesScreen()),
                  ),
                ),
                child: const Icon(Icons.add_location_alt),
              ),
            ]),
          ),
        ),
      ),
      DraggableScrollableSheet(
        initialChildSize: 0.32,
        minChildSize: 0.12,
        maxChildSize: 0.8,
        builder: (context, scroll) => Material(
          elevation: 8,
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: ListView(
            controller: scroll,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              if (d.children.isEmpty)
                const ListTile(
                  leading: Icon(Icons.person_add),
                  title: Text('No children yet'),
                  subtitle: Text('Settings → Add family member gives you a code to type on their phone.'),
                ),
              for (final c in d.children) _ChildTile(child: c, onTap: () => _open(context, c)),
            ],
          ),
        ),
      ),
    ]);
  }

  void _open(BuildContext context, ChildProfile c) {
    final d = context.read<ParentData>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: d, child: ChildDetailScreen(childId: c.id)),
      ),
    );
  }
}

class _ChildTile extends StatelessWidget {
  const _ChildTile({required this.child, required this.onTap});

  final ChildProfile child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<ParentData>();
    final status = ChildStatus(child, d.zones, DateTime.now(), staleAfterMinutes: d.settings.staleAfterMinutes);
    final scheme = Theme.of(context).colorScheme;
    final issues = child.health?.issues ?? const [];
    return ListTile(
      onTap: onTap,
      leading: Avatar(child, alert: status.needsAttention),
      title: Row(children: [
        Expanded(child: Text('${child.name} · ${status.headline}', overflow: TextOverflow.ellipsis)),
        BatteryChip(child.health),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(status.detail),
        if (issues.isNotEmpty)
          Text('⚠ ${issues.first}', style: TextStyle(color: scheme.error, fontSize: 12)),
        if (child.privacyMode != PrivacyMode.live)
          Text(privacyLabel(child.privacyMode), style: TextStyle(color: scheme.primary, fontSize: 12)),
      ]),
      isThreeLine: issues.isNotEmpty || child.privacyMode != PrivacyMode.live,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
