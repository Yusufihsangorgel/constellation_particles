# constellation_particles

Decorative motion is the first thing a reader turns off, and a particle
background that never asks keeps drifting anyway. This one holds still when the
platform requests reduced motion, and leaves the constellation on screen while
it does.

`example/lib/main.dart` puts that request behind a switch: flip it and the
points stop where they are, with the constellation still on screen.

![A dark phone screen with pale teal points drifting across it, each joined by a thin line to the neighbours near enough to reach.](https://raw.githubusercontent.com/Yusufihsangorgel/constellation_particles/main/doc/demo.gif)

## Why this instead of what you already have

**Instead of a bare `CustomPainter`.** It is an abstract class whose contract
is one method, `paint(Canvas, Size)` (`rendering/custom_paint.dart:149`), and
whose `semanticsBuilder` returns `null` until you write one
(`rendering/custom_paint.dart:222`). It hands you a canvas. Reduced motion,
high contrast, pausing when the app goes to the background, and keeping the
decoration out of the accessibility tree are all left to you.

**Instead of the existing particle packages.** `animated_background`,
`particle_field` and `particles_network` are genuinely animated packages, but a
case-insensitive search of each one's `lib/` finds no `disableAnimations`, no
`highContrast`, no `AppLifecycleState` and no `Semantics`. This package reads
`MediaQuery.maybeDisableAnimationsOf` and holds the field still with the
constellation on screen (`lib/constellation_particles.dart:138`), and stops the
clock when the app is hidden (`lib/constellation_particles.dart:164`). To be
fair about scale, all three draw under 4,000 downloads a month, so this is a
small corner of the ecosystem.

## Reach for it when

- A landing or sign-in screen wants a moving background that stops when the
  platform asks for reduced motion.
- The background must stop spending frames once the app is backgrounded.
- Screen readers should pass over the decoration instead of announcing it.

Skip it if a still gradient or image would do the job: even with those pauses,
this runs a simulation every frame while motion is allowed, and a static
background costs nothing.

Neighbour lookups run through a spatial hash grid: a particle's work is set by
how crowded its own neighbourhood is rather than by how many particles exist.

## Install

```sh
flutter pub add constellation_particles
```

## Use it

Drop it into a `Stack` behind your content and give it a bounded size.

```dart
Stack(
  children: [
    const Positioned.fill(child: ConstellationParticles()),
    yourContent,
  ],
)
```

## Tune it

Two parameters decide how the field reads. `particleCount` sets how many points
there are, and `connectionDistance` sets how far apart two of them can be and
still be joined.

```dart
ConstellationParticles(
  particleCount: 60,
  connectionDistance: 80,
  color: const Color(0xFF64FFDA),
)
```

![Four panels of the same particle field. Across each row the linking distance doubles and the mesh fills in; down each column the particle count rises from 60 to 200.](https://raw.githubusercontent.com/Yusufihsangorgel/constellation_particles/main/doc/params.webp)

Reach for `connectionDistance` before `particleCount`. The GPU draws one line
per link rather than one per particle, and raising the count multiplies links
quadratically: at the default distance, 400 particles is 3,563 links and 800 is
13,611.

## What the grid costs

Connecting-line fields usually decide which pairs to join by measuring every
particle against every other one. This one buckets particles into a grid whose
cell size equals the connection distance, which leaves a particle able to reach
only its own cell and the eight around it.

![Two log-log panels of distance checks per frame. On a fixed canvas both passes have slope 2 and the grid sits a constant distance below. On a growing canvas the grid falls to slope 1 while all-pairs stays at 2.](https://raw.githubusercontent.com/Yusufihsangorgel/constellation_particles/main/doc/benchmark.png)

The result splits in two, and only one half flatters the grid. On a canvas that
stays one size it removes about eight distance checks in nine and still runs
slower, because nine hash-map lookups per particle cost more than the
arithmetic they replaced. On a canvas that grows with the count the exponent
changes instead of the constant, and there the grid pass came out roughly five
times faster at 6400 particles.

Either way, at a few hundred particles on a normal window both passes take
microseconds. `example/frame_cost.dart` produces every number above, and
`example/README.md` has the tables, the hardware they were measured on, and the
AOT run that a Flutter release build actually uses.

## What it will not do

- It paints a background. No API attaches particles to widgets, emits them from
  a point, or reacts to the content in front of them.
- Touch is inert until you pass `touchReactive: true`. A field that grabbed
  pointers by default would swallow drags meant for your UI.
- `particleCount` is a request. High-contrast mode halves it.
- The measurements above cover the neighbour pass and nothing else. Whether the
  pass or the drawing is what costs you a frame is a question for a Flutter
  timeline.

## Alternatives

`animated_background` (311 likes), `particle_field` (143) and
`particles_network` (66) are all older and more widely used than this package.
Reading their published archives on 2026-08-09, none of the three mentions
`disableAnimations`, `highContrast` or `AppLifecycleState` anywhere, and none
puts a node into the semantics tree. Closing that gap is why this package was
written.

If you have accessibility covered elsewhere, `particles_network` is the one
worth looking at. Of the three it is the only one that avoids the all-pairs
scan, using a quadtree where this package uses a grid.

## Parameters

| Parameter            | Default     | Description                                             |
| -------------------- | ----------- | ------------------------------------------------------- |
| `particleCount`      | `100`       | Particles at full density; halved under high contrast.  |
| `color`              | `0xFF64FFDA`| Base colour; per-particle/line opacity derived from it. |
| `speed`              | `1.0`       | Drift-speed multiplier.                                 |
| `connectionDistance` | `120.0`     | Max link distance, also the grid cell size.             |
| `repulsionRadius`    | `200.0`     | Pointer influence radius.                               |
| `repulsionForce`     | `50.0`      | Pointer push strength.                                  |
| `seed`               | `42`        | Layout seed; fixed by default for reproducible fields.  |
| `touchReactive`      | `false`     | Let touches drive repulsion too, as well as the mouse.  |

The mouse drives repulsion on desktop and web with no configuration. Set
`touchReactive: true` when the particles are a foreground surface and you want
touches to push them around as well.

## What else it handles

- Pauses its ticker when the app is hidden or backgrounded.
- Halves the particle count when the platform requests high contrast.
- Caches its paints and the glow gradient, and repaints only after the
  simulation has actually advanced.
- Excludes itself from the semantics tree, being decoration.
- Renders inside a `RepaintBoundary`; your content stays out of its repaints.

## License

MIT © Yusuf İhsan Görgel
