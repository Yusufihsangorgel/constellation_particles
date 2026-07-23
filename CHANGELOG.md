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
