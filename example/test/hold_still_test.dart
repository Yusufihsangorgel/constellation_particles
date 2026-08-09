import 'package:constellation_particles/constellation_particles.dart';
import 'package:constellation_particles_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether anything is still driving frames. A drifting field keeps a ticker
/// scheduled; a held one does not.
bool get _isAnimating => SchedulerBinding.instance.transientCallbackCount > 0;

/// Flips the switch and lets its own thumb animation finish, which is a ticker
/// too and would otherwise be counted as the field still moving.
Future<void> _flipTheSwitch(WidgetTester tester) async {
  await tester.tap(find.byType(Switch));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('the field drifts until the switch is flipped', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump(const Duration(milliseconds: 16));
    expect(_isAnimating, isTrue);

    await _flipTheSwitch(tester);
    expect(_isAnimating, isFalse);
  });

  testWidgets('the constellation is still on screen while held', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await _flipTheSwitch(tester);

    // The distinction the switch exists to show. Motion stopped, and the
    // widget did not leave the tree or stop painting to achieve that.
    expect(find.byType(ConstellationParticles), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ConstellationParticles),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
    expect(find.text('the drift stopped, the field stayed'), findsOneWidget);
  });

  testWidgets('flipping it back starts the drift again', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await _flipTheSwitch(tester);
    expect(_isAnimating, isFalse);

    await _flipTheSwitch(tester);
    expect(_isAnimating, isTrue);
  });

  testWidgets('a platform request holds the field with the switch off', (
    tester,
  ) async {
    // What a user who has reduce-motion on in the OS gets before touching
    // anything. The switch reads off, and the field is held regardless.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(const ExampleApp());
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(_isAnimating, isFalse);
    expect(
      find.text(
          'your system already asks for it; the field is held either way'),
      findsOneWidget,
    );
  });
}
