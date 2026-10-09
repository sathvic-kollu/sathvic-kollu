import 'dart:async';
import 'dart:math' as math;

import '../core/geo.dart';
import '../core/ids.dart';
import '../core/models.dart';
import '../services/child_controller.dart';
import 'backend.dart';

/// A value plus a stream that replays the latest value to new listeners.
class _Live<T> {
  _Live(this._value);

  T _value;
  final _ctrl = StreamController<T>.broadcast();

  T get value => _value;
  set value(T v) {
    _value = v;
    _ctrl.add(v);
  }

  Stream<T> get stream => Stream<T>.multi((c) {
        c.add(_value);
        final sub = _ctrl.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });
}

/// In-memory backend for trying the app with zero setup. Creating a family
/// seeds two children, three places and a morning of history, and starts a
/// simulated phone for "Mia" that walks between home, school and football
/// through the real child-side code ([ChildController]).
class DemoBackend implements FamilyBackend {
  DemoBackend({this.simulate = true, this.tick = const Duration(seconds: 2)});

  final bool simulate;
  final Duration tick;

  @override
  String get name => 'Demo';

  Session? _session;
  String _familyId = 'demo-family';
  final _children = _Live<Map<String, ChildProfile>>({});
  final _zones = _Live<Map<String, Zone>>({});
  final _settings = _Live<FamilySettings>(const FamilySettings());
  final _alerts = _Live<List<AlertEvent>>([]);
  final _history = <String, List<LocationFix>>{};
  final _historyLive = _Live<int>(0);
  final _commands = _Live<Map<String, Command>>({});
  final _views = _Live<List<ViewRecord>>([]);
  final _tasks = _Live<Map<String, FamilyTask>>({});

  /// The simulated child's phone, exposed so the "open Mia's phone" demo
  /// switch shows the very controller the parent is watching.
  ChildController? demoChild;

  static const _home = (51.5390, -0.1030);
  static const _school = (51.5455, -0.0925);
  static const _football = (51.5480, -0.1050);
  static const _library = (51.5330, -0.1060);

  @override
  Future<Session?> restoreSession() async => _session;

  @override
  Future<Session> createFamily({required String parentName}) async {
    _familyId = newId();
    _session = Session(
        familyId: _familyId, memberId: newId(), role: Role.parent, displayName: parentName);
    _seed();
    if (simulate) await _startSimulatedChild();
    return _session!;
  }

