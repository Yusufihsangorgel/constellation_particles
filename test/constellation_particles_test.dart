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
}
