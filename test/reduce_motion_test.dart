import 'package:constellation_particles/constellation_particles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool disableAnimations}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 300,
          height: 300,
          child: ConstellationParticles(particleCount: 30, seed: 7),
        ),
      ),
    );

/// Whether anything is still driving frames. A running particle simulation
/// keeps a ticker scheduled; a held one does not.
bool get _hasScheduledFrame =>
    SchedulerBinding.instance.hasScheduledFrame ||
    SchedulerBinding.instance.transientCallbackCount > 0;

void main() {
  testWidgets('with reduce motion off, the simulation keeps running', (
    tester,
  ) async {
    await tester.pumpWidget(_host(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_hasScheduledFrame, isTrue);
  });

  testWidgets('with reduce motion on, nothing keeps ticking', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 16));
    // The widget is still there and painted; it just is not moving.
    expect(find.byType(ConstellationParticles), findsOneWidget);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('the frame is still painted, not blanked', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 16));
    // A CustomPaint with the constellation painter is in the tree, so the
    // design survives; only the motion is gone.
    expect(
      find.descendant(
        of: find.byType(ConstellationParticles),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
  });

  testWidgets('turning reduce motion off starts the simulation again', (
    tester,
  ) async {
    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    await tester.pumpWidget(_host(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_hasScheduledFrame, isTrue);
  });

  testWidgets('turning reduce motion on stops a running simulation', (
    tester,
  ) async {
    await tester.pumpWidget(_host(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_hasScheduledFrame, isTrue);

    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('it stays out of the semantics tree either way', (tester) async {
    final handle = tester.ensureSemantics();
    for (final reduce in [false, true]) {
      await tester.pumpWidget(_host(disableAnimations: reduce));
      await tester.pump(const Duration(milliseconds: 16));
      // Decorative: a screen reader has nothing to say about it.
      expect(
        tester.getSemantics(find.byType(ConstellationParticles)).label,
        isEmpty,
      );
    }
    handle.dispose();
  });
}
