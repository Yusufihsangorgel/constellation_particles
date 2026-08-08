# constellation_particles

A pointer-reactive constellation particle field for Flutter. Particles drift,
wrap at the edges, repel from the pointer, and link up with fading lines when
they get close. No plugins, no shaders, no runtime dependencies beyond Flutter.

![demo](https://raw.githubusercontent.com/Yusufihsangorgel/constellation_particles/main/doc/demo.gif)

## Why this exists

Connecting-line particle fields are everywhere, and the neighbour pass is
usually O(n²): every frame, each particle is distance-checked against every
other one to decide whether to draw a line. At 100 particles that is ~5,000
checks a frame; at 800, 319,600.

That "usually" is counted rather than assumed. Searching pub.dev turns up eight
other packages that draw lines between nearby particles; in the versions current
in August 2026, seven of the eight do the full pairwise scan, and two of those
seven check every pair twice, drawing each line on top of itself. The exception
is `particles_network`, which queries a quadtree per particle — so the quadratic
pass is the norm in this category, not the whole of it.

This one buckets particles into a **spatial hash grid** whose cell size equals
the connection distance. A particle can only link to something in its own cell
or the eight around it, so each frame walks ~9 cells per particle instead of
the whole population. At 800 particles on a 1200x800 canvas that is 36,861
distance checks a frame instead of 319,600.

Fewer checks is not less time, though, and `example/frame_cost.dart` times both
passes over the same field rather than leaving that to the imagination. On a
canvas that stays 1200x800 while the count rises, the grid pass is the *slower*
of the two at every count the script tries: its own bookkeeping — a fresh
candidate list per particle, nine map lookups, a rebuild every frame — costs
more than the distance arithmetic it skips. Where the grid does pay is a canvas
that grows with the count, which is where its advantage is a change of shape
rather than a constant factor: 6400 particles on 9600x6400 came out about 5x
faster than every pair.

Either way, at a few hundred particles both passes are microseconds rather than
milliseconds, so neither is what would cost you a frame. The quantity to size
is the number of *lines* — 400 particles is 3,563 links, 800 is 13,611, and
each one is a `drawLine` with its own colour. That is the part the script does
not measure and a Flutter timeline does. `example/README.md` has the tables,
including the AOT run, which is the mode a Flutter release build gets.

A couple of other things it does so you don't have to:

- **Pauses** its ticker when the app is hidden or backgrounded.
- **Holds still** when the platform asks for reduced motion: the constellation
  is painted, but nothing drifts. Drifting particles in the background are the
  kind of motion that setting exists to stop, and honouring it should not mean
  the design disappears.
- **Halves** the particle count when the platform requests high contrast.
- Caches paints and the glow gradient, and only repaints when the simulation
  actually advanced (`shouldRepaint` gates on a generation counter).
- Excludes itself from the semantics tree; it's decoration, not content.

## Install

```sh
flutter pub add constellation_particles
```

## Usage

Drop it into a `Stack` behind your content and give it a bounded size:

```dart
Stack(
  children: [
    const Positioned.fill(
      child: ConstellationParticles(),
    ),
    yourContent,
  ],
)
```

Tune it:

```dart
ConstellationParticles(
  particleCount: 160,
  color: const Color(0xFF64FFDA),
  speed: 1.2,
  connectionDistance: 140,
  repulsionRadius: 220,
)
```

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
| `touchReactive`      | `false`     | Let touches drive repulsion too, not just the mouse.    |

## Notes

- The mouse cursor drives repulsion on desktop and web out of the box. On
  touch the field just drifts by default, which is the right call for a
  background: turning it on would let the widget swallow drags meant for your
  content. Set `touchReactive: true` when the particles are a foreground
  surface and you want touches to push them around too.
- It renders into a `RepaintBoundary`, so it won't drag your content into its
  repaints.

## License

MIT © Yusuf İhsan Görgel
