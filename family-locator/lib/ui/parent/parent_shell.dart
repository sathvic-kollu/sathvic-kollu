import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models.dart';
import 'alerts_tab.dart';
import 'map_tab.dart';
import 'parent_data.dart';
import 'settings_tab.dart';
import 'tasks_tab.dart';

class ParentShell extends StatefulWidget {
  const ParentShell({super.key, required this.session});

  final Session session;

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final backend = context.read<AppState>().backend;
    return ChangeNotifierProvider(
      create: (_) => ParentData(backend, widget.session),
      child: Builder(builder: (context) {
        final data = context.watch<ParentData>();
        final sos = data.children.where((c) => c.sosActiveSince != null).toList();
        final unreadUrgent = data.alerts.take(20).where((a) => a.urgent).length;
        return Scaffold(
          body: Column(children: [
            if (sos.isNotEmpty) _SosBanner(children: sos, onTap: () => setState(() => tab = 0)),
            Expanded(
              child: IndexedStack(index: tab, children: const [
                MapTab(),
                AlertsTab(),
                TasksTab(),
                SettingsTab(),
              ]),
            ),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Family'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unreadUrgent > 0,
                  label: Text('$unreadUrgent'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: const Icon(Icons.notifications),
                label: 'Alerts',
              ),
              const NavigationDestination(icon: Icon(Icons.star_outline), selectedIcon: Icon(Icons.star), label: 'Tasks'),
              const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      }),
    );
  }
}

class _SosBanner extends StatelessWidget {
  const _SosBanner({required this.children, required this.onTap});

  final List<ChildProfile> children;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.error,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          onTap: onTap,
          leading: Icon(Icons.sos, color: scheme.onError, size: 32),
          title: Text(
            '${children.map((c) => c.name).join(', ')} pressed SOS',
            style: TextStyle(color: scheme.onError, fontWeight: FontWeight.bold),
          ),
          subtitle: Text('Live location is on. Tap to see the map.', style: TextStyle(color: scheme.onError)),
        ),
      ),
    );
  }
}
