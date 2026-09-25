# Package engineering rules: constellation_particles

Rules-Version: constellation_particles/786a9f8469a4a9618f9a567e5c5b7cc6ced8de1eeb5adb82f0dc15ba9c81fa78
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: 9b7c619
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD 9b7c619 (2026-08-29), version 1.1.0, 39 commits. A single file package: lib/constellation_particles.dart (442 lines). There is no lib/src and no library directive. flutter >=3.24.0, sdk ^3.5.0. The only dependency is the Flutter SDK (the pubspec description promises 'zero runtime deps'). Contents: the public ConstellationParticles widget. The private state runs the simulation (particle motion, wrap at the edges, pointer repulsion) and honors platform contracts (reduced motion, high contrast, app lifecycle). Helpers: _SpatialGrid (cell size = connectionDistance, neighbor query over 9 cells), _ConstellationPainter and _Particle. example/frame_cost.dart measures cost with a copy of the grid. In CI it verifies that the all-pairs pass draws the same lines as the grid. There is no hook/ or bin/. AGENTS.md is written for an agent that uses the package. There is a .pubignore at the root.

## Layers and responsibilities
- lib/constellation_particles.dart: ConstellationParticles (constructor validation), _ConstellationParticlesState (frame clock, particle seeding, tick physics, pointer and touch input, reduced motion, high contrast, lifecycle), _SpatialGrid (neighbor search), _ConstellationPainter (lines, particles, glow), _Particle (mutable position).
- example/ (frame_cost.dart, lib/main.dart, test/hold_still_test.dart): Produces the cost table for the neighbor pass. In CI it checks that the grid matches the all-pairs pass (exit 1 on mismatch). Demo app and one example widget test.
- tool/: benchmark_chart and param_grid README figures; not library code.

## Public API and dependency direction
The only public type is ConstellationParticles. Its parameters are particleCount, color, speed, connectionDistance, repulsionRadius, repulsionForce, seed and touchReactive. The constructor has no doc. The private state has an isPointerInside getter marked @visibleForTesting. Tests reach it through dynamic.

The file imports dart:math, dart:ui and package:flutter/material.dart. Material is needed only for Colors.transparent. Direction inside the file: widget → state → {_SpatialGrid, _ConstellationPainter → {_Particle, _SpatialGrid}}. example/frame_cost.dart does not import lib. It copies the grid.

## Error, state and platform contracts
- Performance architecture: the grid is rebuilt every frame and the neighbor query is limited to 9 cells (O(n) goal). Paint objects and glow stops are kept in a cache, but in static fields (debt).
- Error contract: comparison based asserts compatible with a const constructor reject NaN and infinity (lib:31-54). Painting has a bounds guard for a stale grid index (lib:385-388).
- Platform check: MediaQuery.maybeDisableAnimationsOf, maybeHighContrastOf, lifecycle through WidgetsBindingObserver; MouseRegion and an optional touch Listener. Platform.isX is not used.
- Accessibility: the widget is decorative and wrapped in ExcludeSemantics. With IgnorePointer and translucent listeners it does not claim hit tests.
- Configuration: constructor parameters only. Tuning constants sit as unnamed literals (debt).
- No FFI. Streams/cancellation: AnimationController.repeat serves as the frame clock. The observer is added and removed. The controller is disposed.
- The measurement script is a real check in CI: exit(1) on mismatch (frame_cost.dart:381, 411, 424, 519).

## Package rules
### constellation_particles/CP-01 [MUST]
ConstellationParticles is the only public type, in lib/constellation_particles.dart. Helpers stay private. If the file is split, implementation moves under lib/src and the main library exports with show.
Reason: A single 442-line file fits the scale of the package; for this reason the lib/src layer is not imposed. If the file is split, the boundary must be drawn with show as in the other packages.
Evidence: lib/constellation_particles.dart:20, 90, 316, 351, 426
Evidence role: current-pattern
Existing violation: none

