import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/alert_policy.dart';
import '../../core/models.dart';
import '../common/widgets.dart';
import 'parent_data.dart';

enum _Filter { all, safety, places, checkIns }

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  _Filter filter = _Filter.all;

  bool _matches(AlertEvent a) => switch (filter) {
        _Filter.all => true,
        _Filter.safety => a.urgent ||
            const {AlertType.sosCancelled, AlertType.lowBattery, AlertType.sharingPaused, AlertType.sharingResumed}
                .contains(a.type),
        _Filter.places => a.type == AlertType.arrived || a.type == AlertType.left,
        _Filter.checkIns => a.type == AlertType.checkIn || a.type == AlertType.signalAcknowledged,
      };

  @override
  Widget build(BuildContext context) {
    final d = context.watch<ParentData>();
    final scheme = Theme.of(context).colorScheme;
    final alerts = d.alerts.where(_matches).toList();
    final dayFmt = DateFormat.MMMEd();

    final rows = <Widget>[];
    DateTime? lastDay;
    for (final a in alerts) {
      if (lastDay == null || !DateUtils.isSameDay(lastDay, a.at)) {
        lastDay = a.at;
        rows.add(SectionTitle(DateUtils.isSameDay(a.at, DateTime.now()) ? 'Today' : dayFmt.format(a.at)));
      }
      final child = d.childById(a.childId);
      final delivery = decideDelivery(a, d.settings, zone: d.zones[a.zoneId]);
      rows.add(ListTile(
        leading: CircleAvatar(
          backgroundColor: a.urgent ? scheme.errorContainer : scheme.secondaryContainer,
          child: Icon(alertIcon(a.type), color: a.urgent ? scheme.error : scheme.onSecondaryContainer),
        ),
        title: Text(a.message),
        subtitle: Text([
          hm.format(a.at),
          if (child != null) '${child.emoji} ${child.name}',
          if (delivery == Delivery.feedOnly) 'outside alert hours, not notified',
          if (delivery == Delivery.digest) 'quiet hours, sent in summary',
        ].join(' · ')),
      ));
    }

    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Text('Alerts', style: Theme.of(context).textTheme.headlineSmall),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            for (final f in _Filter.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(switch (f) {
                    _Filter.all => 'All',
                    _Filter.safety => 'Safety',
                    _Filter.places => 'Places',
                    _Filter.checkIns => 'Check-ins',
                  }),
                  selected: filter == f,
                  onSelected: (_) => setState(() => filter = f),
                ),
              ),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Nothing here yet.'))
              : ListView(children: rows),
        ),
      ]),
    );
  }
}
