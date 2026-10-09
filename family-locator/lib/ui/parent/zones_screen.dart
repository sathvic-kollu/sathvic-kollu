import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/models.dart';
import '../common/widgets.dart';
import 'parent_data.dart';

class ZonesScreen extends StatelessWidget {
  const ZonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<ParentData>();
    final zones = d.zones.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Places')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add place'),
      ),
      body: zones.isEmpty
          ? const Center(child: Text('Add home and school to get arrival alerts.'))
          : ListView(children: [
              for (final z in zones)
                ListTile(
                  leading: CircleAvatar(child: Text(z.emoji)),
                  title: Text(z.name),
                  subtitle: Text([
                    '${z.radiusM.round()} m',
                    if (z.notifyArrive && z.notifyLeave)
                      'arrive + leave alerts'
                    else if (z.notifyArrive)
                      'arrival alerts'
                    else if (z.notifyLeave)
                      'leave alerts'
                    else
                      'no alerts',
                    if (z.alertWindow != null) _windowLabel(z.alertWindow!),
                  ].join(' · ')),
                  onTap: () => _edit(context, z),
                ),
              const SizedBox(height: 80),
            ]),
    );
  }

  void _edit(BuildContext context, Zone? zone) {
    final d = context.read<ParentData>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: d, child: ZoneEditor(zone: zone)),
      ),
    );
  }
}

const _dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String _time(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

String _windowLabel(TimeWindow w) {
  final days = w.weekdays.length == 7
      ? 'every day'
      : (w.weekdays.toList()..sort()).map((d) => _dayNames[d - 1]).join();
  return '$days ${_time(w.startMinute)}–${_time(w.endMinute)}';
}

class ZoneEditor extends StatefulWidget {
  const ZoneEditor({super.key, this.zone});

  final Zone? zone;

  @override
  State<ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<ZoneEditor> {
  late final TextEditingController name;
  late LatLng center;
  late double radius;
  late String emoji;
  late bool arrive;
  late bool leave;
  TimeWindow? window;

  static const emojis = ['🏠', '🏫', '⚽', '📚', '🏊', '👵', '🎹', '🏥', '🛒', '📍'];

  @override
  void initState() {
    super.initState();
    final z = widget.zone;
    final d = context.read<ParentData>();
    LatLng? fallback;
    for (final c in d.children) {
      if (c.lastFix != null) fallback ??= ll(c.lastFix!.lat, c.lastFix!.lng);
    }
    if (fallback == null && d.zones.isNotEmpty) {
      final first = d.zones.values.first;
      fallback = ll(first.lat, first.lng);
    }
    name = TextEditingController(text: z?.name ?? '');
    center = z == null ? (fallback ?? const LatLng(51.5390, -0.1030)) : ll(z.lat, z.lng);
    radius = z?.radiusM ?? 150;
    emoji = z?.emoji ?? '📍';
    arrive = z?.notifyArrive ?? true;
    leave = z?.notifyLeave ?? true;
    window = z?.alertWindow;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final w = window!;
    final current = start ? w.startMinute : w.endMinute;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60 % 24, minute: current % 60),
    );
    if (t == null) return;
    final m = t.hour * 60 + t.minute;
    setState(() => window = TimeWindow(
          weekdays: w.weekdays,
          startMinute: start ? m : w.startMinute,
          endMinute: start ? w.endMinute : m,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final d = context.read<ParentData>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zone == null ? 'New place' : 'Edit place'),
        actions: [
          if (widget.zone != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                await d.backend.deleteZone(d.familyId, widget.zone!.id);
                nav.pop();
              },
            ),
        ],
      ),
      body: ListView(children: [
        SizedBox(
          height: 260,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              onTap: (_, p) => setState(() => center = p),
            ),
            children: [
              osmTiles(),
              CircleLayer(circles: [
                CircleMarker(
                  point: center,
                  radius: radius,
                  useRadiusInMeter: true,
                  color: scheme.primary.withValues(alpha: 0.2),
                  borderColor: scheme.primary,
                  borderStrokeWidth: 2,
                ),
              ]),
              MarkerLayer(markers: [
                Marker(point: center, width: 32, height: 32, child: Text(emoji, style: const TextStyle(fontSize: 24))),
              ]),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Tap the map to move the place.'),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in emojis)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(e, style: const TextStyle(fontSize: 18)),
                    selected: emoji == e,
                    onSelected: (_) => setState(() => emoji = e),
                  ),
                ),
            ],
          ),
        ),
        ListTile(
          title: Text('Size: ${radius.round()} m'),
          subtitle: Slider(
            min: 50,
            max: 1000,
            divisions: 19,
            value: radius,
            onChanged: (v) => setState(() => radius = v),
          ),
        ),
        SwitchListTile(
          title: const Text('Tell me when they arrive'),
          value: arrive,
          onChanged: (v) => setState(() => arrive = v),
        ),
        SwitchListTile(
          title: const Text('Tell me when they leave'),
          value: leave,
          onChanged: (v) => setState(() => leave = v),
        ),
        SwitchListTile(
          title: const Text('Only alert at certain times'),
          subtitle: const Text('e.g. school alerts on school days only. Visits are still logged.'),
          value: window != null,
          onChanged: (v) => setState(() => window = v
              ? const TimeWindow(weekdays: {1, 2, 3, 4, 5}, startMinute: 7 * 60, endMinute: 17 * 60)
              : null),
        ),
        if (window != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 4, children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(_dayNames[day - 1]),
                  selected: window!.weekdays.contains(day),
                  onSelected: (on) => setState(() {
                    final days = {...window!.weekdays};
                    on ? days.add(day) : days.remove(day);
                    window = TimeWindow(weekdays: days, startMinute: window!.startMinute, endMinute: window!.endMinute);
                  }),
                ),
            ]),
          ),
          Row(children: [
            const SizedBox(width: 16),
            TextButton(onPressed: () => _pickTime(true), child: Text('From ${_time(window!.startMinute)}')),
            TextButton(onPressed: () => _pickTime(false), child: Text('To ${_time(window!.endMinute)}')),
          ]),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () async {
              final label = name.text.trim();
              if (label.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the place a name.')));
                return;
              }
              final nav = Navigator.of(context);
              await d.backend.saveZone(
                d.familyId,
                Zone(
                  id: widget.zone?.id ?? newId(),
                  name: label,
                  lat: center.latitude,
                  lng: center.longitude,
                  radiusM: radius,
                  emoji: emoji,
                  notifyArrive: arrive,
                  notifyLeave: leave,
                  alertWindow: window,
                ),
              );
              nav.pop();
            },
            child: const Text('Save place'),
          ),
        ),
      ]),
    );
  }
}
