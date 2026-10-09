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
- [ ] Enable **Authentication → Anonymous**, **Firestore** (production mode), **Cloud Messaging**.
- [ ] Upgrade to the **Blaze** plan (Cloud Functions need it; the free tier covers a small user base).
- [ ] `dart pub global activate flutterfire_cli && flutterfire configure`, choosing the Android + iOS apps
      with your package/bundle ID. This **replaces `lib/firebase_options.dart`**. Commit it.
- [ ] iOS push: Apple Developer → Keys → create an **APNs key** (.p8), then upload it in
      Firebase → Project settings → Cloud Messaging → Apple app.
- [ ] Deploy: `cd firebase && firebase use <project-id> && npm --prefix functions install && firebase deploy`.
      This deploys rules, indexes and the functions `onAlertCreated`, `onCommandCreated`, `checkStalePhones`,
      `pruneHistory` and `deleteMyData`.

## 3. Map tiles (10 min)

- [ ] Create a free key at a tile provider (e.g. https://cloud.maptiler.com, Stadia, Mapbox). The public
      OpenStreetMap server is not allowed for production apps.

## 4. Legal pages (≈30 min)

- [ ] Fill every `[BRACKETED]` value in `store/privacy-policy.md`, `store/terms.md`, `store/delete-account.md`.
- [ ] Host all three publicly (GitHub Pages / Notion / your site) and note the three URLs.
- [ ] Set up a monitored support inbox.

## 5. Release config (2 min)

- [ ] `cp config/release.example.json config/release.json` (git-ignored) and fill:
      `PRIVACY_URL`, `TERMS_URL`, `SUPPORT_EMAIL`, `TILE_URL` (with your key), `TILE_ATTRIBUTION`.

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
- App icon (all sizes, adaptive on Android), store screenshots and feature graphic. Swap in designer
  versions any time: replace `assets/icon/icon.png` + `icon_foreground.png`, then run `dart run flutter_launcher_icons`.

## Recommended before or soon after launch (not blockers)

- Crash reporting (Firebase Crashlytics). If you add it, update `store/data-safety.md` (Crash logs, Diagnostics).
- Translate the listing and in-app strings for your main markets.
- Store the family's IANA time zone instead of a UTC offset (see README → Time zones).
- Firebase App Check to block API abuse.
