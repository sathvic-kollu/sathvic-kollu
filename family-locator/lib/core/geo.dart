import 'dart:math' as math;

import 'models.dart';

const _earthRadiusM = 6371000.0;

double _rad(double deg) => deg * math.pi / 180;

/// Great-circle distance in metres.
double distanceM(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
}

double fixDistanceM(LocationFix a, LocationFix b) =>
    distanceM(a.lat, a.lng, b.lat, b.lng);

/// Classifies movement from speed, smoothing over recent fixes so one GPS
/// jump doesn't turn a walk into a car ride.
class MovementClassifier {
  MovementClassifier({this.window = 3});

  final int window;
  LocationFix? _previous;
  final List<double> _speeds = [];

  static MovementType fromSpeed(double mps) {
    if (mps < 0.5) return MovementType.stationary;
    if (mps < 2.2) return MovementType.walking;
    if (mps < 4.0) return MovementType.running;
    if (mps < 8.0) return MovementType.cycling;
    return MovementType.vehicle;
  }

  MovementType classify(LocationFix fix) {
    final previous = _previous;
    _previous = fix;

    double? speed = fix.speedMps;
    if ((speed == null || speed < 0) && previous != null) {
      final seconds = fix.at.difference(previous.at).inMilliseconds / 1000;
      final moved = fixDistanceM(previous, fix);
      // Movement smaller than the combined uncertainty is noise, not motion.
      final noise = fix.accuracyM + previous.accuracyM;
      if (seconds > 0) speed = moved <= noise ? 0 : moved / seconds;
    }
    if (speed == null || speed < 0) return MovementType.unknown;

    _speeds.add(speed);
    if (_speeds.length > window) _speeds.removeAt(0);
    final sorted = [..._speeds]..sort();
    return fromSpeed(sorted[sorted.length ~/ 2]);
  }
}

/// A zone crossing that survived the noise filters.
class ZoneTransition {
  const ZoneTransition(this.zone, {required this.entered, required this.at});

  final Zone zone;
  final bool entered;
  final DateTime at;
}

class _ZoneState {
  bool? inside;
  bool? pending;
  int pendingCount = 0;
}

/// Turns raw fixes into arrive/leave transitions without the false alarms
/// that plague naive geofencing:
///
/// * fixes too inaccurate to decide (accuracy wider than the zone) are skipped;
/// * leaving needs the child to be clearly outside (radius + buffer), so a
///   fix wobbling on the boundary doesn't flap in/out;
/// * a change has to be confirmed by [confirmations] consecutive fixes unless
///   the fix is precise relative to the zone.
class GeofenceEngine {
  GeofenceEngine({this.confirmations = 2, this.exitBufferM = 40});

  final int confirmations;
  final double exitBufferM;
  final Map<String, _ZoneState> _states = {};

  /// Zone the child is currently inside, preferring the smallest one when
  /// zones overlap (a classroom inside a campus).
  String? currentZoneId(List<Zone> zones) {
    Zone? best;
    for (final z in zones) {
      if (_states[z.id]?.inside == true &&
          (best == null || z.radiusM < best.radiusM)) {
        best = z;
      }
    }
    return best?.id;
  }

  /// Seeds state without emitting transitions, e.g. after an app restart.
  void seed(String zoneId, bool inside) =>
      _states.putIfAbsent(zoneId, _ZoneState.new).inside = inside;

