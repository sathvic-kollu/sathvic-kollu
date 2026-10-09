import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/child_tracker.dart';
import '../core/geo.dart';
import '../core/models.dart';
import '../data/backend.dart';

/// Where location samples come from: the real GPS, or the demo simulator.
abstract class FixSource {
  Stream<LocationFix> get fixes;

  /// Re-tunes accuracy/interval; the battery policy calls this as the
  /// child starts moving, rests, or a parent opens live view.
  Future<void> apply(LocationRequestSpec spec);
  Future<void> start(LocationRequestSpec spec);
  Future<void> stop();

  /// One fresh fix, as fast as possible (SOS, refresh).
  Future<LocationFix?> current();
}

abstract class DeviceStatus {
  Future<DeviceHealth> read();
}

/// Loud signal that plays even when the phone is on silent.
abstract class Alarm {
  Future<void> start();
  Future<void> stop();
}

/// Runs everything on the child's phone: tracking, health reports, SOS,
/// check-ins, pause, and replies to parent commands.
class ChildController extends ChangeNotifier {
  ChildController({
    required this.backend,
    required this.session,
    required this.source,
    required this.status,
    required this.alarm,
    required String Function() newId,
    this.autoAckRingAfter,
    DateTime Function()? clock,
  })  : _now = clock ?? DateTime.now,
        tracker = ChildTracker(
          child: ChildProfile(id: session.memberId, name: session.displayName),
          newId: newId,
        );

  final FamilyBackend backend;
  final Session session;
  final FixSource source;
  final DeviceStatus status;
  final Alarm alarm;

  /// Demo only: the simulated child "hears" a ring after this long.
  final Duration? autoAckRingAfter;
  final DateTime Function() _now;
  final ChildTracker tracker;

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _healthTimer;
  Timer? _resumeTimer;
  LocationRequestSpec? _spec;
  DeviceHealth? _lastHealth;
  FamilySettings _settings = const FamilySettings();
  bool _started = false;

  Command? ringing;
  String? lastError;

  String get _f => session.familyId;
  ChildProfile get child => tracker.child;
  FamilySettings get settings => _settings;
  LocationRequestSpec? get spec => _spec;
  DeviceHealth? get health => _lastHealth;
  bool get sosActive => tracker.sosActive;
  bool get running => _started;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subs
      ..add(backend.watchChild(_f, session.memberId).listen((c) {
        if (c == null) return;
        // The server copy wins for parent-controlled fields.
        tracker.child = tracker.child.copyWith(
          name: c.name,
          emoji: c.emoji,
          privacyMode: c.privacyMode,
          points: c.points,
          pausedUntil: c.pausedUntil,
          pauseReason: c.pauseReason,
          clearPause: c.pausedUntil == null,
        );
        _scheduleResume();
        notifyListeners();
      }))
      ..add(backend.watchZones(_f).listen((z) => tracker.zones = z))
      ..add(backend.watchSettings(_f).listen((s) {
        _settings = s;
        tracker.settings = s;
        notifyListeners();
      }))
      ..add(backend.watchCommands(_f, session.memberId).listen(_onCommands))
      ..add(source.fixes.listen(_onFix, onError: (Object e) {
        lastError = '$e';
        notifyListeners();
      }));

