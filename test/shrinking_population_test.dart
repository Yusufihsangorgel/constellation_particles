import 'package:constellation_particles/constellation_particles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required int particleCount, bool highContrast = false}) =>
    MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 400,
          child: ConstellationParticles(particleCount: particleCount, seed: 3),
        ),
      ),
    );

void main() {
  testWidgets(
      'surviving a particleCount drop after the grid has been populated',
      (tester) async {
    await tester.pumpWidget(_host(particleCount: 300));
    // Run enough ticks that the spatial grid fills with indices up to 299.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);

    // Shrinking the population used to leave the grid holding indices past
    // the end of the new, shorter particle list; the very next paint threw
    // a RangeError.
    await tester.pumpWidget(_host(particleCount: 60));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'surviving high contrast halving the population after the grid has been populated',
      (tester) async {
    await tester.pumpWidget(_host(particleCount: 200));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);

    // The high-contrast path halves the count through didChangeDependencies
    // rather than a particleCount change, and hit the same stale-grid bug.
    await tester.pumpWidget(_host(particleCount: 200, highContrast: true));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });
}
