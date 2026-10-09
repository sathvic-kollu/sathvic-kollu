import 'dart:ui';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/models.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/firestore_backend.dart';
import 'firebase_options.dart';
import 'services/platform_services.dart';
import 'ui/child/child_home.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/parent/parent_shell.dart';

/// `flutter run` → demo mode. `flutter run --dart-define=BACKEND=firebase`
/// after `flutterfire configure` → real sync between phones.
const backendKind = String.fromEnvironment('BACKEND', defaultValue: 'demo');

@pragma('vm:entry-point')
Future<void> _onBackgroundPush(RemoteMessage message) async {
  // A "ring" push wakes the child phone even if the app was killed.
  if (message.data['type'] == 'ring') {
    await Notifier.instance.show(
      '🔔 ${message.data['from'] ?? 'Your parent'} is calling you',
      'Open the app and tap "I hear you".',
      urgent: true,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final FamilyBackend backend;
  if (backendKind == 'firebase') {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Proves requests come from the genuine app (enforce it in the Firebase
    // console once the release build is live). Debug builds use debug tokens.
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    // Crash reports (no location or names) so failures in the field are seen.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    FirebaseMessaging.onBackgroundMessage(_onBackgroundPush);
    backend = FirestoreBackend();
  } else {
    backend = DemoBackend();
  }
  await Notifier.instance.init();
  final state = AppState(backend);
  runApp(ChangeNotifierProvider.value(value: state, child: const FamilyLocatorApp()));
  await state.init();
}

class FamilyLocatorApp extends StatelessWidget {
  const FamilyLocatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'Family Locator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final s = app.session;
    if (s == null) return const OnboardingScreen();
    if (s.role == Role.child && app.child != null) {
      return ChangeNotifierProvider.value(value: app.child!, child: const ChildHome());
    }
    return ParentShell(key: ValueKey(s.memberId), session: s);
  }
}
