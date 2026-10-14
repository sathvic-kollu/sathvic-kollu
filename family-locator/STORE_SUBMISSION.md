# Store submission: your checklist

All the code is done. What's left is accounts, keys, URLs and console forms that only you can
fill. Work top to bottom. Each item says exactly where the value goes. When every box is ticked,
`scripts/build_release.sh` produces the files you upload.

Everything already prepared for you is in [`store/`](store/): listing copy, privacy policy, terms,
the deletion page, Data safety / App Privacy answers, permission declarations, review notes,
screenshots, icon and feature graphic.

---

## 1. Decide identity (5 min)

- [ ] **App name.** Default: "Family Locator: Kids Safety". Check it's free in both stores and not a trademark.
      To change it: `android/app/src/main/AndroidManifest.xml` (`android:label`), `ios/Runner/Info.plist`
      (`CFBundleDisplayName`), `lib/main.dart` (`title:`), `store/listing.md`.
- [ ] **Package / bundle ID.** Default: `com.techtenstein.familylocator`, permanent once published.
      To change it: `android/app/build.gradle.kts` (`applicationId`) and `ios/Runner.xcodeproj/project.pbxproj`
      (`PRODUCT_BUNDLE_IDENTIFIER`, 3 places). Also record it in `docs/app/INTAKE.md` if your template has one.
- [ ] **Version.** `pubspec.yaml` → `version: 1.0.0+1`. Bump the `+N` build number on every upload.

## 2. Firebase backend (≈30 min)

- [ ] Create a Firebase project at https://console.firebase.google.com (choose a region, then record it in the privacy policy).
- [ ] Enable **Authentication → Anonymous**, **Firestore** (production mode), **Cloud Messaging**,
      **Crashlytics** and **Hosting**.
- [ ] Upgrade to the **Blaze** plan (Cloud Functions need it; the free tier covers a small user base).
- [ ] `dart pub global activate flutterfire_cli && flutterfire configure`, choosing the Android + iOS apps
      with your package/bundle ID. This **replaces `lib/firebase_options.dart`**. Commit it.
- [ ] iOS push: Apple Developer → Keys → create an **APNs key** (.p8), then upload it in
      Firebase → Project settings → Cloud Messaging → Apple app.
- [ ] **App Check** → register both apps: Android with **Play Integrity** (paste the *app signing key*
      SHA-256 from Play Console → Setup → App signing), iOS with **App Attest**. Leave enforcement **off**
      for now (step 10).
- [ ] Deploy (after step 4, because the deploy refuses to publish legal pages that still have placeholders):
      `cd firebase && firebase use <project-id> && npm --prefix functions install && firebase deploy`.
      This deploys rules, indexes, the functions `onAlertCreated`, `onCommandCreated`, `checkStalePhones`,
      `pruneHistory` and `deleteMyData`, and your legal pages (step 4).

## 3. Map tiles (10 min)

