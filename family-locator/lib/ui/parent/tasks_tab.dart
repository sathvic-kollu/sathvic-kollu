import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ids.dart';
import '../../core/models.dart';
import '../common/widgets.dart';
import 'parent_data.dart';

class TasksTab extends StatelessWidget {
  const TasksTab({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<ParentData>();
    return Scaffold(
      floatingActionButton: d.children.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add_task),
              label: const Text('New task'),
            ),
      body: SafeArea(
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Tasks & rewards', style: Theme.of(context).textTheme.headlineSmall),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Kids earn points for jobs you approve. You decide what points are worth.'),
          ),
          for (final c in d.children) ...[
            SectionTitle('${c.emoji} ${c.name} · ${c.points} points'),
            ...d.tasks.where((t) => t.childId == c.id && t.status != TaskStatus.approved).map(
                  (t) => ListTile(
                    leading: Icon(
                      t.status == TaskStatus.done ? Icons.hourglass_top : Icons.radio_button_unchecked,
                    ),
                    title: Text(t.title),
                    subtitle: Text(
                        '${t.points} points${t.status == TaskStatus.done ? ' · done, waiting for you' : ''}'),
                    trailing: t.status == TaskStatus.done
                        ? FilledButton(
                            onPressed: () => runGuarded(context, () => d.backend.approveTask(d.familyId, t),
                                success: '${c.name} earned ${t.points} points'),
                            child: const Text('Approve'),
                          )
                        : IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.close),
                            onPressed: () => d.backend.deleteTask(d.familyId, t.id),
                          ),
                  ),
                ),
            if (!d.tasks.any((t) => t.childId == c.id && t.status != TaskStatus.approved))
              const ListTile(dense: true, title: Text('No open tasks.')),
          ],
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final d = context.read<ParentData>();
    final title = TextEditingController();
    var points = 10;
    var childId = d.children.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New task'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: childId,
              decoration: const InputDecoration(labelText: 'For'),
              items: [
                for (final c in d.children) DropdownMenuItem(value: c.id, child: Text('${c.emoji} ${c.name}')),
              ],
              onChanged: (v) => setState(() => childId = v ?? childId),
            ),
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Task'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Points'),
              Expanded(
                child: Slider(
                  min: 5,
                  max: 50,
                  divisions: 9,
                  label: '$points',
                  value: points.toDouble(),
                  onChanged: (v) => setState(() => points = v.round()),
                ),
              ),
              Text('$points'),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      await d.backend.saveTask(
        d.familyId,
        FamilyTask(id: newId(), childId: childId, title: title.text.trim(), points: points),
      );
    }
    title.dispose();
  }
}