  List<ZoneTransition> update(LocationFix fix, List<Zone> zones) {
    _states.removeWhere((id, _) => !zones.any((z) => z.id == id));
    final out = <ZoneTransition>[];
    for (final zone in zones) {
      final state = _states.putIfAbsent(zone.id, _ZoneState.new);
      if (fix.accuracyM > math.max(zone.radiusM, 100)) continue;

      final d = distanceM(fix.lat, fix.lng, zone.lat, zone.lng);
      final bool? observed;
      if (d <= zone.radiusM) {
        observed = true;
      } else if (d > zone.radiusM + math.max(exitBufferM, fix.accuracyM)) {
        observed = false;
      } else {
        observed = null; // In the boundary band: keep the current state.
      }
      if (observed == null) {
        state.pending = null;
        state.pendingCount = 0;
        continue;
      }

      if (state.inside == null) {
        // First decisive fix just establishes where we are.
        state.inside = observed;
        continue;
      }
      if (observed == state.inside) {
        state.pending = null;
        state.pendingCount = 0;
        continue;
      }

      state.pendingCount = state.pending == observed ? state.pendingCount + 1 : 1;
      state.pending = observed;
      final precise = fix.accuracyM <= zone.radiusM / 3;
      if (precise || state.pendingCount >= confirmations) {
        state.inside = observed;
        state.pending = null;
        state.pendingCount = 0;
        out.add(ZoneTransition(zone, entered: observed, at: fix.at));
      }
    }
    return out;
  }
}

/// How the child's phone should ask the OS for location right now.
class LocationRequestSpec {
  const LocationRequestSpec({
    required this.highAccuracy,
    required this.interval,
    required this.distanceFilterM,
    required this.label,
  });

  final bool highAccuracy;
  final Duration interval;
  final int distanceFilterM;

  /// Shown in the child's status card and parent's health view.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is LocationRequestSpec &&
      other.highAccuracy == highAccuracy &&
      other.interval == interval &&
      other.distanceFilterM == distanceFilterM;

  @override
  int get hashCode => Object.hash(highAccuracy, interval, distanceFilterM);
}

/// Battery-aware sampling. GPS only runs hot when it buys something: the
/// child is moving, a parent is actively watching, or there is an SOS.
class AdaptiveLocationPolicy {
  static LocationRequestSpec choose({
    required MovementType movement,
    required bool insideZone,
    int? batteryPct,
    bool charging = false,
    bool liveMode = false,
    bool sosActive = false,
  }) {
    if (sosActive) {
      return const LocationRequestSpec(
          highAccuracy: true,
          interval: Duration(seconds: 5),
          distanceFilterM: 0,
          label: 'SOS: continuous');
    }
    if (liveMode) {
      return const LocationRequestSpec(
          highAccuracy: true,
          interval: Duration(seconds: 5),
          distanceFilterM: 5,
          label: 'Live view');
    }
    final low = !charging && batteryPct != null && batteryPct <= 15;
    if (low) {
      return const LocationRequestSpec(
          highAccuracy: false,
          interval: Duration(minutes: 5),
          distanceFilterM: 100,
          label: 'Battery saver');
    }
    switch (movement) {
      case MovementType.stationary:
        return insideZone
            ? const LocationRequestSpec(
                highAccuracy: false,
                interval: Duration(minutes: 10),
                distanceFilterM: 50,
                label: 'Resting at a place')
            : const LocationRequestSpec(
                highAccuracy: false,
                interval: Duration(minutes: 3),
                distanceFilterM: 30,
                label: 'Resting');
      case MovementType.walking:
      case MovementType.running:
        return const LocationRequestSpec(
            highAccuracy: true,
            interval: Duration(seconds: 30),
            distanceFilterM: 15,
            label: 'On foot');
      case MovementType.cycling:
      case MovementType.vehicle:
        return const LocationRequestSpec(
            highAccuracy: true,
            interval: Duration(seconds: 15),
            distanceFilterM: 50,
            label: 'Travelling');
      case MovementType.unknown:
        return const LocationRequestSpec(
            highAccuracy: true,
            interval: Duration(minutes: 1),
            distanceFilterM: 20,
            label: 'Starting up');
    }
  }
}

/// Fires a low-battery alert once per discharge, not on every update.
class BatteryAlertGate {
  BatteryAlertGate({this.threshold = 15, this.rearmAbove = 25});

  int threshold;
  final int rearmAbove;
  bool _armed = true;

