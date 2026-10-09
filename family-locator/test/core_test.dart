import 'package:family_locator/core/alert_policy.dart';
import 'package:family_locator/core/child_tracker.dart';
import 'package:family_locator/core/geo.dart';
import 'package:family_locator/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

const home = Zone(id: 'home', name: 'Home', lat: 52.5200, lng: 13.4050, radiusM: 100);

// ~111 m per 0.001 degrees of latitude.
LocationFix fixAt(double dLatMeters, DateTime at, {double acc = 10, double? speed}) =>
    LocationFix(
      lat: home.lat + dLatMeters / 111195,
      lng: home.lng,
      accuracyM: acc,
      at: at,
      speedMps: speed,
    );

final t0 = DateTime(2026, 10, 5, 8); // A Monday.

void main() {
  group('distanceM', () {
    test('matches a known distance', () {
      // Berlin → Paris is ~878 km.
      final d = distanceM(52.5200, 13.4050, 48.8566, 2.3522);
      expect(d / 1000, closeTo(878, 5));
    });
  });

  group('TimeWindow', () {
    test('daytime window respects weekdays', () {
      const school = TimeWindow(weekdays: {1, 2, 3, 4, 5}, startMinute: 8 * 60, endMinute: 15 * 60);
      expect(school.contains(DateTime(2026, 10, 5, 9)), isTrue); // Mon
      expect(school.contains(DateTime(2026, 10, 5, 16)), isFalse);
      expect(school.contains(DateTime(2026, 10, 10, 9)), isFalse); // Sat
    });

    test('overnight window belongs to the day it starts', () {
      const quiet = TimeWindow(weekdays: {5}, startMinute: 22 * 60, endMinute: 7 * 60);
      expect(quiet.contains(DateTime(2026, 10, 9, 23)), isTrue); // Fri 23:00
      expect(quiet.contains(DateTime(2026, 10, 10, 6)), isTrue); // Sat 06:00
      expect(quiet.contains(DateTime(2026, 10, 10, 8)), isFalse);
      expect(quiet.contains(DateTime(2026, 10, 9, 6)), isFalse); // Fri 06:00 (Thu not set)
    });
  });

  group('GeofenceEngine', () {
    test('first fix establishes state without an alert', () {
      final e = GeofenceEngine();
      expect(e.update(fixAt(0, t0), [home]), isEmpty);
      expect(e.currentZoneId([home]), 'home');
    });

    test('needs confirmation before leaving on a mediocre fix', () {
      final e = GeofenceEngine(confirmations: 2);
      e.update(fixAt(0, t0, acc: 50), [home]);
      expect(e.update(fixAt(250, t0.add(const Duration(minutes: 1)), acc: 50), [home]), isEmpty);
      final out = e.update(fixAt(260, t0.add(const Duration(minutes: 2)), acc: 50), [home]);
      expect(out.single.entered, isFalse);
    });

    test('a single precise fix is enough', () {
      final e = GeofenceEngine(confirmations: 3);
      e.update(fixAt(0, t0, acc: 5), [home]);
      final out = e.update(fixAt(300, t0.add(const Duration(minutes: 1)), acc: 5), [home]);
      expect(out.single.entered, isFalse);
    });

    test('boundary wobble does not flap', () {
      final e = GeofenceEngine();
      e.update(fixAt(90, t0, acc: 10), [home]);
      for (var i = 1; i < 10; i++) {
        final d = i.isEven ? 95.0 : 120.0; // inside, then inside the exit buffer
        expect(e.update(fixAt(d, t0.add(Duration(minutes: i)), acc: 10), [home]), isEmpty);
      }
    });

    test('ignores fixes too coarse to decide', () {
      final e = GeofenceEngine(confirmations: 1);
      e.update(fixAt(0, t0, acc: 10), [home]);
      expect(e.update(fixAt(2000, t0.add(const Duration(minutes: 1)), acc: 1500), [home]), isEmpty);
      expect(e.currentZoneId([home]), 'home');
    });

    test('prefers the smallest overlapping zone', () {
      const campus = Zone(id: 'campus', name: 'Campus', lat: 52.5200, lng: 13.4050, radiusM: 400);
      final e = GeofenceEngine();
      e.update(fixAt(0, t0), [campus, home]);
      expect(e.currentZoneId([campus, home]), 'home');
    });
  });

  group('MovementClassifier', () {
    test('uses reported speed with a median filter', () {
      final c = MovementClassifier();
      expect(c.classify(fixAt(0, t0, speed: 1.4)), MovementType.walking);
      expect(c.classify(fixAt(5, t0, speed: 1.3)), MovementType.walking);
      // One spurious spike doesn't make it a car ride.
      expect(c.classify(fixAt(10, t0, speed: 25)), MovementType.walking);
    });

    test('derives speed and ignores movement inside the noise', () {
      final c = MovementClassifier();
      c.classify(fixAt(0, t0, acc: 20));
      expect(c.classify(fixAt(15, t0.add(const Duration(seconds: 30)), acc: 20)),
          MovementType.stationary);
    });
  });

  group('AdaptiveLocationPolicy', () {
    test('SOS beats everything, including low battery', () {
      final s = AdaptiveLocationPolicy.choose(
          movement: MovementType.stationary, insideZone: true, batteryPct: 5, sosActive: true);
      expect(s.highAccuracy, isTrue);
      expect(s.interval, const Duration(seconds: 5));
    });

    test('low battery backs off unless charging', () {
      final low = AdaptiveLocationPolicy.choose(
          movement: MovementType.walking, insideZone: false, batteryPct: 10);
      expect(low.highAccuracy, isFalse);
      final charging = AdaptiveLocationPolicy.choose(
          movement: MovementType.walking, insideZone: false, batteryPct: 10, charging: true);
      expect(charging.highAccuracy, isTrue);
    });

    test('resting at a known place samples least', () {
      final s = AdaptiveLocationPolicy.choose(movement: MovementType.stationary, insideZone: true);
      expect(s.interval, const Duration(minutes: 10));
      expect(s.highAccuracy, isFalse);
    });
  });

  group('BatteryAlertGate', () {
    test('alerts once per discharge', () {
      final g = BatteryAlertGate(threshold: 15);
      expect(g.shouldAlert(20, charging: false), isFalse);
      expect(g.shouldAlert(15, charging: false), isTrue);
      expect(g.shouldAlert(12, charging: false), isFalse);
      expect(g.shouldAlert(40, charging: true), isFalse);
      expect(g.shouldAlert(14, charging: false), isTrue);
    });
  });

  group('decideDelivery', () {
    AlertEvent ev(AlertType type, DateTime at) =>
        AlertEvent(id: 'x', childId: 'c', type: type, at: at, message: '', zoneId: 'school');
    const quiet = FamilySettings(
        quietHours: TimeWindow(weekdays: {1, 2, 3, 4, 5, 6, 7}, startMinute: 21 * 60, endMinute: 7 * 60));
    const school = Zone(
        id: 'school',
        name: 'School',
        lat: 0,
        lng: 0,
        alertWindow: TimeWindow(weekdays: {1, 2, 3, 4, 5}, startMinute: 7 * 60, endMinute: 16 * 60));

    test('SOS ignores quiet hours', () {
      expect(decideDelivery(ev(AlertType.sos, DateTime(2026, 10, 5, 23)), quiet), Delivery.now);
    });

    test('zone alerts outside the zone schedule stay in the feed', () {
      expect(decideDelivery(ev(AlertType.arrived, DateTime(2026, 10, 10, 10)), quiet, zone: school),
          Delivery.feedOnly);
      expect(decideDelivery(ev(AlertType.arrived, DateTime(2026, 10, 5, 8)), quiet, zone: school),
          Delivery.now);
    });

    test('quiet hours hold non-urgent alerts for the digest', () {
      expect(decideDelivery(ev(AlertType.lowBattery, DateTime(2026, 10, 5, 22)), quiet),
          Delivery.digest);
      final summary = digestSummary([ev(AlertType.lowBattery, DateTime(2026, 10, 5, 22))]);
      expect(summary, startsWith('1 update during quiet hours'));
    });
  });

  group('ChildTracker', () {
    var n = 0;
    ChildTracker tracker(PrivacyMode mode) => ChildTracker(
          child: ChildProfile(id: 'c1', name: 'Ana', privacyMode: mode),
          zones: const [home],
          newId: () => 'id${n++}',
        );

    test('live mode shares fixes and arrival alerts with coordinates', () {
      final t = tracker(PrivacyMode.live);
      t.onFix(fixAt(500, t0, acc: 5));
      final out = t.onFix(fixAt(0, t0.add(const Duration(minutes: 5)), acc: 5));
      expect(out.sharedFix, isNotNull);
      expect(out.events.single.type, AlertType.arrived);
      expect(out.events.single.lat, isNotNull);
      expect(out.zoneId, 'home');
    });

    test('places-only mode shares the place but never coordinates', () {
      final t = tracker(PrivacyMode.placesOnly);
      t.onFix(fixAt(500, t0, acc: 5));
      final out = t.onFix(fixAt(0, t0.add(const Duration(minutes: 5)), acc: 5));
      expect(out.sharedFix, isNull);
      expect(out.shareZone, isTrue);
      expect(out.events.single.lat, isNull);
    });

    test('pause withholds everything until SOS', () {
      final t = tracker(PrivacyMode.live);
      t.onFix(fixAt(500, t0, acc: 5));
      final paused = t.pause(const Duration(hours: 1), 'party', t0);
      expect(paused.message, contains('until 09:00'));
      final out = t.onFix(fixAt(0, t0.add(const Duration(minutes: 5)), acc: 5));
      expect(out.sharedFix, isNull);
      expect(out.events, isEmpty);

      final sos = t.startSos(t0.add(const Duration(minutes: 6)));
      expect(sos.lat, isNotNull);
      final during = t.onFix(fixAt(0, t0.add(const Duration(minutes: 7)), acc: 5));
      expect(during.sharedFix, isNotNull);
      expect(during.spec.label, 'SOS: continuous');
    });

    test('check-in carries location even in check-in-only mode', () {
      final t = tracker(PrivacyMode.checkInOnly);
      final out = t.onFix(fixAt(0, t0, acc: 5));
      expect(out.sharedFix, isNull);
      final e = t.checkIn("I'm OK", t0);
      expect(e.lat, isNotNull);
      expect(e.message, "Ana: I'm OK (at Home)");
    });
  });

  group('buildTimeline', () {
    test('splits a day into stays and moves', () {
      final fixes = <LocationFix>[
        for (var i = 0; i <= 30; i += 5) fixAt(0, t0.add(Duration(minutes: i))),
        for (var i = 1; i <= 4; i++) fixAt(i * 300.0, t0.add(Duration(minutes: 30 + i * 2))),
        for (var i = 0; i <= 60; i += 10) fixAt(1500, t0.add(Duration(minutes: 40 + i))),
      ];
      final tl = buildTimeline(fixes, const [home]);
      expect(tl.map((e) => e.isStay).toList(), [true, false, true]);
      expect(tl.first.zone?.id, 'home');
      expect(tl[1].distanceM, closeTo(1500, 50));
      expect(tl.last.zone, isNull);
    });
  });

  test('models round-trip through maps', () {
    final child = ChildProfile(
      id: 'c',
      name: 'Ana',
      privacyMode: PrivacyMode.placesOnly,
      lastFix: fixAt(0, t0),
      health: DeviceHealth(lastSeen: t0, backgroundPermission: false, batteryPct: 40),
      pausedUntil: t0,
    );
    final back = ChildProfile.fromMap(child.toMap());
    expect(back.privacyMode, PrivacyMode.placesOnly);
    expect(back.lastFix!.lat, child.lastFix!.lat);
    expect(back.health!.issues.single, contains('Allow all the time'));
    expect(back.pausedUntil, t0);
  });
}
