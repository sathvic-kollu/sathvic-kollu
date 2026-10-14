# Privacy forms: ready-to-copy answers

These match what the code does (see `lib/data/firestore_backend.dart`, `firebase/functions/src/index.ts`).
Crash reporting (Firebase Crashlytics) is included and covered below. If you add analytics later,
update both forms.

## Google Play: Data safety

**Does your app collect or share any of the required user data types?** Yes
**Is all of the user data collected by your app encrypted in transit?** Yes
**Do you provide a way for users to request that their data is deleted?** Yes. In-app, plus the URL of your hosted `store/delete-account.md`.

| Data type | Collected | Shared* | Optional? | Purposes |
| --- | --- | --- | --- | --- |
| Location → Precise location | Yes | No | Required (core function) | App functionality |
| Location → Approximate location | Yes | No | Required | App functionality |
| Personal info → Name | Yes | No | Required | App functionality, Account management |
| Personal info → User IDs | Yes | No | Required | App functionality, Account management |
| Messages → Other in-app messages (check-ins) | Yes | No | Optional | App functionality |
| App activity → Other user-generated content (places, tasks) | Yes | No | Optional | App functionality |
| Device or other IDs (push token, Crashlytics installation ID) | Yes | No | Required | App functionality, Analytics |
| App info and performance → Crash logs | Yes | No | Required | Analytics (stability) |
| App info and performance → Diagnostics | Yes | No | Required | Analytics (stability) |

\* "Shared" in Play's sense means transferred to a third party. Data shown to other members of the
user's own family, and data processed by Firebase as your service provider, does **not** count as sharing.

Ephemeral processing: No. Data is stored.

**Advertising ID** (Play Console → App content → Advertising ID): **No**, the app doesn't use it.
The release manifest has no `AD_ID` permission; `scripts/check_manifest.py` fails the build if a
plugin ever adds one.

## Apple: App Privacy ("nutrition label")

**Data used to track you:** None.

**Data linked to you** (all for *App Functionality*):
- Location: Precise Location, Coarse Location
- Contact Info: Name
- Identifiers: User ID, Device ID (push token)
- User Content: Other User Content (check-ins, places, tasks)

**Data not linked to you** (for *App Functionality* and *Analytics*):
- Diagnostics: Crash Data

This matches `ios/Runner/PrivacyInfo.xcprivacy`.
