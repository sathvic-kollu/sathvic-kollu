import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import '../core/models.dart';
import 'child_controller.dart';

const appVersion = '1.0.0';

/// Real GPS via geolocator. On Android this runs as a foreground service
/// with a permanent notification, so the child always knows sharing is on
/// (and Android doesn't kill tracking in the background).
class GeolocatorFixSource implements FixSource {
  final _ctrl = StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _sub;
  LocationRequestSpec? _spec;

  @override
  Stream<LocationFix> get fixes => _ctrl.stream;

  static LocationFix _toFix(Position p) => LocationFix(
        lat: p.latitude,
        lng: p.longitude,
        accuracyM: p.accuracy,
        speedMps: p.speed >= 0 ? p.speed : null,
        at: p.timestamp,
      );

  LocationSettings _settings(LocationRequestSpec spec) {
    final accuracy = spec.highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium;
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: spec.distanceFilterM,
        intervalDuration: spec.interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Sharing location with your family',
          notificationText: 'Tap to see what is shared or to pause.',
          notificationChannelName: 'Location sharing',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: spec.distanceFilterM,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        // The blue status-bar pill: tracking is never hidden from the child.
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: spec.distanceFilterM);
  }

  @override
  Future<void> start(LocationRequestSpec spec) async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      _ctrl.addError('Location permission is off');
      return;
    }
    _spec = spec;
    await _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings(spec)).listen(
      (p) => _ctrl.add(_toFix(p)),
      onError: (Object e) => _ctrl.addError(e),
    );
  }

  @override
  Future<void> apply(LocationRequestSpec spec) async {
    if (spec == _spec && _sub != null) return;
    await start(spec);
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<LocationFix?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      return _toFix(p);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : _toFix(last);
    }
  }
}

class PhoneStatus implements DeviceStatus {
  final _battery = Battery();

  @override
  Future<DeviceHealth> read() async {
    final permission = await Geolocator.checkPermission();
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    var precise = true;
    try {
      precise = await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.precise;
    } catch (_) {}
    int? level;
    var charging = false;
    var saver = false;
    try {
      level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      charging = state == BatteryState.charging || state == BatteryState.full;
      saver = await _battery.isInBatterySaveMode;
    } catch (_) {}
    return DeviceHealth(
      lastSeen: DateTime.now(),
      locationServiceOn: serviceOn,
      backgroundPermission: permission == LocationPermission.always,
      preciseLocation: precise,
      notificationsOn: await Notifier.instance.enabled(),
      batteryPct: level,
      charging: charging,
      powerSaveMode: saver,
      appVersion: appVersion,
    );
  }
}

/// Plays on the alarm stream so it is audible with the phone on silent,
/// and loops until the child taps "I hear you".
class LoudAlarm implements Alarm {
  AudioPlayer? _player;

  @override
  Future<void> start() async {
    final p = _player ??= AudioPlayer();
    await p.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
    ));
    await p.setReleaseMode(ReleaseMode.loop);
    await p.setVolume(1);
    await p.play(AssetSource('sounds/alarm.wav'));
  }

  @override
  Future<void> stop() async => _player?.stop();
}

/// Local notifications: alerts for parents, the ring for children.
class Notifier {
  Notifier._();
  static final instance = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 100;

  static const _alerts = AndroidNotificationDetails(
    'alerts',
    'Family alerts',
    channelDescription: 'Arrivals, departures, check-ins and battery',
    importance: Importance.defaultImportance,
  );
  static final _urgent = AndroidNotificationDetails(
    'urgent',
    'SOS and safety',
    channelDescription: 'SOS and tracking-stopped alerts. Loud, never batched.',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    // FLAG_INSISTENT: repeat the sound until the notification is opened.
    additionalFlags: Int32List.fromList([4]),
  );

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
    } catch (_) {
      // Tests and unsupported platforms: notifications become no-ops.
    }
  }

  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true, badge: true) ?? false;
  }

  Future<bool> enabled() async {
    await init();
    if (!_ready) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  Future<void> show(String title, String body, {bool urgent = false}) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: urgent ? _urgent : _alerts,
        iOS: DarwinNotificationDetails(
          interruptionLevel: urgent ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
        ),
      ),
    );
  }
}