  @override
  Future<String> createInviteCode(String familyId) async {
    final r = math.Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  Future<Session> joinWithCode({
    required String code,
    required String name,
    required Role role,
  }) async {
    if (code.trim().length < 4) throw BackendException('That code is too short.');
    if (_children.value.isEmpty) _seed();
    final id = newId();
    _session = Session(familyId: _familyId, memberId: id, role: role, displayName: name);
    if (role == Role.child) {
      _children.value = {..._children.value, id: ChildProfile(id: id, name: name, emoji: '🙂')};
    }
    return _session!;
  }

  /// Demo-only: look at the family from the simulated child's phone.
  Session? switchToDemoChild() {
    final c = demoChild;
    if (c == null) return null;
    return _session = c.session;
  }

  Session switchToParent(Session parent) => _session = parent;

  @override
  Future<void> deleteAccount(Session session) => signOut();

  @override
  Future<void> signOut() async {
    await demoChild?.stop();
    demoChild = null;
    _session = null;
    _children.value = {};
    _zones.value = {};
    _alerts.value = [];
    _history.clear();
    _commands.value = {};
    _views.value = [];
    _tasks.value = {};
  }

  // ---------------------------------------------------------------------------

  @override
  Stream<List<ChildProfile>> watchChildren(String familyId) =>
      _children.stream.map((m) => m.values.toList());

  @override
  Stream<ChildProfile?> watchChild(String familyId, String childId) =>
      _children.stream.map((m) => m[childId]);

  @override
  Future<void> updateChild(String familyId, ChildProfile child) async {
    final existing = _children.value[child.id];
    // Presence and health are owned by publishPresence/updateHealth.
    final merged = existing == null
        ? child
        : ChildProfile(
            id: child.id,
            name: child.name,
            emoji: child.emoji,
            privacyMode: child.privacyMode,
            lastFix: existing.lastFix,
            currentZoneId: existing.currentZoneId,
            health: existing.health,
            pausedUntil: child.pausedUntil,
            pauseReason: child.pauseReason,
            points: child.points,
            sosActiveSince: child.sosActiveSince,
          );
    _children.value = {..._children.value, child.id: merged};
  }

  @override
  Stream<List<Zone>> watchZones(String familyId) => _zones.stream.map((m) => m.values.toList());

  @override
  Future<void> saveZone(String familyId, Zone zone) async =>
      _zones.value = {..._zones.value, zone.id: zone};

  @override
  Future<void> deleteZone(String familyId, String zoneId) async =>
      _zones.value = {..._zones.value}..remove(zoneId);

  @override
  Stream<FamilySettings> watchSettings(String familyId) => _settings.stream;

  @override
  Future<void> saveSettings(String familyId, FamilySettings settings) async =>
      _settings.value = settings;

  @override
  Stream<List<AlertEvent>> watchAlerts(String familyId, {int limit = 100}) =>
      _alerts.stream.map((l) => l.take(limit).toList());

  @override
  Future<void> pushEvent(String familyId, AlertEvent event) async =>
      _alerts.value = [event, ..._alerts.value];

  @override
  Future<void> publishPresence(
    String familyId,
    String childId, {
    LocationFix? fix,
    String? zoneId,
    bool shareZone = false,
  }) async {
    final c = _children.value[childId];
    if (c == null) return;
    var next = c;
    if (fix != null) {
      next = next.copyWith(lastFix: fix);
      (_history[childId] ??= []).add(fix);
      _historyLive.value++;
    }
    if (shareZone) next = next.copyWith(currentZoneId: zoneId, clearZone: zoneId == null);
    _children.value = {..._children.value, childId: next};
  }

  @override
  Future<void> updateHealth(String familyId, String childId, DeviceHealth health) async {
    final c = _children.value[childId];
    if (c == null) return;
    _children.value = {..._children.value, childId: c.copyWith(health: health)};
  }

  @override
  Stream<List<LocationFix>> watchHistory(String familyId, String childId, DateTime day) =>
      _historyLive.stream.map((_) => (_history[childId] ?? const <LocationFix>[])
          .where((f) => f.at.year == day.year && f.at.month == day.month && f.at.day == day.day)
          .toList());

  @override
  Future<void> sendCommand(String familyId, Command command) async =>
      _commands.value = {..._commands.value, command.id: command};

  @override
  Stream<List<Command>> watchCommands(String familyId, String childId) => _commands.stream
      .map((m) => m.values.where((c) => c.childId == childId).toList());

  @override
  Future<void> ackCommand(String familyId, String commandId) async =>
      _commands.value = {..._commands.value}..remove(commandId);

  @override
  Future<void> recordView(String familyId, ViewRecord view) async =>
      _views.value = [view, ..._views.value].take(50).toList();

  @override
  Stream<List<ViewRecord>> watchViews(String familyId, String childId) =>
      _views.stream.map((l) => l.where((v) => v.childId == childId).toList());

  @override
  Stream<List<FamilyTask>> watchTasks(String familyId) =>
      _tasks.stream.map((m) => m.values.toList());

  @override
  Future<void> saveTask(String familyId, FamilyTask task) async =>
      _tasks.value = {..._tasks.value, task.id: task};

  @override
  Future<void> deleteTask(String familyId, String taskId) async =>
      _tasks.value = {..._tasks.value}..remove(taskId);

  @override
  Future<void> approveTask(String familyId, FamilyTask task) async {
    await saveTask(familyId, task.copyWith(status: TaskStatus.approved));
    final c = _children.value[task.childId];
    if (c != null) {
      _children.value = {..._children.value, c.id: c.copyWith(points: c.points + task.points)};
    }
  }

  // Seed data ---------------------------------------------------------------

  static const miaId = 'demo-mia';
  static const leoId = 'demo-leo';

  void _seed() {
    final now = DateTime.now();
    const weekdays = {1, 2, 3, 4, 5};
    _zones.value = {
      'home': Zone(id: 'home', name: 'Home', emoji: '🏠', lat: _home.$1, lng: _home.$2, radiusM: 120),
      'school': Zone(
        id: 'school',
        name: 'School',
        emoji: '🏫',
        lat: _school.$1,
        lng: _school.$2,
        radiusM: 180,
        alertWindow: const TimeWindow(weekdays: weekdays, startMinute: 7 * 60, endMinute: 17 * 60),
      ),
      'football': Zone(
          id: 'football', name: 'Football', emoji: '⚽', lat: _football.$1, lng: _football.$2, radiusM: 150),
      'library': Zone(
          id: 'library', name: 'Library', emoji: '📚', lat: _library.$1, lng: _library.$2, radiusM: 100),
    };
    _settings.value = const FamilySettings(
      quietHours: TimeWindow(weekdays: {1, 2, 3, 4, 5, 6, 7}, startMinute: 22 * 60, endMinute: 7 * 60),
    );

    _children.value = {
      miaId: ChildProfile(id: miaId, name: 'Mia', emoji: '👧', points: 40),
      leoId: ChildProfile(
        id: leoId,
        name: 'Leo',
        emoji: '🧑',
        privacyMode: PrivacyMode.placesOnly,
        currentZoneId: 'library',
        points: 120,
        health: DeviceHealth(
          lastSeen: now.subtract(const Duration(minutes: 7)),
          batteryPct: 64,
          backgroundPermission: false,
          appVersion: '1.0.0',
        ),
      ),
    };

    // A morning for Mia: home → walk → school → walk → home.
    final start = now.subtract(const Duration(hours: 6));
    final fixes = <LocationFix>[];
    void stay((double, double) p, DateTime from, int minutes) {
      for (var m = 0; m <= minutes; m += 10) {
        fixes.add(LocationFix(
            lat: p.$1, lng: p.$2, accuracyM: 12, at: from.add(Duration(minutes: m)), movement: MovementType.stationary));
      }
    }

    void walk((double, double) a, (double, double) b, DateTime from, int minutes) {
      for (var m = 1; m < minutes; m += 2) {
        final t = m / minutes;
        fixes.add(LocationFix(
          lat: a.$1 + (b.$1 - a.$1) * t,
          lng: a.$2 + (b.$2 - a.$2) * t,
          accuracyM: 8,
          speedMps: 1.4,
          at: from.add(Duration(minutes: m)),
          movement: MovementType.walking,
        ));
      }
    }

    stay(_home, start, 40);
    walk(_home, _school, start.add(const Duration(minutes: 40)), 16);
    stay(_school, start.add(const Duration(minutes: 56)), 230);
    walk(_school, _home, start.add(const Duration(minutes: 290)), 16);
    stay(_home, start.add(const Duration(minutes: 306)), 40);
    _history[miaId] = fixes.where((f) => f.at.day == now.day).toList();

    AlertEvent ev(AlertType type, int minutesAfterStart, String msg, {String? childId, String? zoneId}) =>
        AlertEvent(
          id: newId(),
          childId: childId ?? miaId,
          type: type,
          at: start.add(Duration(minutes: minutesAfterStart)),
          message: msg,
          zoneId: zoneId,
        );
    _alerts.value = [
      ev(AlertType.arrived, 306, 'Mia arrived at Home', zoneId: 'home'),
      ev(AlertType.checkIn, 300, 'Mia: On my way home'),
      ev(AlertType.left, 290, 'Mia left School', zoneId: 'school'),
      ev(AlertType.arrived, 200, 'Leo arrived at Library', childId: leoId, zoneId: 'library'),
      ev(AlertType.arrived, 56, 'Mia arrived at School', zoneId: 'school'),
      ev(AlertType.left, 40, 'Mia left Home', zoneId: 'home'),
    ].where((e) => e.at.day == now.day).toList();

    _tasks.value = {
      't1': const FamilyTask(id: 't1', childId: miaId, title: 'Pack football kit', points: 10),
      't2': const FamilyTask(
          id: 't2', childId: miaId, title: 'Reading: 20 minutes', points: 15, status: TaskStatus.done),
      't3': const FamilyTask(id: 't3', childId: leoId, title: 'Take the bins out', points: 10),
    };
  }

  Future<void> _startSimulatedChild() async {
    await demoChild?.stop();
    final session =
        Session(familyId: _familyId, memberId: miaId, role: Role.child, displayName: 'Mia');
    demoChild = ChildController(
      backend: this,
      session: session,
      source: SimulatedRoute(
        tick: tick,
        stops: const [_home, _school, _football, _home],
      ),
      status: _DemoStatus(),
      alarm: _SilentAlarm(),
      newId: newId,
      autoAckRingAfter: const Duration(seconds: 4),
    );
    await demoChild!.start();
  }
}

/// Walks between stops at a brisk demo pace, pausing at each one.
class SimulatedRoute implements FixSource {
  SimulatedRoute({
    required this.stops,
    this.tick = const Duration(seconds: 2),
    this.metresPerTick = 25,
    this.dwellTicks = 20,
  });

