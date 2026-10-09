import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:family_locator/core/models.dart';
import 'package:family_locator/data/backend.dart';
import 'package:family_locator/data/firestore_backend.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each "phone" gets its own auth but shares the one fake database.
FirestoreBackend phone(FakeFirebaseFirestore db, String uid) => FirestoreBackend(
      db: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: uid, isAnonymous: true)),
      timeZone: () async => 'Europe/London',
      registerPush: false,
    );

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreBackend mum;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    mum = phone(db, 'mum');
  });

  Future<(Session, Session)> familyWithChild() async {
    final parent = await mum.createFamily(parentName: 'Mum');
    final code = await mum.createInviteCode(parent.familyId, role: Role.child);
    final child = await phone(db, 'mia').joinWithCode(code: code, name: 'Mia', role: Role.child);
    return (parent, child);
  }

  test('creating a family stores the parent and the family time zone', () async {
    final s = await mum.createFamily(parentName: 'Mum');
    expect(s.role, Role.parent);
    final family = (await db.doc('families/${s.familyId}').get()).data()!;
    expect(family['tz'], 'Europe/London');
    expect(family['createdBy'], 'mum');
    expect((await db.doc('families/${s.familyId}/members/mum').get()).data()!['role'], 'parent');
  });

  test('a child joins with a code and appears for the parent', () async {
    final (parent, child) = await familyWithChild();
    expect(child.familyId, parent.familyId);
    final kids = await mum.watchChildren(parent.familyId).first;
    expect(kids.single.name, 'Mia');
    expect(kids.single.id, 'mia');
  });

  test('codes are bound to a role, normalised, and expire', () async {
    final parent = await mum.createFamily(parentName: 'Mum');
    final code = await mum.createInviteCode(parent.familyId, role: Role.child);
    final dad = phone(db, 'dad');
    await expectLater(
      () => dad.joinWithCode(code: code, name: 'Dad', role: Role.parent),
      throwsA(isA<BackendException>().having((e) => e.message, 'message', contains("child's phone"))),
    );
    // Lower-case with spaces still works.
    await phone(db, 'mia').joinWithCode(code: ' ${code.toLowerCase()} ', name: 'Mia', role: Role.child);

    await db.doc('invites/OLDCOD').set({'familyId': parent.familyId, 'role': 'child', 'expiresAt': 0});
    await expectLater(
      () => phone(db, 'leo').joinWithCode(code: 'OLDCOD', name: 'Leo', role: Role.child),
      throwsA(isA<BackendException>().having((e) => e.message, 'message', contains('expired'))),
    );
    await expectLater(
      () => phone(db, 'leo').joinWithCode(code: 'NOPE00', name: 'Leo', role: Role.child),
      throwsA(isA<BackendException>()),
    );
  });

  test('presence, history by day, and privacy-safe profile updates', () async {
    final (parent, child) = await familyWithChild();
    final f = parent.familyId;
    final miaPhone = phone(db, 'mia');
    final today = DateTime.now();
    final fix = LocationFix(lat: 51.5, lng: -0.1, accuracyM: 8, at: today);
    await miaPhone.publishPresence(f, 'mia', fix: fix, zoneId: 'home', shareZone: true);
    await miaPhone.publishPresence(f, 'mia', zoneId: 'school', shareZone: true); // places-only style
    await miaPhone.updateHealth(f, 'mia', DeviceHealth(lastSeen: today, batteryPct: 40));

    final kid = (await mum.watchChild(f, 'mia').first)!;
    expect(kid.lastFix!.lat, 51.5);
    expect(kid.currentZoneId, 'school');
    expect(kid.health!.batteryPct, 40);

    final history = await mum.watchHistory(f, 'mia', today).first;
    expect(history, hasLength(1));
    expect(await mum.watchHistory(f, 'mia', today.subtract(const Duration(days: 1))).first, isEmpty);

    // updateChild never overwrites presence or health owned by the child's phone.
    await mum.updateChild(f, kid.copyWith(privacyMode: PrivacyMode.placesOnly));
    final after = (await mum.watchChild(f, 'mia').first)!;
    expect(after.privacyMode, PrivacyMode.placesOnly);
    expect(after.lastFix, isNotNull);
    expect(after.health!.batteryPct, 40);
  });

  test('alerts arrive newest first; commands, views and tasks round-trip', () async {
    final (parent, _) = await familyWithChild();
    final f = parent.familyId;
    final miaPhone = phone(db, 'mia');
    final t0 = DateTime(2026, 10, 9, 8);
    for (var i = 0; i < 3; i++) {
      await miaPhone.pushEvent(f, AlertEvent(
          id: 'a$i', childId: 'mia', type: AlertType.checkIn, at: t0.add(Duration(minutes: i)), message: '$i'));
    }
    expect((await mum.watchAlerts(f).first).map((a) => a.id), ['a2', 'a1', 'a0']);

    await mum.sendCommand(f, Command(id: 'c1', childId: 'mia', type: CommandType.ring, at: t0, from: 'Mum'));
    expect((await miaPhone.watchCommands(f, 'mia').first).single.type, CommandType.ring);
    await miaPhone.ackCommand(f, 'c1');
    expect(await miaPhone.watchCommands(f, 'mia').first, isEmpty);

    await mum.recordView(f, ViewRecord(viewer: 'Mum', at: t0, childId: 'mia'));
    expect((await miaPhone.watchViews(f, 'mia').first).single.viewer, 'Mum');

    const task = FamilyTask(id: 't1', childId: 'mia', title: 'Bins', points: 15);
    await mum.saveTask(f, task);
    await miaPhone.saveTask(f, task.copyWith(status: TaskStatus.done));
    await mum.approveTask(f, task.copyWith(status: TaskStatus.done));
    expect((await mum.watchTasks(f).first).single.status, TaskStatus.approved);
    expect((await mum.watchChild(f, 'mia').first)!.points, 15);
  });

  test('zones and settings round-trip', () async {
    final s = await mum.createFamily(parentName: 'Mum');
    const school = Zone(
      id: 'school',
      name: 'School',
      lat: 1,
      lng: 2,
      radiusM: 200,
      alertWindow: TimeWindow(weekdays: {1, 2, 3, 4, 5}, startMinute: 480, endMinute: 900),
    );
    await mum.saveZone(s.familyId, school);
    final zones = await mum.watchZones(s.familyId).first;
    expect(zones.single.alertWindow!.weekdays, {1, 2, 3, 4, 5});

    await mum.saveSettings(
      s.familyId,
      const FamilySettings(
        quietHours: TimeWindow(weekdays: {1, 2, 3, 4, 5, 6, 7}, startMinute: 1320, endMinute: 420),
        maxPauseMinutes: 30,
      ),
    );
    final settings = await mum.watchSettings(s.familyId).first;
    expect(settings.quietHours!.startMinute, 1320);
    expect(settings.maxPauseMinutes, 30);

    await mum.deleteZone(s.familyId, 'school');
    expect(await mum.watchZones(s.familyId).first, isEmpty);
  });

  test('the session survives an app restart on the same phone', () async {
    final s = await mum.createFamily(parentName: 'Mum');
    final restored = await mum.restoreSession();
    expect(restored!.familyId, s.familyId);
    expect(restored.role, Role.parent);
    await mum.signOut();
    expect(await mum.restoreSession(), isNull);
  });
}
