import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models.dart';
import '../common/legal.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, parent, join }

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step step = _Step.welcome;
  final _name = TextEditingController();
  final _code = TextEditingController();
  Role joinRole = Role.child;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Please enter a name.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (step == _Step.parent) {
        await app.createFamily(name);
      } else {
        await app.join(_code.text, name, joinRole);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text('👨‍👩‍👧', style: theme.textTheme.displayMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Family Locator',
                    style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Know they got there safely, without spying on them. '
                  'Core safety features are free: no ads, no paywall on SOS or places.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (app.isDemo) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.tertiaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Demo mode: everything stays on this phone. Creating a family adds two '
                        'sample kids, one of them walking between home, school and football.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ...switch (step) {
                  _Step.welcome => _welcome(),
                  _Step.parent => _form(parent: true),
                  _Step.join => _form(parent: false),
                },
                const SizedBox(height: 16),
                const LegalLinks(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _welcome() => [
        FilledButton.icon(
          onPressed: () => setState(() => step = _Step.parent),
          icon: const Icon(Icons.family_restroom),
          label: const Text("I'm a parent: set up my family"),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() => step = _Step.join),
          icon: const Icon(Icons.qr_code),
          label: const Text('I have a family code'),
        ),
      ];

  List<Widget> _form({required bool parent}) => [
        if (!parent) ...[
          SegmentedButton<Role>(
            segments: const [
              ButtonSegment(value: Role.child, label: Text("I'm the child"), icon: Icon(Icons.child_care)),
              ButtonSegment(value: Role.parent, label: Text("I'm a guardian"), icon: Icon(Icons.person)),
            ],
            selected: {joinRole},
            onSelectionChanged: (s) => setState(() => joinRole = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Family code',
              helperText: 'Six letters, shown in the parent app under Settings → Add family member',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: parent || joinRole == Role.parent ? 'Your name (e.g. Mum)' : 'Your first name',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (!parent && joinRole == Role.child) ...[
          const SizedBox(height: 12),
          const Text(
            'Your family will see what this phone shares. You will always see what that is, '
            'who looked, and you can pause sharing. SOS always works.',
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(parent ? 'Create family' : 'Join family'),
        ),
        TextButton(onPressed: () => setState(() => step = _Step.welcome), child: const Text('Back')),
      ];
}
