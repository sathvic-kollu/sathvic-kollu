// Store-facing settings. Everything here can be overridden at build time
// with --dart-define, so release builds don't need code edits:
//
//   flutter build appbundle --dart-define=BACKEND=firebase \
//     --dart-define=PRIVACY_URL=https://example.com/privacy \
//     --dart-define=SUPPORT_EMAIL=help@example.com
//
// See STORE_SUBMISSION.md for what each value is used for.

const privacyPolicyUrl = String.fromEnvironment(
  'PRIVACY_URL',
  defaultValue: 'https://example.com/family-locator/privacy', // TODO(store): your hosted privacy policy
);

const termsUrl = String.fromEnvironment(
  'TERMS_URL',
  defaultValue: 'https://example.com/family-locator/terms', // TODO(store): your hosted terms
);

const supportEmail = String.fromEnvironment(
  'SUPPORT_EMAIL',
  defaultValue: 'support@example.com', // TODO(store): a monitored support inbox
);

/// Map tiles. The public OpenStreetMap server is for development only, so
/// release builds should pass a provider URL with your key, e.g. MapTiler:
/// https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=YOUR_KEY
const tileUrl = String.fromEnvironment(
  'TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const tileAttribution = String.fromEnvironment(
  'TILE_ATTRIBUTION',
  defaultValue: 'OpenStreetMap contributors',
);