  final List<(double, double)> stops;
  final Duration tick;
  final double metresPerTick;
  final int dwellTicks;

  final _ctrl = StreamController<LocationFix>.broadcast();
  Timer? _timer;
  int _leg = 0;
  double _progress = 0; // metres along the current leg
  late int _dwell = dwellTicks; // start parked at the first stop
  LocationFix? _last;

  @override
  Stream<LocationFix> get fixes => _ctrl.stream;

  @override
  Future<void> start(LocationRequestSpec spec) async {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _step());
    _step();
  }

  @override
  Future<void> apply(LocationRequestSpec spec) async {}

  @override
  Future<void> stop() async => _timer?.cancel();

  @override
  Future<LocationFix?> current() async => _last;

  void _step() {
    final a = stops[_leg % stops.length];
    final b = stops[(_leg + 1) % stops.length];
    final legLength = distanceM(a.$1, a.$2, b.$1, b.$2);
    double lat, lng;
    double speed;
    if (_dwell > 0) {
      _dwell--;
      lat = a.$1;
      lng = a.$2;
      speed = 0;
      if (_dwell == 0) _progress = 0;
    } else {
      _progress += metresPerTick;
      if (_progress >= legLength) {
        _leg++;
        _dwell = dwellTicks;
        lat = b.$1;
        lng = b.$2;
        speed = 0;
      } else {
        final t = _progress / legLength;
        lat = a.$1 + (b.$1 - a.$1) * t;
        lng = a.$2 + (b.$2 - a.$2) * t;
        speed = 1.4;
      }
    }
    final jitter = (math.Random().nextDouble() - 0.5) * 0.00004;
    _last = LocationFix(
      lat: lat + jitter,
      lng: lng + jitter,
      accuracyM: 6 + math.Random().nextDouble() * 6,
      speedMps: speed,
      at: DateTime.now(),
    );
    _ctrl.add(_last!);
  }
}

class _DemoStatus implements DeviceStatus {
  int _battery = 78;

  @override
  Future<DeviceHealth> read() async {
    _battery = math.max(9, _battery - 1);
    return DeviceHealth(lastSeen: DateTime.now(), batteryPct: _battery, appVersion: '1.0.0');
  }
}

class _SilentAlarm implements Alarm {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
