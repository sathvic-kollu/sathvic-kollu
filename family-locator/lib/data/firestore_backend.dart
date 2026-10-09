import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'backend.dart';

/// Firestore layout (see firebase/firestore.rules for who may do what):
///
///   invites/{code}                         familyId, expiresAt
///   families/{f}                           settings
///   families/{f}/members/{uid}             role, name, fcmTokens
///   families/{f}/children/{uid}            ChildProfile
///   families/{f}/children/{uid}/history/*  LocationFix + day
///   families/{f}/zones|alerts|commands|views|tasks/*
class FirestoreBackend implements FamilyBackend {
  FirestoreBackend({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    Future<String?> Function()? timeZone,
    this.registerPush = true,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _timeZone = timeZone ?? _deviceTimeZone;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final Future<String?> Function() _timeZone;

  /// Off in tests, where there is no messaging plugin.
  final bool registerPush;

  static Future<String?> _deviceTimeZone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return null;
    }
  }

  /// Lets the server evaluate quiet hours and place schedules in the
  /// family's local time. The IANA name follows daylight saving; the offset
  /// is a fallback for devices that can't report a zone name.
  Future<Map<String, Object?>> _zoneFields() async => {
        'tz': ?await _timeZone(),
        'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      };
  static const _sessionKey = 'session';

  @override
  String get name => 'Firebase';

  DocumentReference<Map<String, dynamic>> _family(String f) => _db.collection('families').doc(f);
  CollectionReference<Map<String, dynamic>> _col(String f, String name) =>
      _family(f).collection(name);

  Future<String> _uid() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
    if (user == null) throw BackendException('Could not sign in.');
    return user.uid;
  }

