import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

const _kGridKeyStride = 100000; // Stored y-cell indices must stay below this.
const _kInitialVelocityScale = 0.4; // Maximum initial drift on either axis.
const _kPointerRepulsionScale = 0.02; // Scales pointer force to gentle motion.
const _kParticleOpacity = 0.6; // Base opacity for each particle.
const _kLineBaseOpacity = 0.08; // Base opacity for connecting lines.
const _kLineOpacityScale = 0.15; // Maximum opacity before distance fading.
const _kLineStrokeWidth = 0.5; // Connection line width in logical pixels.
const _kGlowRadiusThreshold = 1.2; // Radius above which a particle glows.
const _kGlowRadiusScale = 4.0; // Glow radius relative to the particle radius.
const _kGlowOpacity = 0.05; // Opacity at the centre of each glow.

// withValues was added after Flutter 3.24, which this package supports.
// ignore: deprecated_member_use
Color _withOpacity(Color color, double opacity) => color.withOpacity(opacity);

/// A pointer-reactive constellation particle field.
///
/// Particles drift, wrap around the edges, and repel from the pointer.
/// Nearby particles are joined by fading lines. Neighbour lookups run through
/// a spatial hash grid, so the per-frame cost stays close to O(n) instead of
/// the O(n²) you get from comparing every pair.
///
/// The mouse cursor drives repulsion on desktop and web. Touch reactivity is
/// off by default (see [touchReactive]) so the field never steals drag gestures
/// from the content it sits behind.
///
/// The widget is decorative and excludes itself from the semantics tree.
/// It pauses its ticker when the app is backgrounded and halves the particle
/// count when the platform requests high contrast.
class ConstellationParticles extends StatefulWidget {
  /// Creates a decorative, pointer-reactive particle field.
  const ConstellationParticles({
    super.key,
    this.particleCount = 100,
    this.color = const Color(0xFF64FFDA),
    this.speed = 1.0,
    this.connectionDistance = 120.0,
    this.repulsionRadius = 200.0,
    this.repulsionForce = 50.0,
    this.seed = 42,
    this.touchReactive = false,
  })  : assert(particleCount >= 0),
        assert(connectionDistance > 0),
        // The three physics multipliers reach the spatial grid, whose cell
        // index is an int: a NaN there throws `Infinity or NaN toInt` out of
        // both the ticker and paint(), once per frame for as long as the
        // widget lives. `connectionDistance > 0` already rejects a NaN by
        // being false for it; these had nothing.
        // Written as comparisons, not `isFinite`: this is a const constructor
        // and a property access is not a constant expression. Every one of
        // these is false for NaN, which is the value that actually breaks.
        assert(
          speed > double.negativeInfinity && speed < double.infinity,
          'speed must be finite',
        ),
        assert(
          repulsionRadius > double.negativeInfinity &&
              repulsionRadius < double.infinity,
          'repulsionRadius must be finite',
        ),
        assert(
          repulsionForce > double.negativeInfinity &&
              repulsionForce < double.infinity,
          'repulsionForce must be finite',
        );

  /// Number of particles at full density. Halved under high-contrast mode.
  final int particleCount;

  /// Base colour for particles and connecting lines. Opacity is derived
  /// internally per-particle and per-line.
  final Color color;

  /// Drift-speed multiplier. `1.0` is the calibrated default.
  final double speed;

  /// Maximum distance, in logical pixels, at which two particles are linked.
  /// Also used as the spatial grid cell size.
  final double connectionDistance;

  /// Radius, in logical pixels, within which the pointer pushes particles away.
  final double repulsionRadius;

  /// Strength of the pointer repulsion.
  final double repulsionForce;

  /// Seed for the initial layout. A fixed seed keeps the field reproducible
  /// across rebuilds; pass a varying value for a different arrangement.
  final int seed;

  /// Whether touches also drive the repulsion. Off by default: the mouse
  /// cursor already reacts on desktop and web, and leaving this off means the
  /// field never intercepts a touch that belongs to the content behind it.
  /// Turn it on for a foreground surface where the particles are the point.
  final bool touchReactive;

  @override
  State<ConstellationParticles> createState() => _ConstellationParticlesState();
}

