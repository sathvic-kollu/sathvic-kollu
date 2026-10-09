import 'package:intl/intl.dart';

import 'models.dart';

enum Delivery {
  /// Push notification right away.
  now,

  /// Hold until quiet hours end, then send one summary.
  digest,

  /// Keep in the alert feed only; no notification.
  feedOnly,
}

/// Decides whether an alert interrupts the parent. The fix for
/// "geofence alerts are overkill": zone alerts respect the zone's own
/// schedule and the family's quiet hours, while safety alerts never wait.
Delivery decideDelivery(AlertEvent e, FamilySettings settings, {Zone? zone}) {
  if (e.urgent) return Delivery.now;
  if ((e.type == AlertType.arrived || e.type == AlertType.left) &&
      zone?.alertWindow != null &&
      !zone!.alertWindow!.contains(e.at)) {
    return Delivery.feedOnly;
  }
  final quiet = settings.quietHours;
  if (quiet != null && quiet.contains(e.at)) return Delivery.digest;
  return Delivery.now;
}

/// One notification body summarising alerts held during quiet hours.
String digestSummary(List<AlertEvent> held) {
  if (held.isEmpty) return '';
  final fmt = DateFormat.Hm();
  final sorted = [...held]..sort((a, b) => a.at.compareTo(b.at));
  final lines = sorted
      .map((e) => '${fmt.format(e.at)} ${e.message}')
      .take(6)
      .toList();
  final more = sorted.length - lines.length;
  return [
    '${held.length} update${held.length == 1 ? '' : 's'} during quiet hours:',
    ...lines,
    if (more > 0) '…and $more more',
  ].join('\n');
}
