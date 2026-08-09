## 1.0.1

No library code changed in this release. `lib/` is byte-identical to 1.0.0.

- The description led with the spatial grid. It now leads with the behaviours
  the neighbouring packages do not have: the field holds still under reduced
  motion, halves its population under high contrast, and stops its ticker in
  the background. A new "Alternatives" section carries the comparison, checked
  against the published archives of animated_background 2.0.0, particle_field
  1.0.0 and particles_network 1.9.5 on 2026-08-09: none of the three mentions
  `disableAnimations`, `highContrast` or `AppLifecycleState`.
- Two figures join the package page as screenshots, each drawn by a committed
  tool: a four-panel grid of what `particleCount` and `connectionDistance` each
  change (`tool/param_grid.dart`), and a log-log chart of distance checks per
  frame (`tool/benchmark_chart.dart`).
- The grid was sold as "near-O(n)", and on a canvas that stays one size the
  measurements do not support that. A new "What the grid costs" section says
  what they do support, and `example/frame_cost.dart` produces every number in
  it: at 800 particles on a fixed 1200x800 canvas the grid makes 36,861
  distance checks where the all-pairs pass makes 319,600, and its wall clock is
  still the slower of the two, because nine hash-map lookups per particle cost
  more than the arithmetic they replace. On a canvas that grows with the count
  the exponent drops instead of the constant, and the grid pass came out
  roughly fivefold faster at 6,400 particles. The check columns are seeded and
  reproduce exactly; the time columns are one laptop's.
- A "What it will not do" section states the boundaries: it paints a
  background, touch is inert until `touchReactive: true`, and `particleCount`
  is a request that high-contrast mode halves.
- The demo gif is out of the archive and out of `screenshots:`. The README
  still opens with it, and pub.dev serves README images from GitHub rather than
  from the archive. With the two figures in and the gif out, the download drops
  from 1895 KB to 146 KB.
- `flutter_lints` 5 to 6 in dev dependencies.

## 1.0.0

First stable release. The API below is what 1.0 freezes.

- **Fix a per-frame exception storm from a NaN multiplier.** `particleCount`
  and `connectionDistance` were asserted; `speed`, `repulsionRadius` and
  `repulsionForce` were not. All three reach the spatial grid, whose cell index
  is an `int`, so a NaN threw `Unsupported operation: Infinity or NaN toInt`
  out of both the animation ticker and `paint()` — not once, but on every frame
  for as long as the widget lived. All three now assert, written as
  comparisons rather than `isFinite` because the constructor is `const` and a
  property access is not a constant expression.

Checked and unchanged for this release, by running each rather than reading for
it: infinite and negative `speed`, negative and NaN `repulsionRadius` and
`repulsionForce` before the assert, a `connectionDistance` of 1e-9 and of 1e9,
`particleCount` of 0 and 1, a zero-size viewport, and `particleCount` churned
200 → 0 → 200 → 5 across consecutive frames. None misbehaved.

## 0.3.1

- Fix a `RangeError` that could crash the painter when the particle count
  drops after the spatial grid has been built. The grid is only rebuilt on
  the next animation tick, so shrinking `particleCount` at runtime, or the
  platform switching on high contrast (which halves the count on its own),
  could leave the grid holding indices from the larger, previous population
  for one frame. The painter used those stale indices to look up particles
  in the new, shorter list and threw. `_initParticles` now clears the grid
  as soon as it replaces the particle list, and the painter's neighbour loop
  also skips any index the current list is too short for.

## 0.3.0

- Add `touchReactive`, off by default. Repulsion was gated on `MouseRegion`'s
  onHover, which never fires for touch, so on phones and tablets the field only
  drifted and the pointer reaction was gone. Setting the flag adds a pointer
  Listener that feeds the same repulsion path from touch down and move events.
  It stays off by default so the widget keeps its current behaviour and does
  not intercept a drag meant for the content behind it. Docs now say
  pointer-reactive rather than mouse-reactive.

## 0.2.2

- Install instructions now say `pub add` instead of pinning a version. The
  pinned number was stale by several releases and would have been stale again
  after the next one: the README ships frozen in the archive, so a hand-edited
  version line is wrong the moment anything is published. This one cannot go
  out of date.

## 0.2.1

- Declare the demo in `pubspec.yaml` so pub.dev shows it on the package page.
  The recording was already in the repository and in the README, but pub.dev
  only renders what the `screenshots:` field points at, so anyone landing on
  the page from search saw text where the demo should have been.

## 0.2.0

- Honour the platform's reduce-motion setting. A drifting particle field is
  exactly the continuous background movement that setting exists to stop, and
  the widget ignored it: someone who had asked their OS for less motion got the
  full animation anyway. It now holds the simulation still and paints a single
  frame, so the constellation is still there and only the drift is gone. The
  ticker stops rather than running invisibly, and coming back from the
  background no longer restarts it while the setting is on.

## 0.1.2

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.1.1

- Docs: tightened the README wording and visuals.

## 0.1.0

- Initial release.
- Mouse-reactive constellation field with spatial-grid neighbour lookups.
- Configurable count, colour, speed, connection distance, and repulsion.
- Pauses when backgrounded; reduces density under high contrast.
