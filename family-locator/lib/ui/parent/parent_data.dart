import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../data/backend.dart';
import '../../core/ids.dart';

/// Live family data for the parent screens, shared by all tabs.
class ParentData extends ChangeNotifier {
  ParentData(this.backend, this.session) {
    final f = session.familyId;
    _subs
      ..add(backend.watchChildren(f).listen((v) {
        children = v..sort((a, b) => a.name.compareTo(b.name));
        notifyListeners();
      }))
      ..add(backend.watchZones(f).listen((v) {
        zones = {for (final z in v) z.id: z};
        notifyListeners();
      }))
      ..add(backend.watchAlerts(f).listen((v) {
        alerts = v;
        notifyListeners();
      }))
      ..add(backend.watchSettings(f).listen((v) {
        settings = v;
        notifyListeners();
      }))
      ..add(backend.watchTasks(f).listen((v) {
        tasks = v;
        notifyListeners();
      }));
    // Keeps "updated 3 min ago" labels honest.
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) => notifyListeners());
  }

  final FamilyBackend backend;
  final Session session;
  final _subs = <StreamSubscription<Object?>>[];
  late final Timer _ticker;

  List<ChildProfile> children = [];
  Map<String, Zone> zones = {};
  List<AlertEvent> alerts = [];
  FamilySettings settings = const FamilySettings();
  List<FamilyTask> tasks = [];

  String get familyId => session.familyId;

  ChildProfile? childById(String id) {
    for (final c in children) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> sendCommand(String childId, CommandType type) => backend.sendCommand(
        familyId,
        Command(id: newId(), childId: childId, type: type, at: DateTime.now(), from: session.displayName),
      );

  Future<void> recordView(String childId) => backend.recordView(
        familyId,
        ViewRecord(viewer: session.displayName, at: DateTime.now(), childId: childId),
      );

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _ticker.cancel();
    super.dispose();
  }
}
