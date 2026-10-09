// Plain data types shared by the parent app, the child app and every backend.
// Everything serialises to a Firestore-friendly map (no nested custom types
// that Firestore can't store, timestamps as epoch milliseconds).

enum Role { parent, child }

enum MovementType { stationary, walking, running, cycling, vehicle, unknown }

/// How much of their location a child shares. Older kids get a less
/// intrusive mode instead of being pushed to uninstall the app.
enum PrivacyMode {
  /// Live location, history and place alerts.
  live,

  /// Parents only see which named place the child is at (or "out"), plus
  /// arrivals and departures. No coordinates, no route history.
  placesOnly,

  /// Nothing is shared until the child checks in or presses SOS.
  checkInOnly,
}

enum AlertType {
  arrived,
  left,
  sos,
  sosCancelled,
  checkIn,
  lowBattery,
  trackingOff,
  permissionLost,
  sharingPaused,
  sharingResumed,
  signalAcknowledged,
  taskDone,
}

/// Urgent alerts break through quiet hours and are never batched.
const urgentAlertTypes = {
  AlertType.sos,
  AlertType.trackingOff,
  AlertType.permissionLost,
};

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DateTime _date(Object? ms) =>
    DateTime.fromMillisecondsSinceEpoch((ms as num?)?.toInt() ?? 0);

DateTime? _dateOrNull(Object? ms) => ms == null ? null : _date(ms);

double? _doubleOrNull(Object? v) => (v as num?)?.toDouble();

class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.at,
    this.speedMps,
    this.batteryPct,
    this.movement = MovementType.unknown,
  });

  final double lat;
  final double lng;

  /// Radius of 68% confidence, in metres. Always shown to parents so a
  /// coarse network fix is never presented as a precise one.
  final double accuracyM;
  final DateTime at;
  final double? speedMps;
  final int? batteryPct;
  final MovementType movement;

  LocationFix copyWith({MovementType? movement, int? batteryPct}) =>
      LocationFix(
        lat: lat,
        lng: lng,
        accuracyM: accuracyM,
        at: at,
        speedMps: speedMps,
        batteryPct: batteryPct ?? this.batteryPct,
        movement: movement ?? this.movement,
      );

  Map<String, Object?> toMap() => {
        'lat': lat,
        'lng': lng,
        'acc': accuracyM,
        'at': at.millisecondsSinceEpoch,
        'speed': speedMps,
        'battery': batteryPct,
        'movement': movement.name,
      };

  factory LocationFix.fromMap(Map<String, Object?> m) => LocationFix(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        accuracyM: (m['acc'] as num?)?.toDouble() ?? 0,
        at: _date(m['at']),
        speedMps: _doubleOrNull(m['speed']),
        batteryPct: (m['battery'] as num?)?.toInt(),
        movement: _enumByName(
            MovementType.values, m['movement'], MovementType.unknown),
      );
}

/// A weekly time window, e.g. Mon–Fri 08:00–15:30. Windows that end before
/// they start wrap past midnight (22:00–07:00).
class TimeWindow {
  const TimeWindow({
    required this.weekdays,
    required this.startMinute,
    required this.endMinute,
  });

  /// Every day, all day.
  static const always = TimeWindow(
    weekdays: {1, 2, 3, 4, 5, 6, 7},
    startMinute: 0,
    endMinute: 24 * 60,
  );

  /// ISO weekdays, Monday = 1 … Sunday = 7.
  final Set<int> weekdays;
  final int startMinute;
  final int endMinute;

  bool contains(DateTime t) {
    final minute = t.hour * 60 + t.minute;
    if (startMinute <= endMinute) {
      return weekdays.contains(t.weekday) &&
          minute >= startMinute &&
          minute < endMinute;
    }
    // Overnight window: the part after midnight belongs to the previous day.
    if (minute >= startMinute) return weekdays.contains(t.weekday);
    if (minute < endMinute) {
      final previousDay = t.weekday == 1 ? 7 : t.weekday - 1;
      return weekdays.contains(previousDay);
    }
    return false;
  }

  Map<String, Object?> toMap() => {
        'days': weekdays.toList()..sort(),
        'start': startMinute,
        'end': endMinute,
      };

