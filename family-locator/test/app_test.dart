import 'dart:async';

import 'package:family_locator/app_state.dart';
import 'package:family_locator/core/geo.dart';
import 'package:family_locator/core/ids.dart';
import 'package:family_locator/core/models.dart';
import 'package:family_locator/data/demo_backend.dart';
import 'package:family_locator/main.dart';
import 'package:family_locator/services/child_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakeSource implements FixSource {
  final ctrl = StreamController<LocationFix>.broadcast();
  LocationFix? last;
  LocationRequestSpec? spec;

  void emit(LocationFix f) {
    last = f;
    ctrl.add(f);
  }

  @override
  Stream<LocationFix> get fixes => ctrl.stream;
  @override
  Future<void> apply(LocationRequestSpec s) async => spec = s;
  @override
  Future<void> start(LocationRequestSpec s) async => spec = s;
  @override
  Future<void> stop() async {}
  @override
  Future<LocationFix?> current() async => last;
}

class FakeStatus implements DeviceStatus {
  DeviceHealth health = DeviceHealth(lastSeen: DateTime.now(), batteryPct: 80);
  @override
  Future<DeviceHealth> read() async => health;
}

class FakeAlarm implements Alarm {
  bool ringing = false;
  @override
  Future<void> start() async => ringing = true;
  @override
  Future<void> stop() async => ringing = false;
}

void main() {
  testWidgets('parent sets up a demo family and sees kids and alerts', (tester) async {
    final app = AppState(DemoBackend(simulate: false));
    await app.init();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: const FamilyLocatorApp()));
    await tester.pump();

    await tester.tap(find.text("I'm a parent: set up my family"));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.tap(find.text('Create family'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Mia ·'), findsOneWidget);
    expect(find.textContaining('Leo · At Library'), findsOneWidget);
    expect(find.text('Places only'), findsOneWidget);
    expect(find.textContaining('Allow all the time'), findsOneWidget);

    await tester.tap(find.text('Alerts'));
    await tester.pump();
    expect(find.text('Alerts'), findsWidgets);

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    expect(find.text('Reading: 20 minutes'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);

    await app.signOut();
    await tester.pumpWidget(const SizedBox());
  });

  group('ChildController with the demo backend', () {
    late DemoBackend backend;
    late FakeSource source;
    late FakeAlarm alarm;
    late ChildController c;
    late Session parent;
    late String childId;

    setUp(() async {
      backend = DemoBackend(simulate: false);
      parent = await backend.createFamily(parentName: 'Sam');
      final child = await backend.joinWithCode(code: 'ABCDEF', name: 'Ana', role: Role.child);
      childId = child.memberId;
      await backend.saveZone(
          parent.familyId, const Zone(id: 'home', name: 'Home', lat: 51.5390, lng: -0.1030, radiusM: 120));
      source = FakeSource();
      alarm = FakeAlarm();
      c = ChildController(
        backend: backend,
        session: child,
        source: source,
        status: FakeStatus(),
        alarm: alarm,
        newId: newId,
      );
      await c.start();
    });

    tearDown(() => c.stop());

    LocationFix at(double lat, double lng) =>
        LocationFix(lat: lat, lng: lng, accuracyM: 5, at: DateTime.now(), speedMps: 1.4);

    Future<List<AlertEvent>> alerts() => backend.watchAlerts(parent.familyId).first;
    Future<ChildProfile?> profile() => backend.watchChild(parent.familyId, childId).first;

    test('arrival is published with location', () async {
      source.emit(at(51.5600, -0.1200));
      await pumpEventQueue();
      source.emit(at(51.5390, -0.1030));
      await pumpEventQueue();
      expect((await alerts()).first.message, 'Ana arrived at Home');
      expect((await profile())!.currentZoneId, 'home');
      expect((await profile())!.lastFix, isNotNull);
    });

    test('pause notifies parents, hides location, and SOS still gets through', () async {
      await c.pause(const Duration(minutes: 30), 'party');
      expect((await alerts()).first.type, AlertType.sharingPaused);

      source.emit(at(51.5600, -0.1200));
      await pumpEventQueue();
      expect((await profile())!.lastFix, isNull);

      await c.sos();
      final p = await profile();
      expect(p!.sosActiveSince, isNotNull);
      expect(p.lastFix, isNotNull);
      expect((await alerts()).first.type, AlertType.sos);
      expect(source.spec!.label, 'SOS: continuous');
    });

    test('ring plays until acknowledged, and the parent hears back', () async {
      await backend.sendCommand(
        parent.familyId,
        Command(id: 'r1', childId: childId, type: CommandType.ring, at: DateTime.now(), from: 'Sam'),
      );
      await pumpEventQueue();
      expect(alarm.ringing, isTrue);
      expect(c.ringing, isNotNull);
      await c.acknowledgeRing();
      expect(alarm.ringing, isFalse);
      expect((await alerts()).first.message, 'Ana heard the signal from Sam');
      expect(await backend.watchCommands(parent.familyId, childId).first, isEmpty);
    });

    test('parent switching to places-only stops coordinates', () async {
      final p = (await profile())!;
      await backend.updateChild(parent.familyId, p.copyWith(privacyMode: PrivacyMode.placesOnly));
      await pumpEventQueue();
      source.emit(at(51.5390, -0.1030));
      await pumpEventQueue();
      final after = (await profile())!;
      expect(after.lastFix, isNull);
      expect(after.currentZoneId, 'home');
    });

    test('losing background permission alerts parents', () async {
      (c.status as FakeStatus).health =
          DeviceHealth(lastSeen: DateTime.now(), backgroundPermission: false, batteryPct: 80);
      await c.refreshHealth();
      expect((await alerts()).first.type, AlertType.permissionLost);
    });
  });
}