class _ConstellationParticlesState extends State<ConstellationParticles>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  late _SpatialGrid _grid;
  List<_Particle> _particles = const [];
  final Paint _linePaint = Paint()..style = PaintingStyle.stroke;
  final Paint _particlePaint = Paint();
  final Paint _glowPaint = Paint();
  Color? _cachedGlowColor;
  List<Color>? _cachedGlowStops;
  Offset _mousePos = Offset.zero;
  bool _mouseInside = false;
  Size _lastSize = Size.zero;

  /// Bumped every tick so the painter knows the simulation advanced.
  int _generation = 0;

  /// Whether the platform asked for reduced motion, in which case the
  /// simulation is held still.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _grid = _SpatialGrid(widget.connectionDistance);
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(_tick)
          ..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce the particle count when the platform asks for high contrast,
    // both for legibility and to lighten the paint load.
    final target = _effectiveCount;
    if (target != _particles.length && !_lastSize.isEmpty) {
      _initParticles(_lastSize, count: target);
    }

    // Respect the platform's reduce-motion setting. Drifting particles are
    // exactly the kind of continuous background movement that setting exists
    // to stop, so hold the simulation still and paint one frame instead of
    // hiding the widget: the design survives, the motion does not.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (_reduceMotion) {
        if (_controller.isAnimating) _controller.stop();
      } else if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(ConstellationParticles old) {
    super.didUpdateWidget(old);

    if (old.connectionDistance != widget.connectionDistance) {
      _grid = _SpatialGrid(widget.connectionDistance);
    }

    if ((old.particleCount != widget.particleCount ||
            old.seed != widget.seed) &&
        !_lastSize.isEmpty) {
      _initParticles(_lastSize);
    } else if (old.connectionDistance != widget.connectionDistance) {
      _rebuildGrid();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_reduceMotion && !_controller.isAnimating) _controller.repeat();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_controller.isAnimating) _controller.stop();
      default:
        break;
    }
  }

  int get _effectiveCount {
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return highContrast
        ? (widget.particleCount * 0.5).round()
        : widget.particleCount;
  }

  void _initParticles(Size size, {int? count}) {
    if (size.isEmpty) return;
    final rng = math.Random(widget.seed);
    final n = count ?? _effectiveCount;
    _particles = List.generate(
      n,
      (_) => _Particle(
        x: rng.nextDouble() * size.width,
        y: rng.nextDouble() * size.height,
        vx: (rng.nextDouble() - 0.5) * _kInitialVelocityScale,
        vy: (rng.nextDouble() - 0.5) * _kInitialVelocityScale,
        radius: rng.nextDouble() * 1.5 + 0.5,
        opacity: rng.nextDouble() * 0.4 + 0.1,
      ),
    );
    _lastSize = size;

    _rebuildGrid();
  }

  void _rebuildGrid() {
    _grid.clear();
    for (var i = 0; i < _particles.length; i++) {
      _grid.insert(i, _particles[i].x, _particles[i].y);
    }
  }

  List<Color> _glowStopsFor(Color color) {
    if (_cachedGlowColor != color) {
      _cachedGlowColor = color;
      _cachedGlowStops = [
        _withOpacity(color, _kGlowOpacity),
        const Color(0x00000000),
      ];
    }
    return _cachedGlowStops!;
  }

  void _tick() {
    if (_lastSize.isEmpty || _particles.isEmpty) return;
    final speed = widget.speed;
    final radius = widget.repulsionRadius;

    for (final p in _particles) {
      p
        ..x += p.vx * speed
        ..y += p.vy * speed;

      if (p.x < 0) p.x = _lastSize.width;
      if (p.x > _lastSize.width) p.x = 0;
      if (p.y < 0) p.y = _lastSize.height;
      if (p.y > _lastSize.height) p.y = 0;

      if (_mouseInside) {
        final dx = p.x - _mousePos.dx;
        final dy = p.y - _mousePos.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < radius && dist > 0) {
          final force = (radius - dist) / radius;
          p
            ..x += (dx / dist) *
                force *
                widget.repulsionForce *
                _kPointerRepulsionScale
            ..y += (dy / dist) *
                force *
                widget.repulsionForce *
                _kPointerRepulsionScale;
        }
      }
    }

    // Rebuild the spatial grid once per frame; particles land in the cell
    // matching their position so neighbour queries only scan 9 cells.
    _rebuildGrid();

    _generation++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field = IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            if (size != _lastSize || _particles.isEmpty) {
              _initParticles(size);
            }
            return AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                size: size,
                painter: _ConstellationPainter(
                  particles: _particles,
                  color: widget.color,
                  connectionDistance: widget.connectionDistance,
                  generation: _generation,
                  grid: _grid,
                  linePaint: _linePaint,
                  particlePaint: _particlePaint,
                  glowPaint: _glowPaint,
                  glowStops: _glowStopsFor(widget.color),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Touch does not fire MouseRegion.onHover, so opt in to a pointer listener
    // that feeds the same _mousePos/_mouseInside the mouse path already uses.
    // Translucent behaviour lets it register a hit even though IgnorePointer
    // keeps the field itself out of hit testing.
    if (widget.touchReactive) {
      field = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _mousePos = e.localPosition;
          _mouseInside = true;
        },
        onPointerMove: (e) {
          _mousePos = e.localPosition;
          _mouseInside = true;
        },
        onPointerUp: (_) => _mouseInside = false,
        onPointerCancel: (_) => _mouseInside = false,
        child: field,
      );
    }

    return ExcludeSemantics(
      child: MouseRegion(
        onHover: (e) {
          _mousePos = e.localPosition;
          _mouseInside = true;
        },
        onExit: (_) => _mouseInside = false,
        hitTestBehavior: HitTestBehavior.translucent,
        child: field,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spatial hash grid — buckets particles into cells so a neighbour query only
// visits the 9 cells around a point instead of the whole population.
// ---------------------------------------------------------------------------

class _SpatialGrid {
  _SpatialGrid(this.cellSize);
  final double cellSize;
  final Map<int, List<int>> _cells = {};

  void clear() => _cells.clear();

  /// Stored y cells stay nonnegative and below [_kGridKeyStride].
  int _keyOf(int cx, int cy) => cx * _kGridKeyStride + cy;

  int _key(double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    return _keyOf(cx, cy);
  }

  void insert(int index, double x, double y) {
    _cells.putIfAbsent(_key(x, y), () => []).add(index);
  }

  List<int> getNearby(double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    final result = <int>[];
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final cell = _cells[_keyOf(cx + dx, cy + dy)];
        if (cell != null) result.addAll(cell);
      }
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.particles,
    required this.color,
    required this.connectionDistance,
    required this.generation,
    required this.grid,
    required this.linePaint,
    required this.particlePaint,
    required this.glowPaint,
    required this.glowStops,
  });

  final List<_Particle> particles;
  final Color color;
  final double connectionDistance;
  final int generation;
  final _SpatialGrid grid;
  final Paint linePaint;
  final Paint particlePaint;
  final Paint glowPaint;
  final List<Color> glowStops;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final particleColor = _withOpacity(color, _kParticleOpacity);
    final lineColor = _withOpacity(color, _kLineBaseOpacity);
    final distSqThreshold = connectionDistance * connectionDistance;
    linePaint.strokeWidth = _kLineStrokeWidth;

    // Connecting lines, resolved through the grid so we only test near pairs.
    for (var i = 0; i < particles.length; i++) {
      final pi = particles[i];
      for (final j in grid.getNearby(pi.x, pi.y)) {
        // j <= i skips a pair already handled from the other side; the
        // upper bound guards against a grid index left over from a larger
        // population (see _initParticles).
        if (j <= i || j >= particles.length) continue;
        final pj = particles[j];
        final dx = pi.x - pj.x;
        final dy = pi.y - pj.y;
        final distSq = dx * dx + dy * dy;
        if (distSq < distSqThreshold) {
          final dist = math.sqrt(distSq);
          final opacity =
              (1.0 - dist / connectionDistance) * _kLineOpacityScale;
          linePaint.color = _withOpacity(lineColor, opacity);
          canvas.drawLine(Offset(pi.x, pi.y), Offset(pj.x, pj.y), linePaint);
        }
      }
    }

    for (final p in particles) {
      particlePaint.color = _withOpacity(particleColor, p.opacity);
      canvas.drawCircle(Offset(p.x, p.y), p.radius, particlePaint);
      if (p.radius > _kGlowRadiusThreshold) {
        glowPaint.shader = ui.Gradient.radial(
          Offset(p.x, p.y),
          p.radius * _kGlowRadiusScale,
          glowStops,
        );
        canvas.drawCircle(
          Offset(p.x, p.y),
          p.radius * _kGlowRadiusScale,
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) =>
      generation != old.generation ||
      color != old.color ||
      connectionDistance != old.connectionDistance ||
      particles != old.particles ||
      grid != old.grid;
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.opacity,
  });

  double x;
  double y;
  final double vx;
  final double vy;
  final double radius;
  final double opacity;
}