  factory TimeWindow.fromMap(Map<String, Object?> m) => TimeWindow(
        weekdays: ((m['days'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toSet(),
        startMinute: (m['start'] as num?)?.toInt() ?? 0,
        endMinute: (m['end'] as num?)?.toInt() ?? 24 * 60,
      );
}

/// A named circular place (home, school, practice).
class Zone {
  const Zone({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.radiusM = 150,
    this.emoji = '📍',
    this.notifyArrive = true,
    this.notifyLeave = true,
    this.alertWindow,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusM;
  final String emoji;
  final bool notifyArrive;
  final bool notifyLeave;

  /// When set, arrival/departure alerts for this zone only fire inside the
  /// window (school alerts on school days only). Presence is still tracked.
  final TimeWindow? alertWindow;

  Zone copyWith({
    String? name,
    double? lat,
    double? lng,
    double? radiusM,
    String? emoji,
    bool? notifyArrive,
    bool? notifyLeave,
    TimeWindow? alertWindow,
    bool clearAlertWindow = false,
  }) =>
      Zone(
        id: id,
        name: name ?? this.name,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        radiusM: radiusM ?? this.radiusM,
        emoji: emoji ?? this.emoji,
        notifyArrive: notifyArrive ?? this.notifyArrive,
        notifyLeave: notifyLeave ?? this.notifyLeave,
        alertWindow:
            clearAlertWindow ? null : (alertWindow ?? this.alertWindow),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radiusM,
        'emoji': emoji,
        'notifyArrive': notifyArrive,
        'notifyLeave': notifyLeave,
        'window': alertWindow?.toMap(),
      };

  factory Zone.fromMap(Map<String, Object?> m) => Zone(
        id: m['id'] as String,
        name: m['name'] as String? ?? 'Place',
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        radiusM: (m['radius'] as num?)?.toDouble() ?? 150,
        emoji: m['emoji'] as String? ?? '📍',
        notifyArrive: m['notifyArrive'] as bool? ?? true,
        notifyLeave: m['notifyLeave'] as bool? ?? true,
        alertWindow: m['window'] == null
            ? null
            : TimeWindow.fromMap(
                (m['window'] as Map).cast<String, Object?>()),
      );
}

/// What the child's phone reports about its own ability to share location.
/// Shown to parents as a checklist so "the app stopped working" becomes
/// "location permission was switched to While Using".
class DeviceHealth {
  const DeviceHealth({
    required this.lastSeen,
    this.locationServiceOn = true,
    this.backgroundPermission = true,
    this.preciseLocation = true,
    this.notificationsOn = true,
    this.batteryPct,
    this.charging = false,
    this.powerSaveMode = false,
    this.appVersion = '',
  });

  final DateTime lastSeen;
  final bool locationServiceOn;
  final bool backgroundPermission;
  final bool preciseLocation;
  final bool notificationsOn;
  final int? batteryPct;
  final bool charging;
  final bool powerSaveMode;
  final String appVersion;

  /// Human-readable problems, worst first. Empty means healthy.
  List<String> get issues => [
        if (!locationServiceOn) 'Location services are turned off',
        if (!backgroundPermission)
          'Location permission is not set to "Allow all the time"',
        if (!preciseLocation) 'Precise location is off (fixes may be ~3 km)',
        if (!notificationsOn) 'Notifications are blocked (SOS replies, ring)',
        if (powerSaveMode) 'Battery saver may delay updates',
      ];

  Map<String, Object?> toMap() => {
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'locationOn': locationServiceOn,
        'background': backgroundPermission,
        'precise': preciseLocation,
        'notifications': notificationsOn,
        'battery': batteryPct,
        'charging': charging,
        'powerSave': powerSaveMode,
        'appVersion': appVersion,
      };

  factory DeviceHealth.fromMap(Map<String, Object?> m) => DeviceHealth(
        lastSeen: _date(m['lastSeen']),
        locationServiceOn: m['locationOn'] as bool? ?? true,
        backgroundPermission: m['background'] as bool? ?? true,
        preciseLocation: m['precise'] as bool? ?? true,
        notificationsOn: m['notifications'] as bool? ?? true,
        batteryPct: (m['battery'] as num?)?.toInt(),
        charging: m['charging'] as bool? ?? false,
        powerSaveMode: m['powerSave'] as bool? ?? false,
        appVersion: m['appVersion'] as String? ?? '',
      );
}

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    this.emoji = '🧒',
    this.privacyMode = PrivacyMode.live,
    this.lastFix,
    this.currentZoneId,
    this.health,
    this.pausedUntil,
    this.pauseReason,
    this.points = 0,
    this.sosActiveSince,
  });

  final String id;
  final String name;
  final String emoji;
  final PrivacyMode privacyMode;
  final LocationFix? lastFix;
  final String? currentZoneId;
  final DeviceHealth? health;
  final DateTime? pausedUntil;
  final String? pauseReason;
  final int points;
  final DateTime? sosActiveSince;

  bool isPaused(DateTime now) => pausedUntil != null && now.isBefore(pausedUntil!);

  ChildProfile copyWith({
    String? name,
    String? emoji,
    PrivacyMode? privacyMode,
    LocationFix? lastFix,
    String? currentZoneId,
    bool clearZone = false,
    DeviceHealth? health,
    DateTime? pausedUntil,
    String? pauseReason,
    bool clearPause = false,
    int? points,
    DateTime? sosActiveSince,
    bool clearSos = false,
  }) =>
      ChildProfile(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        privacyMode: privacyMode ?? this.privacyMode,
        lastFix: lastFix ?? this.lastFix,
        currentZoneId: clearZone ? null : (currentZoneId ?? this.currentZoneId),
        health: health ?? this.health,
        pausedUntil: clearPause ? null : (pausedUntil ?? this.pausedUntil),
        pauseReason: clearPause ? null : (pauseReason ?? this.pauseReason),
        points: points ?? this.points,
        sosActiveSince: clearSos ? null : (sosActiveSince ?? this.sosActiveSince),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'privacyMode': privacyMode.name,
        'lastFix': lastFix?.toMap(),
        'zoneId': currentZoneId,
        'health': health?.toMap(),
        'pausedUntil': pausedUntil?.millisecondsSinceEpoch,
        'pauseReason': pauseReason,
        'points': points,
        'sosSince': sosActiveSince?.millisecondsSinceEpoch,
      };

  factory ChildProfile.fromMap(Map<String, Object?> m) => ChildProfile(
        id: m['id'] as String,
        name: m['name'] as String? ?? 'Child',
        emoji: m['emoji'] as String? ?? '🧒',
        privacyMode:
            _enumByName(PrivacyMode.values, m['privacyMode'], PrivacyMode.live),
        lastFix: m['lastFix'] == null
            ? null
            : LocationFix.fromMap((m['lastFix'] as Map).cast()),
        currentZoneId: m['zoneId'] as String?,
        health: m['health'] == null
            ? null
            : DeviceHealth.fromMap((m['health'] as Map).cast()),
        pausedUntil: _dateOrNull(m['pausedUntil']),
        pauseReason: m['pauseReason'] as String?,
        points: (m['points'] as num?)?.toInt() ?? 0,
        sosActiveSince: _dateOrNull(m['sosSince']),
      );
}

class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.childId,
    required this.type,
    required this.at,
    required this.message,
    this.lat,
    this.lng,
    this.zoneId,
  });

  final String id;
  final String childId;
  final AlertType type;
  final DateTime at;
  final String message;
  final double? lat;
  final double? lng;
  final String? zoneId;

  bool get urgent => urgentAlertTypes.contains(type);

  Map<String, Object?> toMap() => {
        'id': id,
        'childId': childId,
        'type': type.name,
        'at': at.millisecondsSinceEpoch,
        'message': message,
        'lat': lat,
        'lng': lng,
        'zoneId': zoneId,
        'urgent': urgent,
      };

  factory AlertEvent.fromMap(Map<String, Object?> m) => AlertEvent(
        id: m['id'] as String,
        childId: m['childId'] as String,
        type: _enumByName(AlertType.values, m['type'], AlertType.checkIn),
        at: _date(m['at']),
        message: m['message'] as String? ?? '',
        lat: _doubleOrNull(m['lat']),
        lng: _doubleOrNull(m['lng']),
        zoneId: m['zoneId'] as String?,
      );
}

