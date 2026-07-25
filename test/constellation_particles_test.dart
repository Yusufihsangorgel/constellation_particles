import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:constellation_particles/constellation_particles.dart';

Widget _boxed(Widget child, {Size size = const Size(400, 300)}) => MaterialApp(
      home: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );

void main() {
  testWidgets('renders a CustomPaint and advances without error',
      (tester) async {
    await tester.pumpWidget(_boxed(const ConstellationParticles()));
    expect(find.byType(ConstellationParticles), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Let the ticker run a few frames — a thrown exception here fails the test.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles an empty field', (tester) async {
    await tester
        .pumpWidget(_boxed(const ConstellationParticles(particleCount: 0)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilds when the particle count changes', (tester) async {
    await tester
        .pumpWidget(_boxed(const ConstellationParticles(particleCount: 40)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester
        .pumpWidget(_boxed(const ConstellationParticles(particleCount: 120)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes cleanly', (tester) async {
    await tester.pumpWidget(_boxed(const ConstellationParticles()));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test('the physics multipliers reject NaN', () {
    // A NaN reached the spatial grid, whose cell index is an int, and threw
    // `Infinity or NaN toInt` out of both the ticker and paint() — once per
    // frame, for as long as the widget stayed alive.
    expect(() => ConstellationParticles(speed: double.nan), throwsAssertionError);
    expect(
      () => ConstellationParticles(repulsionRadius: double.nan),
      throwsAssertionError,
    );
    expect(
      () => ConstellationParticles(repulsionForce: double.nan),
      throwsAssertionError,
    );
    // Ordinary values, including the calibrated defaults, still build.
    expect(const ConstellationParticles(), isNotNull);
    expect(const ConstellationParticles(speed: 0), isNotNull);
    expect(const ConstellationParticles(speed: -1), isNotNull);
  });
}
