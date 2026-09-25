import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:constellation_particles/constellation_particles.dart';

Widget _boxed(Widget child, {Size size = const Size(400, 300)}) => MaterialApp(
      home: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );

Widget _frozenField(
  ConstellationParticles field, {
  Size size = const Size(400, 300),
}) =>
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: size.width, height: size.height, child: field),
        ),
      ),
    );

Future<Uint8List> _fieldPixels(
  WidgetTester tester, {
  Size expectedSize = const Size(400, 300),
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.descendant(
      of: find.byType(ConstellationParticles),
      matching: find.byType(RepaintBoundary),
    ),
  );
  expect(boundary.size, expectedSize);
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  image.dispose();
  return Uint8List.fromList(rgba);
}

class _ReferenceParticle {
  const _ReferenceParticle({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
  });

  final double x;
  final double y;
  final double radius;
  final double opacity;
}

class _ReferenceConnection {
  const _ReferenceConnection({
    required this.index,
    required this.cellX,
    required this.cellY,
    required this.distanceSquared,
  });

  final int index;
  final int cellX;
  final int cellY;
  final double distanceSquared;
}

// withValues was added after Flutter 3.24, which this package supports.
// ignore: deprecated_member_use
Color _withOpacity(Color color, double opacity) => color.withOpacity(opacity);

Future<({Uint8List pixels, int lineCount})> _allPairsReference({
  required Size size,
  required int count,
  required double connectionDistance,
  required int seed,
  required Color color,
}) async {
  final rng = math.Random(seed);
  final particles = List.generate(count, (_) {
    final x = rng.nextDouble() * size.width;
    final y = rng.nextDouble() * size.height;
    final vx = (rng.nextDouble() - 0.5) * 0.4;
    final vy = (rng.nextDouble() - 0.5) * 0.4;
    final radius = rng.nextDouble() * 1.5 + 0.5;
    final opacity = rng.nextDouble() * 0.4 + 0.1;
    return _ReferenceParticle(
      x: x + vx * 0.0,
      y: y + vy * 0.0,
      radius: radius,
      opacity: opacity,
    );
  });

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;
  final particlePaint = Paint();
  final glowPaint = Paint();
  final lineColor = _withOpacity(color, 0.08);
  var lineCount = 0;

  for (var i = 0; i < particles.length; i++) {
    final first = particles[i];
    final firstCellX = (first.x / connectionDistance).floor();
    final firstCellY = (first.y / connectionDistance).floor();
    final connections = <_ReferenceConnection>[];
    for (var j = i + 1; j < particles.length; j++) {
      final second = particles[j];
      final dx = first.x - second.x;
      final dy = first.y - second.y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < connectionDistance * connectionDistance) {
        connections.add(
          _ReferenceConnection(
            index: j,
            cellX: (second.x / connectionDistance).floor(),
            cellY: (second.y / connectionDistance).floor(),
            distanceSquared: distanceSquared,
          ),
        );
        lineCount++;
      }
    }
    connections.sort((first, second) {
      final firstCellOrder =
          (first.cellX - firstCellX + 1) * 3 + (first.cellY - firstCellY + 1);
      final secondCellOrder =
          (second.cellX - firstCellX + 1) * 3 + (second.cellY - firstCellY + 1);
      final cellComparison = firstCellOrder.compareTo(secondCellOrder);
      return cellComparison != 0
          ? cellComparison
          : first.index.compareTo(second.index);
    });
    for (final connection in connections) {
      final second = particles[connection.index];
      final distance = math.sqrt(connection.distanceSquared);
      final opacity = (1.0 - distance / connectionDistance) * 0.15;
      linePaint.color = _withOpacity(lineColor, opacity);
      canvas.drawLine(
        Offset(first.x, first.y),
        Offset(second.x, second.y),
        linePaint,
      );
    }
  }

  final particleColor = _withOpacity(color, 0.6);
  final glowStops = [_withOpacity(color, 0.05), const Color(0x00000000)];
  for (final particle in particles) {
    particlePaint.color = _withOpacity(particleColor, particle.opacity);
    canvas.drawCircle(
      Offset(particle.x, particle.y),
      particle.radius,
      particlePaint,
    );
    if (particle.radius > 1.2) {
      glowPaint.shader = ui.Gradient.radial(
        Offset(particle.x, particle.y),
        particle.radius * 4,
        glowStops,
      );
      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.radius * 4,
        glowPaint,
      );
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    size.width.round(),
    size.height.round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final pixels = Uint8List.fromList(rgba);
  image.dispose();
  picture.dispose();
  return (pixels: pixels, lineCount: lineCount);
}

void main() {
  testWidgets('renders a CustomPaint and advances without error', (
    tester,
  ) async {
    await tester.pumpWidget(_boxed(const ConstellationParticles()));
    expect(find.byType(ConstellationParticles), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Let the ticker run a few frames — a thrown exception here fails the test.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles an empty field', (tester) async {
    await tester.pumpWidget(
      _boxed(const ConstellationParticles(particleCount: 0)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilds when the particle count changes', (tester) async {
    await tester.pumpWidget(
      _boxed(const ConstellationParticles(particleCount: 40)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(
      _boxed(const ConstellationParticles(particleCount: 120)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilds the grid when connectionDistance grows', (
    tester,
  ) async {
    const size = Size(400, 300);
    const color = Color(0xFF64FFDA);
    const count = 100;
    const seed = 42;
    await tester.pumpWidget(
      _frozenField(
        const ConstellationParticles(
          particleCount: count,
          connectionDistance: 20,
          speed: 0,
          seed: seed,
          color: color,
        ),
        size: size,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      _frozenField(
        const ConstellationParticles(
          particleCount: count,
          connectionDistance: 120,
          speed: 0,
          seed: seed,
          color: color,
        ),
        size: size,
      ),
    );
    await tester.pump();

    final expected = await _allPairsReference(
      size: size,
      count: count,
      connectionDistance: 120,
      seed: seed,
      color: color,
    );
    expect(expected.lineCount, greaterThan(0));
    expect(
      await _fieldPixels(tester, expectedSize: size),
      orderedEquals(expected.pixels),
    );
  });

  testWidgets('reinitializes particles when seed changes', (tester) async {
    const size = Size(400, 300);
    const color = Color(0xFF64FFDA);
    const count = 60;
    await tester.pumpWidget(
      _frozenField(
        const ConstellationParticles(particleCount: count, speed: 0, seed: 3),
        size: size,
      ),
    );
    await tester.pump();
    final beforeSeedChange = await _fieldPixels(tester, expectedSize: size);

    await tester.pumpWidget(
      _frozenField(
        const ConstellationParticles(
          particleCount: count,
          speed: 0,
          seed: 19,
          color: color,
        ),
        size: size,
      ),
    );
    await tester.pump();

    final expected = await _allPairsReference(
      size: size,
      count: count,
      connectionDistance: 120,
      seed: 19,
      color: color,
    );
    final afterSeedChange = await _fieldPixels(tester, expectedSize: size);
    expect(afterSeedChange, orderedEquals(expected.pixels));
    expect(afterSeedChange, isNot(equals(beforeSeedChange)));
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
    expect(
      () => ConstellationParticles(speed: double.nan),
      throwsAssertionError,
    );
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
