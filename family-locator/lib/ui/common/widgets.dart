import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../config.dart';
import '../../core/geo.dart';
import '../../core/models.dart';

final hm = DateFormat.Hm();

String movementLabel(MovementType m) => switch (m) {
      MovementType.stationary => 'Not moving',
      MovementType.walking => 'Walking',
      MovementType.running => 'Running',
      MovementType.cycling => 'Cycling',
      MovementType.vehicle => 'In a vehicle',
      MovementType.unknown => 'Location',
    };

String privacyLabel(PrivacyMode m) => switch (m) {
      PrivacyMode.live => 'Live location',
      PrivacyMode.placesOnly => 'Places only',
      PrivacyMode.checkInOnly => 'Check-ins only',
    };

String privacyExplainer(PrivacyMode m) => switch (m) {
      PrivacyMode.live => 'Live map position, route history, place alerts and battery.',
      PrivacyMode.placesOnly =>
        'Only which saved place they are at (or "out"), arrivals/departures and battery. '
            'No map position or route. Good for teens.',
      PrivacyMode.checkInOnly => 'Nothing until they check in or press SOS. Battery is still shared.',
    };

/// One honest line about where a child is and how sure we are.
class ChildStatus {
  ChildStatus(this.child, this.zones, this.now, {this.staleAfterMinutes = 30});

  final ChildProfile child;
  final Map<String, Zone> zones;
  final DateTime now;
  final int staleAfterMinutes;

  Zone? get zone => zones[child.currentZoneId];

  DateTime? get lastSeen {
    final a = child.lastFix?.at;
    final b = child.health?.lastSeen;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  Freshness get freshness =>
      lastSeen == null ? Freshness.stale : freshnessOf(lastSeen!, now, staleAfterMinutes: staleAfterMinutes);

  bool get needsAttention =>
      child.sosActiveSince != null ||
      (child.health?.issues.isNotEmpty ?? false) ||
      (freshness == Freshness.stale && !child.isPaused(now));

  String get headline {
    if (child.sosActiveSince != null) return 'SOS since ${hm.format(child.sosActiveSince!)}';
    if (child.isPaused(now)) return 'Paused until ${hm.format(child.pausedUntil!)}';
    switch (child.privacyMode) {
      case PrivacyMode.checkInOnly:
        return 'Shares on check-in';
      case PrivacyMode.placesOnly:
        return zone == null ? 'Out' : 'At ${zone!.name}';
      case PrivacyMode.live:
        if (zone != null) return 'At ${zone!.name}';
        final f = child.lastFix;
        return f == null ? 'Waiting for first location' : movementLabel(f.movement);
    }
  }

  String get detail {
    final parts = <String>[];
    if (child.isPaused(now) && (child.pauseReason?.isNotEmpty ?? false)) {
      parts.add('"${child.pauseReason}"');
    }
    final seen = lastSeen;
    if (seen != null) parts.add('updated ${ago(seen, now)}');
    final f = child.lastFix;
    if (child.privacyMode == PrivacyMode.live && f != null) parts.add('±${f.accuracyM.round()} m');
    if (freshness == Freshness.stale && !child.isPaused(now)) parts.add('may be offline');
    return parts.join(' · ');
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.child, {super.key, this.size = 40, this.alert = false});

  final ChildProfile child;
  final double size;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surface,
        border: Border.all(color: alert ? scheme.error : scheme.primary, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: Text(child.emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

class BatteryChip extends StatelessWidget {
  const BatteryChip(this.health, {super.key});

  final DeviceHealth? health;

  @override
  Widget build(BuildContext context) {
    final pct = health?.batteryPct;
    if (pct == null) return const SizedBox.shrink();
    final low = pct <= 15 && !(health?.charging ?? false);
    final icon = health!.charging
        ? Icons.battery_charging_full
        : pct > 80
            ? Icons.battery_full
            : pct > 50
                ? Icons.battery_5_bar
                : pct > 20
                    ? Icons.battery_3_bar
                    : Icons.battery_1_bar;
    final color = low ? Theme.of(context).colorScheme.error : null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      Text('$pct%', style: TextStyle(fontSize: 12, color: color)),
    ]);
  }
}

LatLng ll(double lat, double lng) => LatLng(lat, lng);

TileLayer osmTiles() => TileLayer(
      urlTemplate: tileUrl,
      userAgentPackageName: 'com.techtenstein.family_locator',
    );

CircleLayer zoneCircles(Iterable<Zone> zones, Color color) => CircleLayer(circles: [
      for (final z in zones)
        CircleMarker(
          point: ll(z.lat, z.lng),
          radius: z.radiusM,
          useRadiusInMeter: true,
          color: color.withValues(alpha: 0.12),
          borderColor: color.withValues(alpha: 0.6),
          borderStrokeWidth: 2,
        ),
    ]);

MarkerLayer zoneLabels(Iterable<Zone> zones) => MarkerLayer(markers: [
      for (final z in zones)
        Marker(
          point: ll(z.lat, z.lng),
          width: 36,
          height: 36,
          child: Text(z.emoji, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
        ),
    ]);

/// Accuracy circle under the marker, so a ±800 m network fix looks like one.
CircleLayer accuracyCircles(Iterable<ChildProfile> children, Color color) => CircleLayer(circles: [
      for (final c in children)
        if (c.lastFix != null)
          CircleMarker(
            point: ll(c.lastFix!.lat, c.lastFix!.lng),
            radius: c.lastFix!.accuracyM,
            useRadiusInMeter: true,
            color: color.withValues(alpha: 0.15),
            borderColor: color.withValues(alpha: 0.4),
            borderStrokeWidth: 1,
          ),
    ]);

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            )),
      );
}

Future<void> runGuarded(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

IconData alertIcon(AlertType t) => switch (t) {
      AlertType.arrived => Icons.login,
      AlertType.left => Icons.logout,
      AlertType.sos => Icons.sos,
      AlertType.sosCancelled => Icons.verified_user,
      AlertType.checkIn => Icons.check_circle,
      AlertType.lowBattery => Icons.battery_alert,
      AlertType.trackingOff => Icons.location_disabled,
      AlertType.permissionLost => Icons.location_off,
      AlertType.sharingPaused => Icons.pause_circle,
      AlertType.sharingResumed => Icons.play_circle,
      AlertType.signalAcknowledged => Icons.volume_up,
      AlertType.taskDone => Icons.task_alt,
    };
