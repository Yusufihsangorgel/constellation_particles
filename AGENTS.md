# constellation_particles

## Purpose

`ConstellationParticles` paints a drifting constellation of points and
linking lines as a background. The mouse pushes particles away; touch
does not, until `touchReactive` is set.

Write the painter yourself when the job is only the drawing. A short
`CustomPainter` is a reasonable answer, and a dependency is a real cost;
taking this package for thirty lines of paint, with no accessibility or
lifecycle requirement, makes the project worse. What a hand-rolled
painter usually omits: the field holds still under reduced motion
without vanishing, halves `particleCount` under high contrast, stops its
ticker when the app is hidden or paused, and stays out of the semantics
tree.

## Usage

From `example/lib/main.dart`. Sit it in a `Stack` behind content, bounded
by `Positioned.fill`:

```dart
import 'package:constellation_particles/constellation_particles.dart';
import 'package:flutter/material.dart';

Stack(
  children: [
    const Positioned.fill(
      child: ConstellationParticles(
        particleCount: 140,
        color: Color(0xFF64FFDA),
        speed: 1.1,
      ),
    ),
    const Center(child: Text('move your cursor')),
  ],
)
```

## Contracts

**Parent bounds.** `build` uses a `LayoutBuilder`. It takes
`Size(constraints.maxWidth, constraints.maxHeight)` and paints that
box. Those must be finite: `Positioned.fill` in a `Stack`, a
`SizedBox`, or a `Scaffold` body. It does not size itself. Paint lives
inside `IgnorePointer` and `RepaintBoundary`; `MouseRegion` (and, if
opted in, `Listener`) sit outside the ignore so hover still works.

**Reduced motion — `MediaQuery.maybeDisableAnimationsOf`.** The widget
does not hide. It stops the `AnimationController` and keeps
`CustomPaint` in the tree, so the constellation stays on screen where it
is. Clearing the setting calls `repeat()` again.

**High contrast — `MediaQuery.maybeHighContrastOf`.** The field still
paints. Effective count is `(particleCount * 0.5).round()`.
`particleCount` is a request, not a guarantee.

**Ticker — `didChangeAppLifecycleState`.** Stops on
`AppLifecycleState.paused` and `AppLifecycleState.hidden`. Restarts on
`AppLifecycleState.resumed` only when reduced motion is off. Dispose
removes the `WidgetsBindingObserver` and disposes the controller.

**Semantics — `ExcludeSemantics`.** Decorative. A screen reader gets an
empty label whether the field is moving or held.

**Cost — `particleCount`, `connectionDistance`.** The GPU draws one
`drawLine` per link, not per particle; at a fixed canvas and distance,
links grow roughly with the square of the count. On a 1200×800 canvas at
the default `connectionDistance` of 120, `example/frame_cost.dart` counts
3,563 links at 400 particles and 13,611 at 800. Raise
`connectionDistance` before `particleCount`. Neighbour lookup uses a
spatial grid whose cell size is `connectionDistance`; fewer distance
checks is not the same as a cheaper frame.

## Mistakes

- **Unbounded constraints.** Parent `maxWidth` or `maxHeight` is
  infinite, so `CustomPaint` is given that `size`. Symptom: Flutter
  asserts an infinite size during layout. Fix: `Positioned.fill` in a
  `Stack` (`example/lib/main.dart`), or `SizedBox` (`test/`).
- **Large `particleCount` without measuring.** Symptom: dropped frames;
  800 particles at default distance is 13,611 `drawLine` calls a frame.
  Fix: keep the count in the low hundreds, raise `connectionDistance`
  first, run `cd example && dart run frame_cost.dart` for the neighbour
  pass, and a Flutter timeline for draw cost.
- **Guarding the widget with `disableAnimations`.** Symptom: the
  background disappears when the platform asks for less motion. Fix:
  leave it mounted; it already holds the frame and stops the ticker.
- **`touchReactive: true` behind tappable UI.** Symptom: the field
  swallows drags. Fix: leave the default `false`; set it only for a
  foreground surface.
- **Asserting `particleCount` particles under high contrast.** Symptom:
  the population is half. Fix: treat the parameter as a request.

## Layout

- `lib/constellation_particles.dart` — public API:
  `ConstellationParticles`
- `test/` — `flutter test` (`reduce_motion_test.dart`,
  `shrinking_population_test.dart`, `touch_reactive_test.dart`,
  `constellation_particles_test.dart`)
- `example/lib/main.dart` — demo
- `example/test/hold_still_test.dart` — example widget test
- `example/frame_cost.dart` — neighbour-pass cost
- `tool/` — README figures, not the library

```sh
flutter test
cd example && flutter test
cd example && flutter run
cd example && dart run frame_cost.dart
# AOT (the mode a release build uses):
cd example && dart compile exe frame_cost.dart -o frame_cost && ./frame_cost
```

## Contributing

Before changing this repository, read [CONTRIBUTING.md](CONTRIBUTING.md), [package engineering rules](docs/engineering/package.md), and the [debt register](docs/engineering/debt.json). These requirements apply to every contributor. The usage guidance above remains the consumer contract.