### constellation_particles/CP-02 [MUST]
Keep zero runtime dependencies beyond the Flutter SDK.
Reason: The pubspec description makes the 'zero runtime deps' promise.
Evidence: pubspec.yaml:5 (description); pubspec.yaml dependencies (flutter: sdk)
Evidence role: current-pattern
Existing violation: none

### constellation_particles/CP-03 [MUST]
Per-frame neighbour lookups go through the spatial grid, never an all-pairs loop. The grid and an every-pair pass must agree on the lines drawn.
Reason: The performance claim of the package is O(n). The CI script exits with exit 1 when the two methods disagree.
Evidence: lib/constellation_particles.dart:9-11, 229-234, 381-400; .github/workflows/ci.yml (dart run example/frame_cost.dart and its comment); example/frame_cost.dart:381, 411, 424, 519
Evidence role: current-pattern
Existing violation: constellation_particles-D001

### constellation_particles/CP-04 [MUST]
Keep the platform contracts: reduced motion stops the ticker and still paints a frame, high contrast halves the count, a paused or hidden app stops the ticker, and the field stays out of semantics.
Reason: The class dartdoc and the pubspec description promise these. reduce_motion_test protects them with 6 cases.
Evidence: lib/constellation_particles.dart:17-19, 122-173, 297; test/reduce_motion_test.dart; example/test/hold_still_test.dart
Evidence role: current-pattern
Existing violation: none

### constellation_particles/CP-05 [MUST]
Reject NaN or infinite physics multipliers in debug with a const-compatible assert naming the parameter.
Reason: The code comment explains that NaN blows up in the grid index every frame; a test exercises this.
Evidence: lib/constellation_particles.dart:31-54; test/constellation_particles_test.dart:51
Evidence role: current-pattern
Existing violation: none

### constellation_particles/CP-06 [MUST]
Touch reactivity stays opt-in, and the field never claims a hit test (IgnorePointer plus translucent listeners).
Reason: A background widget must not steal gestures from the content in front of it. Dartdoc and tests pin this behavior.
Evidence: lib/constellation_particles.dart:13-15, 80-84, 250, 276-306; test/touch_reactive_test.dart:18, 49
Evidence role: current-pattern
Existing violation: none

### constellation_particles/CP-07 [MUST]
Keep CI green on dart analyze --fatal-infos, format, flutter test and dart run example/frame_cost.dart.
Reason: This is the current CI gate.
Evidence: .github/workflows/ci.yml; analysis_options.yaml:1-7
Evidence role: current-pattern
Existing violation: none

### constellation_particles/CP-08 [MUST]
A constructor argument that shapes simulation state (particleCount, connectionDistance, seed) is handled in didUpdateWidget, with a test that changes it at runtime.
Reason: particleCount has this pattern and its test; connectionDistance and seed do not (debt C1).
Evidence: lib/constellation_particles.dart:147-153, 175-199; test/shrinking_population_test.dart; test/constellation_particles_test.dart:33
Evidence role: current-pattern
Existing violation: constellation_particles-D001

### constellation_particles/CP-09 [MUST_NOT]
Do not keep static mutable state in the painter or the state class. Paint objects and caches belong to an instance.
Reason: Shared principle: there must be no global mutable state. Today static Paint objects and a cache are shared across all widget instances (debt C2).
Evidence: lib/constellation_particles.dart:366-370
Evidence role: counterexample
Existing violation: constellation_particles-D002

## Required verification
- Working directory: repository root; command: flutter pub get; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:23.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:24.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed .; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:25.
- Working directory: repository root; command: flutter test; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:26.
- Working directory: repository root; command: dart run example/frame_cost.dart; conditions: ci.yml job test; evidence: .github/workflows/ci.yml:32.
Not verified by the survey:
- Analysis, test and format were not run (read only). CI history was not measured (no network).
- The difference between the working tree and HEAD was not measured. Line evidence refers to HEAD 9b7c619.
- Debt items C1 and C6 were found by static reading. They were not exercised. 120 Hz behavior was not measured on a real device.
- example/frame_cost.dart was only scanned with grep. Whether the copied grid is identical to the class in lib was not compared line by line.
- The tool/ scripts and example/lib/main.dart were not read.
- Test coverage percentage and pub archive contents were not measured (dart pub publish --dry-run was not run).