    _spec = tracker.currentSpec(_now());
    await source.start(_spec!);
    await _reportHealth();
    _healthTimer = Timer.periodic(const Duration(minutes: 5), (_) => _reportHealth());
    notifyListeners();
  }

  Future<void> _onFix(LocationFix raw) async {
    final h = _lastHealth;
    final out = tracker.onFix(raw, batteryPct: h?.batteryPct, charging: h?.charging ?? false);
    try {
      if (out.sharedFix != null || out.shareZone) {
        await backend.publishPresence(_f, child.id,
            fix: out.sharedFix, zoneId: out.zoneId, shareZone: out.shareZone);
      }
      for (final e in out.events) {
        await backend.pushEvent(_f, e);
      }
      lastError = null;
    } catch (e) {
      lastError = 'Could not sync: $e';
    }
    if (out.spec != _spec) {
      _spec = out.spec;
      await source.apply(out.spec);
    }
    notifyListeners();
  }

  Future<void> _reportHealth() async {
    final h = await status.read();
    final before = _lastHealth;
    // Starts GPS if it couldn't start earlier (permission granted since).
    await source.apply(_spec ?? tracker.currentSpec(_now()));
    _lastHealth = h;
    await backend.updateHealth(_f, child.id, h);
    final wasOk = before == null || (before.locationServiceOn && before.backgroundPermission);
    final nowOk = h.locationServiceOn && h.backgroundPermission;
    if (wasOk && !nowOk) {
      await backend.pushEvent(
        _f,
        AlertEvent(
          id: tracker.newId(),
          childId: child.id,
          type: AlertType.permissionLost,
          at: _now(),
          message: "${child.name}'s location stopped: ${h.issues.first}",
        ),
      );
    }
    notifyListeners();
  }

  Future<void> refreshHealth() => _reportHealth();

  void _onCommands(List<Command> commands) {
    for (final c in commands) {
      switch (c.type) {
        case CommandType.ring:
          if (ringing?.id == c.id) continue;
          ringing = c;
          alarm.start();
          if (autoAckRingAfter != null) {
            Timer(autoAckRingAfter!, () => acknowledgeRing());
          }
        case CommandType.liveMode:
          tracker.startLiveMode(_now());
          backend.ackCommand(_f, c.id);
          _applyAndRefresh();
        case CommandType.refresh:
          backend.ackCommand(_f, c.id);
          _applyAndRefresh();
      }
    }
    notifyListeners();
  }

  Future<void> _applyAndRefresh() async {
    _spec = tracker.currentSpec(_now(),
        batteryPct: _lastHealth?.batteryPct, charging: _lastHealth?.charging ?? false);
    await source.apply(_spec!);
    final f = await source.current();
    if (f != null) await _onFix(f);
  }

  Future<void> acknowledgeRing() async {
    final c = ringing;
    if (c == null) return;
    ringing = null;
    await alarm.stop();
    await backend.ackCommand(_f, c.id);
    await backend.pushEvent(
      _f,
      AlertEvent(
        id: tracker.newId(),
        childId: child.id,
        type: AlertType.signalAcknowledged,
        at: _now(),
        message: '${child.name} heard the signal from ${c.from}',
      ),
    );
    notifyListeners();
  }

  Future<void> sos() async {
    final f = await source.current();
    if (f != null) tracker.onFix(f);
    final event = tracker.startSos(_now());
    _spec = tracker.currentSpec(_now());
    await source.apply(_spec!);
    await backend.updateChild(_f, child.copyWith(sosActiveSince: event.at));
    if (tracker.lastFix != null) {
      await backend.publishPresence(_f, child.id,
          fix: tracker.lastFix, zoneId: tracker.currentZoneId, shareZone: true);
    }
    await backend.pushEvent(_f, event);
    notifyListeners();
  }

  Future<void> cancelSos() async {
    final event = tracker.cancelSos(_now());
    await backend.updateChild(_f, child.copyWith(clearSos: true));
    await backend.pushEvent(_f, event);
    _spec = tracker.currentSpec(_now());
    await source.apply(_spec!);
    notifyListeners();
  }

  Future<void> checkIn(String text) async {
    final f = await source.current();
    if (f != null) tracker.onFix(f);
    await backend.pushEvent(_f, tracker.checkIn(text, _now()));
    notifyListeners();
  }

  Future<void> pause(Duration length, String reason) async {
    final max = Duration(minutes: _settings.maxPauseMinutes);
    if (max == Duration.zero) throw BackendException('Your family has turned pausing off.');
    final event = tracker.pause(length > max ? max : length, reason, _now());
    await backend.updateChild(_f, tracker.child);
    await backend.pushEvent(_f, event);
    _scheduleResume();
    notifyListeners();
  }

  Future<void> resume() async {
    _resumeTimer?.cancel();
    final event = tracker.resume(_now());
    await backend.updateChild(_f, tracker.child);
    await backend.pushEvent(_f, event);
    notifyListeners();
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    final until = child.pausedUntil;
    if (until == null) return;
    final wait = until.difference(_now());
    if (wait.isNegative) return;
    _resumeTimer = Timer(wait, () {
      if (child.pausedUntil == until) resume();
    });
  }

  Future<void> markTaskDone(FamilyTask task) async {
    await backend.saveTask(_f, task.copyWith(status: TaskStatus.done));
    await backend.pushEvent(
      _f,
      AlertEvent(
        id: tracker.newId(),
        childId: child.id,
        type: AlertType.taskDone,
        at: _now(),
        message: '${child.name} finished "${task.title}"',
      ),
    );
  }

  Future<void> stop() async {
    _started = false;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _healthTimer?.cancel();
    _resumeTimer?.cancel();
    await source.stop();
    await alarm.stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