  Future<Session> _save(Session s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(s.toMap()));
    await _registerPushToken(s);
    return s;
  }

  Future<void> _registerPushToken(Session s) async {
    if (!registerPush) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null) return;
      await _col(s.familyId, 'members').doc(s.memberId).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    } catch (_) {
      // Push is a backup channel; live sync still works without it.
    }
  }

  @override
  Future<Session?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || _auth.currentUser == null) return null;
    final s = Session.fromMap((jsonDecode(raw) as Map).cast());
    if (s.memberId != _auth.currentUser!.uid) return null;
    await _registerPushToken(s);
    return s;
  }

  @override
  Future<Session> createFamily({required String parentName}) async {
    final uid = await _uid();
    final family = _db.collection('families').doc();
    await family.set({
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'settings': const FamilySettings().toMap(),
      ...await _zoneFields(),
    });
    await family.collection('members').doc(uid).set({'role': 'parent', 'name': parentName});
    return _save(Session(familyId: family.id, memberId: uid, role: Role.parent, displayName: parentName));
  }

  @override
  Future<String> createInviteCode(String familyId, {required Role role}) async {
    await _uid();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I confusion
    final r = math.Random.secure();
    final code = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
    await _db.collection('invites').doc(code).set({
      'familyId': familyId,
      'role': role.name,
      'expiresAt': DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      'createdBy': _auth.currentUser!.uid,
    });
    return code;
  }

  @override
  Future<Session> joinWithCode({required String code, required String name, required Role role}) async {
    final uid = await _uid();
    final normalized = code.trim().toUpperCase();
    final invite = await _db.collection('invites').doc(normalized).get();
    final data = invite.data();
    if (data == null) throw BackendException('That code was not found. Check for typos.');
    if ((data['expiresAt'] as num) < DateTime.now().millisecondsSinceEpoch) {
      throw BackendException('That code has expired. Ask for a new one.');
    }
    final familyId = data['familyId'] as String;
    if (data['role'] != role.name) {
      throw BackendException(data['role'] == 'child'
          ? "This code is for a child's phone. Choose \"I'm the child\"."
          : 'This code is for a parent or guardian. Choose "I\'m a guardian".');
    }
    await _col(familyId, 'members').doc(uid).set({'role': role.name, 'name': name, 'invite': normalized});
    if (role == Role.child) {
      await _col(familyId, 'children').doc(uid).set(ChildProfile(id: uid, name: name).toMap());
    }
    return _save(Session(familyId: familyId, memberId: uid, role: role, displayName: name));
  }

  @override
  Future<void> deleteAccount(Session session) async {
    // Server-side so it can remove subcollections and the auth user, which
    // a client can't do under the security rules.
    await FirebaseFunctions.instance.httpsCallable('deleteMyData').call<void>({'familyId': session.familyId});
    await signOut();
  }

  @override
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await _auth.signOut();
  }

  // ---------------------------------------------------------------------------

  @override
  Stream<List<ChildProfile>> watchChildren(String familyId) => _col(familyId, 'children')
      .snapshots()
      .map((s) => s.docs.map((d) => ChildProfile.fromMap(d.data())).toList());

  @override
  Stream<ChildProfile?> watchChild(String familyId, String childId) => _col(familyId, 'children')
      .doc(childId)
      .snapshots()
      .map((d) => d.data() == null ? null : ChildProfile.fromMap(d.data()!));

  @override
  Future<void> updateChild(String familyId, ChildProfile child) {
    final m = child.toMap()
      // Presence and health have their own writers.
      ..remove('lastFix')
      ..remove('zoneId')
      ..remove('health');
    return _col(familyId, 'children').doc(child.id).set(m, SetOptions(merge: true));
  }

  @override
  Stream<List<Zone>> watchZones(String familyId) =>
      _col(familyId, 'zones').snapshots().map((s) => s.docs.map((d) => Zone.fromMap(d.data())).toList());

  @override
  Future<void> saveZone(String familyId, Zone zone) => _col(familyId, 'zones').doc(zone.id).set(zone.toMap());

  @override
  Future<void> deleteZone(String familyId, String zoneId) => _col(familyId, 'zones').doc(zoneId).delete();

  @override
  Stream<FamilySettings> watchSettings(String familyId) => _family(familyId).snapshots().map((d) {
        final s = d.data()?['settings'];
        return s is Map ? FamilySettings.fromMap(s.cast()) : const FamilySettings();
      });

  @override
  Future<void> saveSettings(String familyId, FamilySettings settings) =>
      _zoneFields().then((zone) => _family(familyId).set({
            'settings': settings.toMap(),
            ...zone,
          }, SetOptions(merge: true)));

  @override
  Stream<List<AlertEvent>> watchAlerts(String familyId, {int limit = 100}) => _col(familyId, 'alerts')
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => AlertEvent.fromMap(d.data())).toList());

  @override
  Future<void> pushEvent(String familyId, AlertEvent event) =>
      _col(familyId, 'alerts').doc(event.id).set(event.toMap());

  static String _day(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  @override
  Future<void> publishPresence(
    String familyId,
    String childId, {
    LocationFix? fix,
    String? zoneId,
    bool shareZone = false,
  }) async {
    final child = _col(familyId, 'children').doc(childId);
    final update = <String, Object?>{
      if (fix != null) 'lastFix': fix.toMap(),
      if (shareZone) 'zoneId': zoneId,
    };
    if (update.isEmpty) return;
    final batch = _db.batch()..set(child, update, SetOptions(merge: true));
    if (fix != null) {
      batch.set(child.collection('history').doc(), {...fix.toMap(), 'day': _day(fix.at)});
    }
    await batch.commit();
  }

  @override
  Future<void> updateHealth(String familyId, String childId, DeviceHealth health) =>
      _col(familyId, 'children').doc(childId).set({'health': health.toMap()}, SetOptions(merge: true));

  @override
  Stream<List<LocationFix>> watchHistory(String familyId, String childId, DateTime day) =>
      _col(familyId, 'children')
          .doc(childId)
          .collection('history')
          .where('day', isEqualTo: _day(day))
          .orderBy('at')
          .snapshots()
          .map((s) => s.docs.map((d) => LocationFix.fromMap(d.data())).toList());

  @override
  Future<void> sendCommand(String familyId, Command command) =>
      _col(familyId, 'commands').doc(command.id).set(command.toMap());

  @override
  Stream<List<Command>> watchCommands(String familyId, String childId) => _col(familyId, 'commands')
      .where('childId', isEqualTo: childId)
      .snapshots()
      .map((s) => s.docs.map((d) => Command.fromMap(d.data())).toList());

  @override
  Future<void> ackCommand(String familyId, String commandId) =>
      _col(familyId, 'commands').doc(commandId).delete();

  @override
  Future<void> recordView(String familyId, ViewRecord view) => _col(familyId, 'views').add(view.toMap());

  @override
  Stream<List<ViewRecord>> watchViews(String familyId, String childId) => _col(familyId, 'views')
      .where('childId', isEqualTo: childId)
      .orderBy('at', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map((d) => ViewRecord.fromMap(d.data())).toList());

  @override
  Stream<List<FamilyTask>> watchTasks(String familyId) => _col(familyId, 'tasks')
      .snapshots()
      .map((s) => s.docs.map((d) => FamilyTask.fromMap(d.data())).toList());

  @override
  Future<void> saveTask(String familyId, FamilyTask task) =>
      _col(familyId, 'tasks').doc(task.id).set(task.toMap());

  @override
  Future<void> deleteTask(String familyId, String taskId) => _col(familyId, 'tasks').doc(taskId).delete();

  @override
  Future<void> approveTask(String familyId, FamilyTask task) {
    final batch = _db.batch()
      ..set(_col(familyId, 'tasks').doc(task.id), task.copyWith(status: TaskStatus.approved).toMap())
      ..update(_col(familyId, 'children').doc(task.childId), {'points': FieldValue.increment(task.points)});
    return batch.commit();
  }
}