## Existing debt
The complete register is docs/engineering/debt.json.
- constellation_particles-D001 | small | lib/constellation_particles.dart:93, 115, 147-153, 316-318 (ilgili dartdoc: 67-68, 76-77) | bug / untested behavior
  Fix: In didUpdateWidget rebuild the grid when connectionDistance changes (drop the late final); restart the particles when seed changes. Test: increase the distance and compare the drawn line count against an all-pairs reference (red first).
  Closure: didUpdateWidget rebuilds the spatial grid when connectionDistance changes and restarts the particles when seed changes. A test that increases the distance at runtime matches the all-pairs reference line count.
- constellation_particles-D002 | small | lib/constellation_particles.dart:366-370 | global mutable state
  Fix: Move the Paint objects and the cache onto the state instance and pass them to the painter as parameters. There must still be no per-frame allocation.
  Closure: The Paint objects and the glow cache live on the state instance and reach the painter as parameters, with no per-frame allocation.
- constellation_particles-D003 | medium | example/frame_cost.dart:31, 537-567; .github/workflows/ci.yml | duplicate logic / check measuring the wrong target
  Fix: Move the grid into lib/src/spatial_grid.dart, free of any Flutter dependency (without exporting it). Let both lib and the script import it and delete the copy. This means splitting the file; it must follow CP-01.
  Closure: One grid implementation in lib/src/spatial_grid.dart serves both the widget and example/frame_cost.dart, and the copied _SpatialGrid is deleted. The CI all-pairs agreement check runs against the shipped grid.
- constellation_particles-D004 | small | lib/constellation_particles.dart:323-327, 333-344 | duplicate constant / undocumented assumption
  Fix: A single _keyOf(cx, cy) function, a named constant, and a one-line doc stating the assumption.
  Closure: A single _keyOf helper with a named 100000 constant serves both key sites and getNearby. A one-line doc states the collision assumption below cy 100000.
- constellation_particles-D005 | small | lib/constellation_particles.dart:184-187, 223-224, 376-379, 395, 404, 410-416 | unnamed tuning constants (J5)
  Fix: Define private _k constants with a one-line meaning note for each. Behavior does not change.
  Closure: Each listed literal becomes a private _k constant with a one-line meaning note. The visible behavior is unchanged.
- constellation_particles-D006 | medium | lib/constellation_particles.dart:116-119, 201-227 | frame-rate dependent physics (potential)
  Fix: Derive dt from the ticker elapsed time and calibrate to 60 fps; test with fake time. The visible behavior changes and a minor release plus a CHANGELOG entry are required.
  Closure: Motion advances by dt derived from the ticker elapsed time, calibrated to 60 fps, and a fake-time test covers it. A minor release and a CHANGELOG entry ship the change.
- constellation_particles-D007 | small | lib/constellation_particles.dart:106-109; test/touch_reactive_test.dart:11-15 | hook leaked into lib for tests
  Fix: Tie the test to observable output (particle positions or the painted result) and remove the getter.
  Closure: The @visibleForTesting getter is gone and test/touch_reactive_test.dart asserts on observable output such as particle positions or the painted result.
- constellation_particles-D008 | small | lib/constellation_particles.dart:21 | undocumented public member (D2)
  Fix: Add a one-sentence doc.
  Closure: The public constructor carries a one-sentence /// doc.
- constellation_particles-D009 | small | lib/constellation_particles.dart:4, 404 | unnecessary dependency surface
  Fix: Use Color(0x00000000) and lower the import to widgets.dart.
  Closure: Colors.transparent is replaced by Color(0x00000000) and the import drops to widgets.dart.
- constellation_particles-D010 | small | .github/workflows/ci.yml; AGENTS.md Layout | CI coverage gap
  Fix: Add a test step for example and put 3.24.0 in the matrix.
  Closure: CI runs the example tests including hold_still_test.dart and lists Flutter 3.24.0 in the matrix.
