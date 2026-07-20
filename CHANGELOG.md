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
