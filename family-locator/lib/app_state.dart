import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core/alert_policy.dart';
import 'core/ids.dart';
import 'core/models.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'services/child_controller.dart';
import 'services/platform_services.dart';

/// Who is signed in, and the long-lived services for that role.
class AppState extends ChangeNotifier {
  AppState(this.backend, {this.childControllerFactory});

  final FamilyBackend backend;

  /// Builds the controller for a real child device. Overridable in tests.
  final ChildController Function(FamilyBackend, Session)? childControllerFactory;

  Session? session;
  ChildController? child;
  ParentAlertWatcher? _watcher;
  bool loading = true;

  /// Demo: the parent session to return to after peeking at the child phone.
  Session? _demoParent;

  bool get isDemo => backend is DemoBackend;
  bool get viewingDemoChild => _demoParent != null;

  Future<void> init() async {
    try {
      final s = await backend.restoreSession();
      if (s != null) await _enter(s);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> createFamily(String parentName) async => _enter(await backend.createFamily(parentName: parentName));

  Future<void> join(String code, String name, Role role) async =>
      _enter(await backend.joinWithCode(code: code, name: name, role: role));

  Future<void> _enter(Session s) async {
    session = s;
    if (s.role == Role.child) {
      final c = childControllerFactory?.call(backend, s) ??
          ChildController(
            backend: backend,
            session: s,
            source: GeolocatorFixSource(),
            status: PhoneStatus(),
            alarm: LoudAlarm(),
            newId: newId,
          );
      child = c;
      await c.start();
    } else {
      _watcher = ParentAlertWatcher(backend, s)..start();
    }
    notifyListeners();
  }

  /// Demo only: see what the simulated child sees on their phone.
  void openDemoChildPhone() {
    final demo = backend as DemoBackend;
    final c = demo.demoChild;
    if (c == null || session == null) return;
    _demoParent = session;
    session = demo.switchToDemoChild();
    child = c;
    notifyListeners();
  }

  void backToParent() {
    final parent = _demoParent;
    if (parent == null) return;
    (backend as DemoBackend).switchToParent(parent);
    session = parent;
    child = null; // The simulated phone keeps running in the background.
    _demoParent = null;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final s = session;
    if (s == null) return;
    _watcher?.stop();
    _watcher = null;
    await child?.stop();
    child = null;
    _demoParent = null;
    await backend.deleteAccount(s);
    session = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    _watcher?.stop();
    _watcher = null;
    if (!viewingDemoChild) await child?.stop();
    child = null;
    _demoParent = null;
    await backend.signOut();
    session = null;
    notifyListeners();
  }
}

/// Shows local notifications for new alerts on the parent's phone,
/// applying zone schedules and quiet hours, and sends one summary when
/// quiet hours end.
class ParentAlertWatcher {
  ParentAlertWatcher(this.backend, this.session);

  final FamilyBackend backend;
  final Session session;
  final _seen = <String>{};
  final _held = <AlertEvent>[];
  var _zones = <String, Zone>{};
  var _settings = const FamilySettings();
  bool _primed = false;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _digestTimer;

  void start() {
    final f = session.familyId;
    _subs
      ..add(backend.watchZones(f).listen((z) => _zones = {for (final x in z) x.id: x}))
      ..add(backend.watchSettings(f).listen((s) => _settings = s))
      ..add(backend.watchAlerts(f, limit: 30).listen(_onAlerts));
    _digestTimer = Timer.periodic(const Duration(minutes: 1), (_) => _flushDigest());
  }

  void _onAlerts(List<AlertEvent> alerts) {
    if (!_primed) {
      // Existing history isn't news.
      _seen.addAll(alerts.map((a) => a.id));
      _primed = true;
      return;
    }
    for (final a in alerts.reversed) {
      if (!_seen.add(a.id)) continue;
      switch (decideDelivery(a, _settings, zone: _zones[a.zoneId])) {
        case Delivery.now:
          Notifier.instance.show(_title(a), a.message, urgent: a.urgent);
        case Delivery.digest:
          _held.add(a);
        case Delivery.feedOnly:
          break;
      }
    }
  }

  void _flushDigest() {
    if (_held.isEmpty) return;
    final quiet = _settings.quietHours;
    if (quiet != null && quiet.contains(DateTime.now())) return;
    Notifier.instance.show('While you were in quiet hours', digestSummary(_held));
    _held.clear();
  }

  static String _title(AlertEvent a) => switch (a.type) {
        AlertType.sos => '🆘 SOS',
        AlertType.trackingOff || AlertType.permissionLost => '⚠️ Location stopped',
        AlertType.lowBattery => '🔋 Low battery',
        AlertType.arrived || AlertType.left => '📍 Places',
        AlertType.checkIn => '✅ Check-in',
        _ => 'Family',
      };

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _digestTimer?.cancel();
  }
}
