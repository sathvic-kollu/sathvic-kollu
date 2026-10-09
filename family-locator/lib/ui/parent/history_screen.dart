import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../core/models.dart';
import '../common/widgets.dart';
import 'parent_data.dart';

/// A day as stays and journeys rather than a scribble of dots.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.childId});

  final String childId;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime day = DateTime.now();
  final _map = MapController();

  @override
  Widget build(BuildContext context) {
    final d = context.watch<ParentData>();
    final child = d.childById(widget.childId);
    final scheme = Theme.of(context).colorScheme;
    final today = DateUtils.isSameDay(day, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text('${child?.name ?? ''}: ${today ? 'today' : DateFormat.MMMEd().format(day)}'),
        actions: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: today ? null : () => setState(() => day = day.add(const Duration(days: 1))),
          ),
        ],
      ),
      body: StreamBuilder<List<LocationFix>>(
        stream: d.backend.watchHistory(d.familyId, widget.childId, day),
        builder: (context, snap) {
          final fixes = snap.data ?? const <LocationFix>[];
          if (snap.connectionState == ConnectionState.waiting && fixes.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (fixes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No route for this day. History is kept for 30 days, then deleted.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final timeline = buildTimeline(fixes, d.zones.values.toList()).reversed.toList();
          final points = fixes.map((f) => ll(f.lat, f.lng)).toList();
          return Column(children: [
            SizedBox(
              height: 280,
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: points,
                    padding: const EdgeInsets.all(40),
                    maxZoom: 16,
                  ),
                ),
                children: [
                  osmTiles(),
                  zoneCircles(d.zones.values, scheme.primary),
                  PolylineLayer(polylines: [
                    Polyline(points: points, strokeWidth: 4, color: scheme.tertiary),
                  ]),
                  MarkerLayer(markers: [
                    for (final e in timeline.where((e) => e.isStay))
                      Marker(
                        point: ll(e.lat, e.lng),
                        width: 28,
                        height: 28,
                        child: Text(e.zone?.emoji ?? '⏸️', style: const TextStyle(fontSize: 20)),
                      ),
                  ]),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: timeline.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final e = timeline[i];
                  final mins = e.duration.inMinutes;
                  final length = mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min';
                  return ListTile(
                    onTap: () => _map.move(ll(e.lat, e.lng), 16),
                    leading: CircleAvatar(
                      child: e.isStay
                          ? Text(e.zone?.emoji ?? '📍')
                          : const Icon(Icons.directions_walk),
                    ),
                    title: Text(e.isStay
                        ? (e.zone?.name ?? 'Stopped')
                        : 'Moved ${(e.distanceM / 1000).toStringAsFixed(1)} km'),
                    subtitle: Text('${hm.format(e.start)}–${hm.format(e.end)} · $length'),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}
