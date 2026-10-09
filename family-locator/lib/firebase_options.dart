// Placeholder. Run `flutterfire configure` to replace this file with your
// Firebase project's settings, then build with --dart-define=BACKEND=firebase.
// Demo mode (the default) never reads it.

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
        'Firebase is not configured. Run `flutterfire configure`, or build '
        'without --dart-define=BACKEND=firebase to use demo mode.',
      );
}
