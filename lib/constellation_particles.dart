import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A mouse-reactive constellation particle field.
///
/// Particles drift, wrap around the edges, and repel from the pointer.
/// Nearby particles are joined by fading lines. Neighbour lookups run through
/// a spatial hash grid, so the per-frame cost stays close to O(n) instead of
/// the O(n²) you get from comparing every pair.
///
/// The widget is decorative and excludes itself from the semantics tree.
/// It pauses its ticker when the app is backgrounded and halves the particle
/// count when the platform requests high contrast.
class ConstellationParticles extends StatefulWidget {
  const ConstellationParticles({
    super.key,
    this.particleCount = 100,
    this.color = const Color(0xFF64FFDA),
    this.speed = 1.0,
    this.connectionDistance = 120.0,
    this.repulsionRadius = 200.0,
    this.repulsionForce = 50.0,
    this.seed = 42,
  })  : assert(particleCount >= 0),
        assert(connectionDistance > 0);

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

  @override
  State<ConstellationParticles> createState() => _ConstellationParticlesState();
}

class _ConstellationParticlesState extends State<ConstellationParticles>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  late final _SpatialGrid _grid;
  List<_Particle> _particles = const [];
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
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
    if (old.particleCount != widget.particleCount && !_lastSize.isEmpty) {
      _initParticles(_lastSize);
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
        vx: (rng.nextDouble() - 0.5) * 0.4,
        vy: (rng.nextDouble() - 0.5) * 0.4,
        radius: rng.nextDouble() * 1.5 + 0.5,
        opacity: rng.nextDouble() * 0.4 + 0.1,
      ),
    );
    _lastSize = size;
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
            ..x += (dx / dist) * force * widget.repulsionForce * 0.02
            ..y += (dy / dist) * force * widget.repulsionForce * 0.02;
        }
      }
    }

    // Rebuild the spatial grid once per frame; particles land in the cell
    // matching their position so neighbour queries only scan 9 cells.
    _grid.clear();
    for (var i = 0; i < _particles.length; i++) {
      _grid.insert(i, _particles[i].x, _particles[i].y);
    }

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
  Widget build(BuildContext context) => ExcludeSemantics(
        child: MouseRegion(
          onHover: (e) {
            _mousePos = e.localPosition;
            _mouseInside = true;
          },
          onExit: (_) => _mouseInside = false,
          hitTestBehavior: HitTestBehavior.translucent,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
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
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
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

  int _key(double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    return cx * 100000 + cy;
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
        final cell = _cells[(cx + dx) * 100000 + (cy + dy)];
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
  });

  final List<_Particle> particles;
  final Color color;
  final double connectionDistance;
  final int generation;
  final _SpatialGrid grid;

  static final _linePaint = Paint()..style = PaintingStyle.stroke;
  static final _particlePaint = Paint();
  static final _glowPaint = Paint();
  static Color? _cachedGlowColor;
  static List<Color>? _cachedGlowStops;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final particleColor = color.withValues(alpha: 0.6);
    final lineColor = color.withValues(alpha: 0.08);
    final distSqThreshold = connectionDistance * connectionDistance;
    _linePaint.strokeWidth = 0.5;

    // Connecting lines, resolved through the grid so we only test near pairs.
    for (var i = 0; i < particles.length; i++) {
      final pi = particles[i];
      for (final j in grid.getNearby(pi.x, pi.y)) {
        if (j <= i) continue; // each pair once
        final pj = particles[j];
        final dx = pi.x - pj.x;
        final dy = pi.y - pj.y;
        final distSq = dx * dx + dy * dy;
        if (distSq < distSqThreshold) {
          final dist = math.sqrt(distSq);
          final opacity = (1.0 - dist / connectionDistance) * 0.15;
          _linePaint.color = lineColor.withValues(alpha: opacity);
          canvas.drawLine(Offset(pi.x, pi.y), Offset(pj.x, pj.y), _linePaint);
        }
      }
    }

    if (_cachedGlowColor != color) {
      _cachedGlowColor = color;
      _cachedGlowStops = [color.withValues(alpha: 0.05), Colors.transparent];
    }

    for (final p in particles) {
      _particlePaint.color = particleColor.withValues(alpha: p.opacity);
      canvas.drawCircle(Offset(p.x, p.y), p.radius, _particlePaint);
      if (p.radius > 1.2) {
        _glowPaint.shader = ui.Gradient.radial(
          Offset(p.x, p.y),
          p.radius * 4,
          _cachedGlowStops!,
        );
        canvas.drawCircle(Offset(p.x, p.y), p.radius * 4, _glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) =>
      generation != old.generation || color != old.color;
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
