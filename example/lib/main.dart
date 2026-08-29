import 'package:constellation_particles/constellation_particles.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const FieldPage(),
    );
  }
}

/// A 140-particle field, with a switch that asks it to hold still.
///
/// Reduced motion is the behaviour worth seeing before you adopt this widget,
/// and reaching it through the OS accessibility panel takes you out of the
/// app. The switch puts the same request in front of the field instead. Flip
/// it and watch what the field does with it: the points stop drifting and stay
/// where they are. The background does not disappear, which is what makes this
/// different from hiding the widget when motion is unwelcome.
class FieldPage extends StatefulWidget {
  const FieldPage({super.key});

  @override
  State<FieldPage> createState() => _FieldPageState();
}

class _FieldPageState extends State<FieldPage> {
  bool _askForStillness = false;

  @override
  Widget build(BuildContext context) {
    final platformAsked = MediaQuery.disableAnimationsOf(context);

    // Or-ed with the platform rather than replacing it. The switch can only
    // add the request: if you already have reduce-motion on in the OS, turning
    // this one off leaves the field held, because an app has no business
    // overriding that setting downwards.
    final holdStill = platformAsked || _askForStillness;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: Stack(
        children: [
          Positioned.fill(
            // The override wraps the field alone. Applied to the whole page it
            // would hold the switch's own thumb still as well, and the control
            // you are experimenting with would stop responding to you.
            child: MediaQuery(
              data:
                  MediaQuery.of(context).copyWith(disableAnimations: holdStill),
              child: const ConstellationParticles(
                particleCount: 140,
                color: Color(0xFF64FFDA),
                speed: 1.1,
              ),
            ),
          ),
          Center(
            child: Text(
              holdStill
                  ? 'the drift stopped, the field stayed'
                  : 'move your cursor',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white24, letterSpacing: 2),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _StillnessControl(
                  value: _askForStillness,
                  platformAsked: platformAsked,
                  onChanged: (v) => setState(() => _askForStillness = v),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StillnessControl extends StatelessWidget {
  const _StillnessControl({
    required this.value,
    required this.platformAsked,
    required this.onChanged,
  });

  final bool value;
  final bool platformAsked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: value, onChanged: onChanged),
            const SizedBox(width: 12),
            Text(
              'ask for reduced motion',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white54),
            ),
          ],
        ),
        if (platformAsked)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'your system already asks for it; the field is held either way',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white24),
            ),
          ),
      ],
    );
  }
}