- [ ] Create a free key at a tile provider (e.g. https://cloud.maptiler.com, Stadia, Mapbox). The public
      OpenStreetMap server is not allowed for production apps.

## 4. Legal pages (≈20 min)

- [ ] Fill every `[BRACKETED]` value in `store/privacy-policy.md`, `store/terms.md`, `store/delete-account.md`.
- [ ] Nothing else to host: `firebase deploy` (step 2) publishes them on Firebase Hosting at
      `https://<project-id>.web.app/privacy`, `/terms` and `/delete-account`. A custom domain can be added in
      Firebase → Hosting.
- [ ] Set up a monitored support inbox.

## 5. Release config (2 min)

- [ ] `cp config/release.example.json config/release.json` (git-ignored) and fill:
      `PRIVACY_URL` (`https://<project-id>.web.app/privacy`), `TERMS_URL` (`…/terms`), `SUPPORT_EMAIL`,
      `TILE_URL` (with your key), `TILE_ATTRIBUTION`.

## 6. Android signing (5 min)

- [ ] Create an upload key (keep the .jks and passwords somewhere safe and backed up):
      `keytool -genkey -v -keystore ~/family-locator-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
- [ ] `cp android/key.properties.example android/key.properties` (git-ignored) and fill in the four values.

## 7. Build

- [ ] Android: `scripts/build_release.sh android` → `build/app/outputs/bundle/release/app-release.aab`
- [ ] iOS (on a Mac with Xcode): `cd ios && pod install`, open `Runner.xcworkspace`, choose your **Team** under
      Signing & Capabilities, confirm **Push Notifications**, **Background Modes (Location, Remote notifications)**
      and **Time Sensitive Notifications** are listed (already in `Runner.entitlements` / `Info.plist`). Then run
      `scripts/build_release.sh ios`.
- [ ] **No Mac?** Use Codemagic (`codemagic.yaml` is ready). It builds both apps in the cloud and uploads
      them to Play internal testing and TestFlight:
  1. Sign in at https://codemagic.io with GitHub and add this repository.
  2. Team settings → Code signing identities: upload your Android upload keystore as `family_locator_upload`.
  3. Team integrations → App Store Connect: add an API key (App Store Connect → Users and Access → Integrations)
     named `family_locator_asc`. Codemagic then creates the iOS certificates and profiles for you.
  4. Global variables, group `family_locator`: `FIREBASE_OPTIONS_B64`, `RELEASE_JSON_B64`, and
     `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` (a Play Console service account with release permission).
  5. Start the `android-release` and `ios-release` workflows. The first Play upload must be done by hand
     in the console; after that Codemagic can upload.
- [ ] Smoke-test the release build on two real phones (parent + child): join with a code, walk out of a
      place, press SOS, ring, delete account.

## 8. Google Play Console

- [ ] Developer account ($25 one-time). Create the app: name, default language, **App**, **Free**.
- [ ] **Main store listing**: copy from `store/listing.md`. Icon `store/play-icon-512.png`, feature graphic
      `store/play-feature-graphic-1024x500.png`, phone screenshots `store/screenshots/android-phone/*`.
- [ ] **App content**:
  - [ ] Privacy policy URL
  - [ ] Ads: **No**
  - [ ] App access: **All functionality available without special access** (anonymous sign-in)
  - [ ] Content rating: answers in `store/listing.md`
  - [ ] Target audience: answers in `store/listing.md`
  - [ ] Data safety: answers in `store/data-safety.md`, plus your deletion page URL
  - [ ] Location permissions + **video**: `store/declarations.md` (record the video on a real phone)
  - [ ] Foreground service (location) + same video: `store/declarations.md`
  - [ ] Government app: No. Financial features: None. Health: None.
- [ ] Upload the `.aab` to **Internal testing**, add your own email as a tester and install it from Play.
- [ ] New personal developer accounts must run a **closed test with at least 12 testers for 14 days** before production. Plan for it.
- [ ] Promote to **Production**, choose countries, then send for review.

## 9. App Store Connect

- [ ] Apple Developer Program ($99/year). In Certificates, IDs & Profiles, register the bundle ID with
      Push Notifications and Time Sensitive Notifications.
- [ ] Create the app in App Store Connect (name, bundle ID, SKU, primary language).
- [ ] **App Information**: category, age rating (answers in `store/listing.md`), privacy policy URL.
- [ ] **App Privacy**: answers in `store/data-safety.md`.
- [ ] **Version page**: subtitle, description, keywords, promo text (`store/listing.md`), support URL,
      screenshots `store/screenshots/iphone-6.7/*` (1290×2796, the size Apple currently requires).
- [ ] Upload the build (Xcode Organizer or Transporter), wait for processing, attach it to the version.
- [ ] **App Review notes**: `store/declarations.md`. No demo account is needed (anonymous sign-in).
- [ ] Optional: request the Critical Alerts entitlement (link in `store/declarations.md`).
- [ ] Submit for review.

## 10. After the first approved release

- [ ] Firebase → App Check → **Enforce** for Firestore, Cloud Functions and Authentication once the Crashlytics
      dashboard shows the store build in use. Older or modified builds are then refused.
- [ ] Watch Firebase → Crashlytics for the first week.

---

## Already done in code (no action needed)

- Release signing reads `android/key.properties`. The build falls back to the debug key only when it's missing.
- `isMonitoringTool=child_monitoring` manifest flag (Play stalkerware policy), persistent "sharing location"
  notification, no hidden mode, no microphone access.
- In-app prominent disclosure shown before the location permission request (`lib/ui/common/legal.dart`).
- In-app account deletion for parents and children, backed by the `deleteMyData` Cloud Function.
- Privacy policy, terms and support links in onboarding, settings and the child menu (`lib/config.dart`).
- Full-screen-intent permission deliberately **not** used (Play restricts it to alarm/calling apps).
- iOS: location usage strings, background modes, push + time-sensitive entitlements, privacy manifest
  (`PrivacyInfo.xcprivacy`), `ITSAppUsesNonExemptEncryption = NO`, iOS 15 minimum.
- 30-day automatic deletion of location history, alerts and view logs (`pruneHistory`).
- Security rules: role-bound invite codes, siblings can't see each other, children can't change their own
  privacy mode, points or places. Tested on the Firestore emulator (`firebase/rules-tests`, 19 tests).
- Cloud Functions tested on the emulators (`npm run test:emulator` in `firebase/functions`, 11 tests).
- Quiet hours and place schedules use the family's IANA time zone (handles daylight saving).
- A child phone that goes silent gets a "tap to turn sharing back on" push as well as alerting the parents.
- Crashlytics crash reporting and App Check (Play Integrity / App Attest) wired in. The privacy forms include crash data.
- Legal pages served by Firebase Hosting from `store/*.md`, with a deploy guard against unfilled placeholders.
- Release manifest audited (REA + apktool on the release APK): 13 permissions, none on Play's restricted list,
  monitoring flag and location foreground service present, not debuggable. Backups and device transfer are
  off so a child's session can't be copied off the phone. `scripts/check_manifest.py` re-checks every release
  build (local and Codemagic) so a plugin update can't silently add a restricted permission.
- App icon (all sizes, adaptive on Android), store screenshots and feature graphic. Swap in designer
  versions any time: replace `assets/icon/icon.png` + `icon_foreground.png`, then run `dart run flutter_launcher_icons`.

## Recommended before or soon after launch (not blockers)

- Translate the listing and in-app strings for your main markets.
- A designer-made icon and screenshots with captions (current ones are clean but plain).

## Verifying changes yourself

```bash
flutter analyze && flutter test                                  # app: 37 tests
cd firebase/functions && npm install && npm test                 # time-zone and alert policy
npm run test:emulator                                            # Cloud Functions on emulators (needs Java)
cd ../rules-tests && npm install && npm test                     # security rules on the emulator
```
