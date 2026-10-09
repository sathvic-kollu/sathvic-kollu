import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';

Future<void> openLink(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

Future<void> emailSupport() => launchUrl(Uri(scheme: 'mailto', path: supportEmail, queryParameters: {
      'subject': 'Family Locator',
    }));

/// "Privacy policy · Terms" footer used on onboarding and settings.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(onPressed: () => openLink(privacyPolicyUrl), child: const Text('Privacy policy')),
          TextButton(onPressed: () => openLink(termsUrl), child: const Text('Terms')),
        ],
      );
}

/// Google Play's "prominent disclosure": shown in-app, before the system
/// permission prompt, saying what is collected, that it happens in the
/// background, and why. The wording follows Play's required pattern.
Future<bool> showLocationDisclosure(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.share_location, size: 40),
      title: const Text('Share your location with your family'),
      content: const SingleChildScrollView(
        child: Text(
          'Family Locator collects location data to show your family where you are, alert them '
          'when you arrive at or leave places they saved (like home or school), and send your '
          'position with an SOS, even when the app is closed or not in use.\n\n'
          'Your location is only shared with the family members you joined. It is never sold or '
          'used for ads. Route history is deleted after 30 days.\n\n'
          'You can always see what is shared, see who looked, and pause sharing. A notification '
          'stays visible whenever sharing is on.\n\n'
          'On the next screen, choose "Allow all the time" so arrival alerts and SOS keep working.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
      ],
    ),
  );
  return ok ?? false;
}

/// Disclosure → foreground permission → background ("all the time").
Future<void> requestLocationWithDisclosure(BuildContext context) async {
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.always) return;
  if (!context.mounted || !await showLocationDisclosure(context)) return;
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  // Android 11+ and iOS ask for "always" as a second step.
  if (p == LocationPermission.whileInUse) p = await Geolocator.requestPermission();
  if (p != LocationPermission.always) await Geolocator.openAppSettings();
}

Future<bool> confirmDeletion(BuildContext context, {required bool child}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(child ? 'Delete my data and leave?' : 'Delete my account?'),
      content: Text(child
          ? 'This permanently deletes your location history, check-ins, alerts and profile, and '
              'removes this phone from the family. Your family is no longer able to see where you are.'
          : 'This permanently deletes your account. If you are the last parent, the whole family '
              "is deleted too, including every child's location history. This can't be undone."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
