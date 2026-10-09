import '../core/models.dart';

class BackendException implements Exception {
  BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Everything the app needs from a server. Two implementations ship:
/// [DemoBackend] (in memory, with a simulated child, runs with no setup)
/// and [FirestoreBackend] (real multi-device sync via Firebase).
abstract class FamilyBackend {
  /// Short label shown in settings ("Demo", "Firebase").
  String get name;

  // Sessions and pairing ------------------------------------------------------

  Future<Session?> restoreSession();
  Future<Session> createFamily({required String parentName});

  /// Invite codes are short, single-family, bound to the [role] the new
  /// member joins as, and expire after 24 hours.
  Future<String> createInviteCode(String familyId, {required Role role});
  Future<Session> joinWithCode({
    required String code,
    required String name,
    required Role role,
  });
  Future<void> signOut();

  /// Store-required account deletion. A child's location history, alerts
  /// and profile are erased; a parent's membership is removed, and the
  /// whole family is erased when the last parent leaves.
  Future<void> deleteAccount(Session session);

  // Family data -----------------------------------------------------------------

  Stream<List<ChildProfile>> watchChildren(String familyId);
  Stream<ChildProfile?> watchChild(String familyId, String childId);
  Future<void> updateChild(String familyId, ChildProfile child);

  Stream<List<Zone>> watchZones(String familyId);
  Future<void> saveZone(String familyId, Zone zone);
  Future<void> deleteZone(String familyId, String zoneId);

  Stream<FamilySettings> watchSettings(String familyId);
  Future<void> saveSettings(String familyId, FamilySettings settings);

  Stream<List<AlertEvent>> watchAlerts(String familyId, {int limit = 100});
  Future<void> pushEvent(String familyId, AlertEvent event);

  // Child → parent --------------------------------------------------------------

  /// Publishes what the privacy mode allows. [fix] null means "don't
  /// update coordinates"; [zoneId] is only written when [shareZone].
  Future<void> publishPresence(
    String familyId,
    String childId, {
    LocationFix? fix,
    String? zoneId,
    bool shareZone = false,
  });
  Future<void> updateHealth(String familyId, String childId, DeviceHealth health);
  Stream<List<LocationFix>> watchHistory(String familyId, String childId, DateTime day);

  // Parent → child --------------------------------------------------------------

  Future<void> sendCommand(String familyId, Command command);
  Stream<List<Command>> watchCommands(String familyId, String childId);
  Future<void> ackCommand(String familyId, String commandId);

  /// Logged every time a parent opens a child's live location, and shown to
  /// the child. Monitoring that the child can see is monitoring they trust.
  Future<void> recordView(String familyId, ViewRecord view);
  Stream<List<ViewRecord>> watchViews(String familyId, String childId);

  // Tasks and rewards -------------------------------------------------------------

  Stream<List<FamilyTask>> watchTasks(String familyId);
  Future<void> saveTask(String familyId, FamilyTask task);
  Future<void> deleteTask(String familyId, String taskId);

  /// Parent approves a done task: status → approved and points credited.
  Future<void> approveTask(String familyId, FamilyTask task);
}
