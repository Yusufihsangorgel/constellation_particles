import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:constellation_particles/constellation_particles.dart';

Widget _boxed(Widget child, {Size size = const Size(400, 300)}) => MaterialApp(
      home: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );

// The State type is private, so reach the getter through dynamic dispatch.
bool _pointerInside(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(ConstellationParticles));
  return state.isPointerInside as bool;
}

void main() {
  testWidgets('touchReactive: true engages repulsion on a touch',
      (tester) async {
    await tester
        .pumpWidget(_boxed(const ConstellationParticles(touchReactive: true)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_pointerInside(tester), isFalse);

    final center = tester.getCenter(find.byType(ConstellationParticles));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    expect(_pointerInside(tester), isTrue,
        reason: 'a touch-down should mark the pointer as inside');

    await gesture.moveTo(center + const Offset(10, 10));
    await tester.pump();
    expect(_pointerInside(tester), isTrue);

    await gesture.up();
    await tester.pump();
    expect(_pointerInside(tester), isFalse,
        reason: 'lifting the touch should release the pointer');
  });

  testWidgets('touchReactive: false ignores a touch', (tester) async {
    await tester.pumpWidget(_boxed(const ConstellationParticles()));
    await tester.pump(const Duration(milliseconds: 16));

    final center = tester.getCenter(find.byType(ConstellationParticles));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveTo(center + const Offset(10, 10));
    await tester.pump();

    expect(_pointerInside(tester), isFalse,
        reason: 'a touch must not drive repulsion when opt-in is off');

    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