enum CommandType { ring, liveMode, refresh }

/// Parent → child request. The child acknowledges by deleting it.
class Command {
  const Command({
    required this.id,
    required this.childId,
    required this.type,
    required this.at,
    required this.from,
  });

  final String id;
  final String childId;
  final CommandType type;
  final DateTime at;
  final String from;

  Map<String, Object?> toMap() => {
        'id': id,
        'childId': childId,
        'type': type.name,
        'at': at.millisecondsSinceEpoch,
        'from': from,
      };

  factory Command.fromMap(Map<String, Object?> m) => Command(
        id: m['id'] as String,
        childId: m['childId'] as String,
        type: _enumByName(CommandType.values, m['type'], CommandType.refresh),
        at: _date(m['at']),
        from: m['from'] as String? ?? 'Parent',
      );
}

/// Shown to the child: who looked at their location and when.
class ViewRecord {
  const ViewRecord({required this.viewer, required this.at, required this.childId});

  final String viewer;
  final DateTime at;
  final String childId;

  Map<String, Object?> toMap() =>
      {'viewer': viewer, 'at': at.millisecondsSinceEpoch, 'childId': childId};

  factory ViewRecord.fromMap(Map<String, Object?> m) => ViewRecord(
        viewer: m['viewer'] as String? ?? 'Parent',
        at: _date(m['at']),
        childId: m['childId'] as String? ?? '',
      );
}

