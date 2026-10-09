# Family Locator

A family safety app in the vein of [Findmykids](https://play.google.com/store/apps/details?id=org.findmykids.app):
live location, places with arrival alerts, SOS, a loud signal, route history, and tasks with rewards.
It's rebuilt around the things that app's reviews complain about most: inaccurate or late locations,
billing traps, broken connections nobody notices, alert spam, and kids who feel spied on.

One Flutter app covers both sides. Pick "parent" or "child" when you set it up. Android and iOS.

## Try it in 30 seconds

```bash
flutter pub get
flutter run            # demo mode: no accounts, no setup
```

In demo mode, creating a family adds two sample kids. **Mia** walks between home, school and football
using the real child-side code: geofencing, the battery policy and alerts all run live. **Leo** is a
teen in "places only" mode, with a phone-health problem to fix. Under **Settings → Demo: open Mia's
phone** you can see the child's side.

## What's addressed, and how

| Common complaint about Findmykids | What this app does | Where |
| --- | --- | --- |
| "Shows my child at home when they're not" / wrong or late location | Every position shows its accuracy (±m) and age. Stale data is labelled *may be offline*, never shown as current. Fixes too coarse to judge a place are ignored. | `core/geo.dart` `GeofenceEngine`, `ui/common/widgets.dart` `ChildStatus` |
| False "left home" alerts from GPS wobble | Geofencing with hysteresis: leaving requires being clearly outside (radius + buffer), and a change needs 2 agreeing fixes unless the fix is precise. Overlapping places resolve to the smallest. | `GeofenceEngine` (unit-tested) |
| Battery drain | Adaptive sampling: high-accuracy GPS only while moving, during live view, or during SOS. It backs off at rest and at a known place, and drops to battery saver at ≤15%. | `AdaptiveLocationPolicy` |
| Tracking silently stops (permissions revoked, app killed, phone dead) | The child's phone reports a health checklist (permission "all the time", precise location, GPS on, notifications, battery saver). Parents see the exact problem, and the child gets a one-tap fix screen. The server alerts parents after N minutes of silence. | `DeviceHealth`, `ChildController._reportHealth`, `checkStalePhones` function |
| Charged after cancelling, pay-per-minute "listen" packs, ads | Core safety (SOS, places, alerts, history, ring) is free. There are no ads and no metered features. The plan screen commits to one-tap cancel and renewal reminders if a paid tier is ever added. | Settings → Plan |
| "Sound around" (covert microphone) feels like spying; teens resent it | Deliberately not built. Instead: **privacy modes** (live / places only / check-ins only), a **"who looked" log** the child can see, a **"what your family can see"** card, and a permanent "sharing location" notification. | `PrivacyMode`, `ViewRecord`, `ui/child/child_home.dart` |
| Kids uninstall or disable it | A **pause** with a reason and an end time (parent-set maximum, 0 disables it). Parents are told immediately, sharing resumes on its own, and SOS still works while paused. | `ChildTracker.pause` |
| Geofence alerts are "overkill" | Per-place schedules (school alerts on school days only; visits are still logged). Quiet hours batch non-urgent alerts into a morning summary. SOS and "tracking stopped" always break through. | `decideDelivery`, `digestSummary` |
| Hard to reconnect devices | 6-character family codes (no 0/O/1/I), valid 24 h, usable for the child and for a second guardian. | `createInviteCode` |
| Accidental SOS | Press-and-hold, then a 5-second cancel window. "I'm safe now" sends an all-clear. | `_SosButton` |

### Extra features

- **Quick check-ins**: "I'm OK", "On my way", "Pick me up please", or free text, always with location. In "check-ins only" mode they're the only thing shared.
- **Live for 5 min**: the parent temporarily boosts update rate, which then drops back automatically.
- **Ring loudly**: plays on the alarm stream (audible on silent). The child taps "I hear you" and the parent is told.
- **Day timeline**: history collapsed into stays and journeys ("School 08:15–15:30 · moved 1.2 km"), not a scribble of dots.
- **Multiple guardians**, **tasks & points** with parent approval, and **30-day history retention** (older data is deleted by a scheduled function).

## Project layout

```
lib/
  core/        Pure Dart, unit-tested: models, geofencing, movement, battery policy,
               alert delivery policy, timeline, and ChildTracker (all child-side decisions)
  data/        FamilyBackend interface; DemoBackend (in-memory + simulated child);
               FirestoreBackend (Firebase)
  services/    ChildController (runs on the child's phone), GPS/battery/alarm/notification adapters
  ui/          onboarding, parent (map, child detail, history, places, alerts, tasks, settings), child
firebase/
  firestore.rules          family-scoped access; children can't change their own privacy mode
  firestore.indexes.json
  functions/               push for alerts and ring, quiet-hours digest, stale-phone detector, history pruning
test/                      core logic + app/controller tests
store/                     listing copy, privacy policy, terms, deletion page, Data safety answers,
                           permission declarations, review notes, screenshots, icon, feature graphic
config/release.example.json  release settings (URLs, map tiles) passed via --dart-define-from-file
scripts/build_release.sh   checks for unfilled placeholders, then builds the .aab / .ipa
```

**Shipping to the stores:** follow [STORE_SUBMISSION.md](STORE_SUBMISSION.md). It lists every remaining
step that needs your accounts, keys or URLs.

## Going live with Firebase

1. Create a Firebase project. Enable **Anonymous Auth**, **Firestore** and **Cloud Messaging**.
2. `dart pub global activate flutterfire_cli && flutterfire configure`. This replaces `lib/firebase_options.dart`.
3. Deploy the rules, indexes and functions (Blaze plan needed for functions):
   ```bash
   cd firebase && npm --prefix functions install && firebase deploy
   ```
4. Run with `flutter run --dart-define=BACKEND=firebase`.

Notes:

- **Map tiles**: development builds use the public OpenStreetMap tile server, which is
  [not for production traffic](https://operations.osmfoundation.org/policies/tiles/). Release builds take
  `TILE_URL` from `config/release.json` (MapTiler, Stadia, Mapbox).
- **Store policies**: the prominent disclosure, account deletion, `isMonitoringTool` flag, privacy manifest
  and entitlements are already in place. The console forms are pre-answered in `store/`.
- **Time zones**: quiet hours and place schedules are evaluated on the server using the parent's UTC offset at
  the time settings were last saved. Families spanning time zones, or a DST change, need a re-save. Storing an
  IANA zone (via `flutter_timezone`) is the proper fix.
- **Children's data**: COPPA (US), GDPR-K (EU) and similar rules apply. A privacy-policy template is in
  `store/privacy-policy.md`. Have it reviewed for your markets.

## Development

```bash
flutter analyze
flutter test                                 # core logic, app flow, child controller
cd firebase/functions && npm install && npm test   # server policy tests
flutter build apk --debug
```
