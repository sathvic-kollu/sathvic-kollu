import 'geo.dart';
import 'models.dart';

/// What the child's device should publish after processing one fix.
class TrackerOutput {
  const TrackerOutput({
    required this.spec,
    this.sharedFix,
    this.zoneId,
    this.shareZone = false,
    this.events = const [],
  });

  /// Fix to upload, or null if the privacy mode/pause withholds it.
  final LocationFix? sharedFix;

  /// Current zone, only meaningful when [shareZone] is true.
  final String? zoneId;
  final bool shareZone;
  final List<AlertEvent> events;

  /// Sampling the OS should use from now on.
  final LocationRequestSpec spec;
}

/// All of the child-side decision making, free of Flutter and plugins so it
/// can be unit-tested and reused by the demo simulator.
class ChildTracker {
  ChildTracker({
    required this.child,
    required this.newId,
    this.zones = const [],
    FamilySettings settings = const FamilySettings(),
    GeofenceEngine? engine,
  })  : _engine = engine ?? GeofenceEngine(),
        _battery = BatteryAlertGate(threshold: settings.lowBatteryPct);

  ChildProfile child;
  final String Function() newId;
  List<Zone> zones;
  final GeofenceEngine _engine;
  final BatteryAlertGate _battery;
  final MovementClassifier _movement = MovementClassifier();

  DateTime? _liveUntil;
  DateTime? _sosSince;
  LocationFix? _last;
  MovementType _lastMovement = MovementType.unknown;

  LocationFix? get lastFix => _last;
  bool get sosActive => _sosSince != null;

  set settings(FamilySettings s) => _battery.threshold = s.lowBatteryPct;

  void startLiveMode(DateTime now, {Duration length = const Duration(minutes: 5)}) =>
      _liveUntil = now.add(length);

  String? get currentZoneId => _engine.currentZoneId(zones);

  Zone? zoneById(String? id) {
    for (final z in zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  LocationRequestSpec currentSpec(DateTime now, {int? batteryPct, bool charging = false}) =>
      AdaptiveLocationPolicy.choose(
        movement: _lastMovement,
        insideZone: currentZoneId != null,
        batteryPct: batteryPct,
        charging: charging,
        liveMode: _liveUntil != null && now.isBefore(_liveUntil!),
        sosActive: sosActive,
      );

  TrackerOutput onFix(LocationFix raw, {int? batteryPct, bool charging = false}) {
    final now = raw.at;
    final movement = _movement.classify(raw);
    _lastMovement = movement;
    final fix = raw.copyWith(movement: movement, batteryPct: batteryPct);
    _last = fix;

    final transitions = _engine.update(fix, zones);
    final paused = child.isPaused(now);
    final mode = child.privacyMode;
    final events = <AlertEvent>[];

    final shareTransitions = !paused && mode != PrivacyMode.checkInOnly;
    if (shareTransitions) {
      for (final t in transitions) {
        if (t.entered ? !t.zone.notifyArrive : !t.zone.notifyLeave) continue;
        events.add(AlertEvent(
          id: newId(),
          childId: child.id,
          type: t.entered ? AlertType.arrived : AlertType.left,
          at: t.at,
          message: '${child.name} ${t.entered ? 'arrived at' : 'left'} ${t.zone.name}',
          zoneId: t.zone.id,
          lat: mode == PrivacyMode.live ? fix.lat : null,
          lng: mode == PrivacyMode.live ? fix.lng : null,
        ));
      }
    }

    if (batteryPct != null && _battery.shouldAlert(batteryPct, charging: charging)) {
      events.add(AlertEvent(
        id: newId(),
        childId: child.id,
        type: AlertType.lowBattery,
        at: now,
        message: "${child.name}'s phone is at $batteryPct%",
      ));
    }

    final shareFix = sosActive || (!paused && mode == PrivacyMode.live);
    return TrackerOutput(
      sharedFix: shareFix ? fix : null,
      zoneId: currentZoneId,
      shareZone: sosActive || shareTransitions,
      events: events,
      spec: currentSpec(now, batteryPct: batteryPct, charging: charging),
    );
  }

  /// SOS always shares exact location, whatever the privacy mode or pause.
  AlertEvent startSos(DateTime now) {
    _sosSince = now;
    final f = _last;
    return AlertEvent(
      id: newId(),
      childId: child.id,
      type: AlertType.sos,
      at: now,
      message: '${child.name} pressed SOS'
          '${f == null ? '' : ' (±${f.accuracyM.round()} m)'}',
      lat: f?.lat,
      lng: f?.lng,
    );
  }

  AlertEvent cancelSos(DateTime now) {
    _sosSince = null;
    return AlertEvent(
      id: newId(),
      childId: child.id,
      type: AlertType.sosCancelled,
      at: now,
      message: '${child.name} is safe: SOS cancelled',
    );
  }

  /// A check-in is a deliberate share, so it carries location in every mode.
  AlertEvent checkIn(String text, DateTime now) {
    final f = _last;
    final zone = zoneById(currentZoneId);
    return AlertEvent(
      id: newId(),
      childId: child.id,
      type: AlertType.checkIn,
      at: now,
      message: '${child.name}: $text${zone == null ? '' : ' (at ${zone.name})'}',
      lat: f?.lat,
      lng: f?.lng,
      zoneId: zone?.id,
    );
  }

  /// Pausing replaces "uninstall the app": parents are told immediately,
  /// with the reason and when sharing comes back.
  AlertEvent pause(Duration length, String reason, DateTime now) {
    final until = now.add(length);
    child = child.copyWith(pausedUntil: until, pauseReason: reason);
    final hh = until.hour.toString().padLeft(2, '0');
    final mm = until.minute.toString().padLeft(2, '0');
    return AlertEvent(
      id: newId(),
      childId: child.id,
      type: AlertType.sharingPaused,
      at: now,
      message: '${child.name} paused sharing until $hh:$mm'
          '${reason.isEmpty ? '' : ': "$reason"'}',
    );
  }

  AlertEvent resume(DateTime now) {
    child = child.copyWith(clearPause: true);
    return AlertEvent(
      id: newId(),
      childId: child.id,
      type: AlertType.sharingResumed,
      at: now,
      message: '${child.name} is sharing again',
    );
  }
}