enum TaskStatus { open, done, approved }

class FamilyTask {
  const FamilyTask({
    required this.id,
    required this.childId,
    required this.title,
    this.points = 10,
    this.status = TaskStatus.open,
  });

  final String id;
  final String childId;
  final String title;
  final int points;
  final TaskStatus status;

  FamilyTask copyWith({TaskStatus? status}) => FamilyTask(
        id: id,
        childId: childId,
        title: title,
        points: points,
        status: status ?? this.status,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'childId': childId,
        'title': title,
        'points': points,
        'status': status.name,
      };

  factory FamilyTask.fromMap(Map<String, Object?> m) => FamilyTask(
        id: m['id'] as String,
        childId: m['childId'] as String,
        title: m['title'] as String? ?? '',
        points: (m['points'] as num?)?.toInt() ?? 0,
        status: _enumByName(TaskStatus.values, m['status'], TaskStatus.open),
      );
}

class FamilySettings {
  const FamilySettings({
    this.quietHours,
    this.lowBatteryPct = 15,
    this.maxPauseMinutes = 60,
    this.staleAfterMinutes = 30,
  });

  /// Non-urgent alerts during these hours are held and delivered as one
  /// summary afterwards. SOS and "tracking stopped" always go through.
  final TimeWindow? quietHours;
  final int lowBatteryPct;

  /// Longest a child may pause sharing in one go. 0 disables pausing.
  final int maxPauseMinutes;

  /// Silence longer than this raises a "tracking may be off" alert.
  final int staleAfterMinutes;

  FamilySettings copyWith({
    TimeWindow? quietHours,
    bool clearQuietHours = false,
    int? lowBatteryPct,
    int? maxPauseMinutes,
    int? staleAfterMinutes,
  }) =>
      FamilySettings(
        quietHours: clearQuietHours ? null : (quietHours ?? this.quietHours),
        lowBatteryPct: lowBatteryPct ?? this.lowBatteryPct,
        maxPauseMinutes: maxPauseMinutes ?? this.maxPauseMinutes,
        staleAfterMinutes: staleAfterMinutes ?? this.staleAfterMinutes,
      );

  Map<String, Object?> toMap() => {
        'quietHours': quietHours?.toMap(),
        'lowBatteryPct': lowBatteryPct,
        'maxPauseMinutes': maxPauseMinutes,
        'staleAfterMinutes': staleAfterMinutes,
      };

  factory FamilySettings.fromMap(Map<String, Object?> m) => FamilySettings(
        quietHours: m['quietHours'] == null
            ? null
            : TimeWindow.fromMap((m['quietHours'] as Map).cast()),
        lowBatteryPct: (m['lowBatteryPct'] as num?)?.toInt() ?? 15,
        maxPauseMinutes: (m['maxPauseMinutes'] as num?)?.toInt() ?? 60,
        staleAfterMinutes: (m['staleAfterMinutes'] as num?)?.toInt() ?? 30,
      );
}

/// Who is signed in on this device.
class Session {
  const Session({
    required this.familyId,
    required this.memberId,
    required this.role,
    required this.displayName,
  });

  final String familyId;

  /// For a child this is also their [ChildProfile.id].
  final String memberId;
  final Role role;
  final String displayName;

  Map<String, Object?> toMap() => {
        'familyId': familyId,
        'memberId': memberId,
        'role': role.name,
        'displayName': displayName,
      };

  factory Session.fromMap(Map<String, Object?> m) => Session(
        familyId: m['familyId'] as String,
        memberId: m['memberId'] as String,
        role: _enumByName(Role.values, m['role'], Role.parent),
        displayName: m['displayName'] as String? ?? '',
      );
}