  bool shouldAlert(int pct, {required bool charging}) {
    if (charging || pct >= rearmAbove) {
      _armed = true;
      return false;
    }
    if (_armed && pct <= threshold) {
      _armed = false;
      return true;
    }
    return false;
  }
}

/// How fresh a child's last report is, in words a parent can trust.
enum Freshness { live, recent, stale }

Freshness freshnessOf(DateTime lastSeen, DateTime now, {int staleAfterMinutes = 30}) {
  final age = now.difference(lastSeen);
  if (age <= const Duration(minutes: 2)) return Freshness.live;
  if (age <= Duration(minutes: staleAfterMinutes)) return Freshness.recent;
  return Freshness.stale;
}

String ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// A stay (time spent in one spot) or a move between stays.
class TimelineEntry {
  const TimelineEntry({
    required this.start,
    required this.end,
    required this.isStay,
    required this.lat,
    required this.lng,
    this.zone,
    this.distanceM = 0,
  });

  final DateTime start;
  final DateTime end;
  final bool isStay;
  final double lat;
  final double lng;
  final Zone? zone;

  /// Distance covered, for moves.
  final double distanceM;

  Duration get duration => end.difference(start);
}

/// Collapses a day of fixes into "Home 07:10–08:02 · walked 1.2 km ·
/// School 08:15–15:30". A stay is [stayRadiusM] of wandering for at least
/// [minStay].
List<TimelineEntry> buildTimeline(
  List<LocationFix> fixes,
  List<Zone> zones, {
  double stayRadiusM = 80,
  Duration minStay = const Duration(minutes: 5),
}) {
  if (fixes.isEmpty) return const [];
  final sorted = [...fixes]..sort((a, b) => a.at.compareTo(b.at));

  Zone? zoneAt(double lat, double lng) {
    Zone? best;
    for (final z in zones) {
      if (distanceM(lat, lng, z.lat, z.lng) <= z.radiusM &&
          (best == null || z.radiusM < best.radiusM)) {
        best = z;
      }
    }
    return best;
  }

  // Find clusters of consecutive fixes that stay near their first point.
  final clusters = <List<LocationFix>>[];
  var current = <LocationFix>[sorted.first];
  for (final f in sorted.skip(1)) {
    if (fixDistanceM(current.first, f) <= stayRadiusM) {
      current.add(f);
    } else {
      clusters.add(current);
      current = [f];
    }
  }
  clusters.add(current);

  final entries = <TimelineEntry>[];
  List<LocationFix> moving = [];

  void flushMove(DateTime until, {LocationFix? next}) {
    if (moving.isEmpty) return;
    var dist = 0.0;
    for (var i = 1; i < moving.length; i++) {
      dist += fixDistanceM(moving[i - 1], moving[i]);
    }
    if (entries.isNotEmpty && entries.last.isStay) {
      dist += distanceM(entries.last.lat, entries.last.lng, moving.first.lat,
          moving.first.lng);
    }
    if (next != null) dist += fixDistanceM(moving.last, next);
    entries.add(TimelineEntry(
      start: moving.first.at,
      end: until,
      isStay: false,
      lat: moving.last.lat,
      lng: moving.last.lng,
      distanceM: dist,
    ));
    moving = [];
  }

  for (final c in clusters) {
    final span = c.last.at.difference(c.first.at);
    if (span >= minStay) {
      flushMove(c.first.at, next: c.first);
      final lat = c.map((f) => f.lat).reduce((a, b) => a + b) / c.length;
      final lng = c.map((f) => f.lng).reduce((a, b) => a + b) / c.length;
      entries.add(TimelineEntry(
        start: c.first.at,
        end: c.last.at,
        isStay: true,
        lat: lat,
        lng: lng,
        zone: zoneAt(lat, lng),
      ));
    } else {
      moving.addAll(c);
    }
  }
  flushMove(moving.isEmpty ? sorted.last.at : moving.last.at);
  return entries;
}
