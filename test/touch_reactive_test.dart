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

Future<Uint8List> _fieldPixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.descendant(
      of: find.byType(ConstellationParticles),
      matching: find.byType(RepaintBoundary),
    ),
  );
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  image.dispose();
  return Uint8List.fromList(rgba);
}

void main() {
  testWidgets('touchReactive: true changes the painted field on touch', (
    tester,
  ) async {
    await tester.pumpWidget(
      _boxed(
        const ConstellationParticles(touchReactive: true, speed: 0, seed: 7),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final beforeTouch = await _fieldPixels(tester);

    final center = tester.getCenter(find.byType(ConstellationParticles));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final afterTouchDown = await _fieldPixels(tester);
    expect(afterTouchDown, isNot(equals(beforeTouch)));

    await gesture.moveTo(center + const Offset(120, 80));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final afterTouchMove = await _fieldPixels(tester);
    expect(afterTouchMove, isNot(equals(afterTouchDown)));

    await gesture.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(await _fieldPixels(tester), equals(afterTouchMove));
  });

  testWidgets('touchReactive: false ignores a touch', (tester) async {
    await tester.pumpWidget(
      _boxed(const ConstellationParticles(speed: 0, seed: 7)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final beforeTouch = await _fieldPixels(tester);

    final center = tester.getCenter(find.byType(ConstellationParticles));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final afterTouch = await _fieldPixels(tester);
    expect(afterTouch, equals(beforeTouch));

    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
