/// What the connecting-line pass costs, both ways.
///
/// A constellation field answers one question every frame: which pairs of
/// particles are close enough to draw a line between? The obvious way is to ask
/// it of every pair, which is n(n-1)/2 distance checks a frame. This package
/// buckets particles into a spatial hash grid whose cell size *is* the
/// connection distance, so a particle can only reach something in its own cell
/// or the eight around it.
///
/// That grid is the package's reason for existing, so it is worth knowing what
/// it buys. This script is that number, and it comes in two halves that do not
/// agree:
///
///   * The grid really does far fewer distance checks — about eight times fewer
///     at 800 particles.
///   * It is not therefore faster. A distance check costs about a nanosecond; a
///     hash-map lookup costs tens of them. The grid trades many cheap
///     operations for a few expensive ones, and whether that trade pays turns
///     on something easy to miss: whether your canvas grows with the particle
///     count or stays the same size.
///
/// So there are two runs below. The first raises the count on a fixed canvas,
/// which is what happens when someone turns `particleCount` up. The second grows
/// the canvas with the count, holding density constant, which is the shape the
/// O(n) claim is actually about. They reach opposite conclusions and both are
/// true.
///
/// This is a standalone reproduction of the pass rather than a call into the
/// widget: the grid is private, and a `dart run` script has no Flutter binding
/// to drive the real widget with. [_SpatialGrid] below is kept the same shape as
/// the private one in `lib/constellation_particles.dart` — same cell key, same
/// 3x3 scan, same `j <= i` skip in the caller — so diff the two by eye before
/// trusting any of this.
///
/// The check counts are arithmetic over a fixed seed and will come out the same
/// on your machine. The microseconds will not.
///
///     cd example && dart run frame_cost.dart
///
/// That gives you the JIT. A Flutter release build is AOT-compiled, where the
/// map-heavy code fares worse and the ordering below changes, so measure the
/// mode you ship:
///
///     cd example
///     dart compile exe frame_cost.dart -o frame_cost && ./frame_cost
library;

import 'dart:io';
import 'dart:math' as math;

/// The package default for `connectionDistance`. Also the grid's cell size,
/// which is load-bearing — see [_theCellSizeIsNotArbitrary].
const _connectionDistance = 120.0;
const _thresholdSq = _connectionDistance * _connectionDistance;

void main() {
  // Before any timing. The property is geometric, so proving it once at one
  // population proves it everywhere — and the check allocates a set and a
  // candidate list per particle, which is exactly the kind of garbage that
  // lands in the middle of a timed loop and gets reported as the cost of the
  // code.
  _requireCompleteNeighbourhood(_field(400, 1200.0, 800.0));

  _onAFixedCanvas(stdout);
  _atConstantDensity(stdout);
  _theCellSizeIsNotArbitrary(stdout);
  _whatThisDoesNotMeasure(stdout);
}

// ---------------------------------------------------------------------------
// Run one: raise the count, keep the canvas
// ---------------------------------------------------------------------------

/// The configuration someone actually reaches: a background sized to the
/// window, and a `particleCount` they turn up until it looks right.
void _onAFixedCanvas(IOSink out) {
  const width = 1200.0;
  const height = 800.0;

  out.writeln(
    'RAISING THE COUNT ON A ${width.toInt()}x${height.toInt()} CANVAS\n'
    'Density rises with the count, so both passes grow quadratically and the\n'
    "grid's advantage is a constant factor rather than a change of shape.\n",
  );
  out.writeln('            distance checks          microseconds per pass');
  out.writeln('       n      pair      grid       pair    grid  in place'
      '     links');

  for (final n in [50, 100, 200, 400, 800, 1600]) {
    final field = _field(n, width, height);
    final grid = _SpatialGrid(_connectionDistance);

    final pair = _everyPair(field);
    final gridded = _viaGrid(field, grid);
    final inPlace = _viaGridInPlace(field, grid);
    _requireSameAnswer(n, {
      'every-pair': pair,
      'grid': gridded,
      'in place': inPlace,
    });

    out.writeln([
      _count(n, 8),
      _count(pair.checks, 10),
      _count(gridded.checks, 10),
      _micros(() => _everyPair(field), n: n, links: pair.links, width: 11),
      _micros(() => _viaGrid(field, grid), n: n, links: pair.links, width: 8),
      _micros(
        () => _viaGridInPlace(field, grid),
        n: n,
        links: pair.links,
        width: 10,
      ),
      _count(pair.links, 10),
    ].join());
  }

  out.writeln('''

The check columns hold up: at 800 particles the grid asks 36,861 distance
questions where every-pair asks 319,600. The time columns do not follow. The
grid column, which is the pass the widget actually runs, is the slower of the
two at every population in this table.

The third column says where it went. `getNearby` builds a fresh candidate list
per particle and copies every index in nine cells into it, which is about twice
the candidates the grid was there to avoid. Walking those nine cells where they
sit skips the copy, and that is the only column here that ever comes out ahead
— from about 400 particles up, having lost below it. Compiled AOT, which is
what a Flutter release build does, even that column loses until the field is
denser than anything you would render; the command is in this file's header
comment. What is left once the copy goes is nine hash-map lookups per particle,
and a lookup costs tens of the arithmetic operations it saved.''');
}

// ---------------------------------------------------------------------------
// Run two: grow the canvas with the count
// ---------------------------------------------------------------------------

/// The same populations on a canvas that grows with them, so the particles stay
/// about as far apart as they started.
///
/// This is the grid's home ground. A particle's work in the grid is set by how
/// many neighbours are within reach, not by how many particles exist, so at
/// constant density the grid pass is linear while every-pair stays quadratic —
/// and that is a difference in shape, not a constant factor.
void _atConstantDensity(IOSink out) {
  out.writeln('''

THE SAME COUNTS, CANVAS GROWING WITH THEM
Four times the particles on twice the canvas in each direction, so the
neighbourhood a particle sees stays about the same size.
''');
  out.writeln('            distance checks          microseconds per pass');
  out.writeln('       n     canvas      pair      grid       pair'
      '      grid     links');

  for (final (n, width, height) in [
    (100, 1200.0, 800.0),
    (400, 2400.0, 1600.0),
    (1600, 4800.0, 3200.0),
    (6400, 9600.0, 6400.0),
  ]) {
    final field = _field(n, width, height);
    final grid = _SpatialGrid(_connectionDistance);

    final pair = _everyPair(field);
    final gridded = _viaGrid(field, grid);
    _requireSameAnswer(n, {'every-pair': pair, 'grid': gridded});

    out.writeln([
      _count(n, 8),
      '${width.toInt()}x${height.toInt()}'.padLeft(11),
      _count(pair.checks, 10),
      _count(gridded.checks, 10),
      _micros(() => _everyPair(field), n: n, links: pair.links, width: 11),
      _micros(() => _viaGrid(field, grid), n: n, links: pair.links, width: 10),
      _count(pair.links, 10),
    ].join());
  }

  out.writeln('''

Every step multiplies the count by four. Every-pair checks go up sixteen times
each step and the grid's go up about four, which is the whole of the argument
for building one. Here the wall clock follows the checks once there is enough
field to matter: the crossover lands between 400 and 1600 particles, and by
6400 the gap is roughly fivefold even with the candidate list left in.

The grid's own times are not quite linear either. Past a few thousand entries
the map and the particle list stop fitting in cache, and that shows up as time
the check count cannot explain.''');
}

// ---------------------------------------------------------------------------
// The one design decision in the grid
// ---------------------------------------------------------------------------

/// Cell size equal to the connection distance is not a tidy coincidence; it is
/// what makes the 3x3 window complete. Two particles closer together than one
/// cell size cannot be two cells apart on either axis, so those nine cells are
/// guaranteed to hold every pair worth drawing.
///
/// Halve the cells and the guarantee goes. The window spans 1.5 connection
/// distances instead of 3, pairs that should link now sit two cells apart and
/// are never compared, and the pass gets *faster* while doing it. A change that
/// draws less and profiles better is the hardest kind to notice.
void _theCellSizeIsNotArbitrary(IOSink out) {
  const n = 400;
  final field = _field(n, 1200.0, 800.0);

  final correct = _viaGrid(field, _SpatialGrid(_connectionDistance));
  final tooSmall = _viaGrid(field, _SpatialGrid(_connectionDistance / 2));

  out.writeln('\nWHY THE CELL SIZE IS THE CONNECTION DISTANCE, '
      'AT $n PARTICLES\n');
  void row(String label, ({int links, int checks}) pass) {
    out.writeln('  ${label.padRight(36)}'
        '${pass.checks} checks, ${pass.links} links');
  }

  row('cell ${_connectionDistance.toInt()}, the connection distance', correct);
  row('cell ${(_connectionDistance / 2).toInt()}, half of it', tooSmall);
  out.writeln(
    '\nHalving the cells loses ${correct.links - tooSmall.links} of '
    '${correct.links} lines and looks like a speedup while\ndoing it. Cells '
    'larger than the connection distance stay correct and only cost\nmore; '
    'smaller ones are a rendering bug that profiles well.',
  );
}

/// The honest boundary of all of the above.
void _whatThisDoesNotMeasure(IOSink out) {
  out.writeln('''

WHAT THIS DOES NOT MEASURE
This is the neighbour pass alone. The widget then draws what the pass found,
and at 800 particles on the fixed canvas that was 13,611 links: 13,611
drawLine calls a frame, each with its own colour, plus a circle per particle
and a fresh radial gradient for the larger ones. Whether the pass or the
drawing is what you would actually feel is not a question this script answers,
and if you are chasing a dropped frame in a real app, a Flutter timeline is the
instrument for it rather than this.

What it does answer is narrower and still worth having: the grid bounds a
particle's work by how crowded its neighbourhood is instead of by how many
particles exist. On a canvas that grows with the count that is an order. On a
canvas that stays put it is a constant factor, and one the bookkeeping can
eat.''');
}

// ---------------------------------------------------------------------------
// The passes. No instrumentation in these loops, deliberately: see
// _requireCompleteNeighbourhood for why the correctness check lives outside.
// ---------------------------------------------------------------------------

/// Every pair, once. This is what most connecting-line fields do, and it is not
/// wrong — it is quadratic, which is fine right up until it isn't.
({int links, int checks}) _everyPair(List<_Point> ps) {
  var links = 0;
  var checks = 0;
  for (var i = 0; i < ps.length; i++) {
    final pi = ps[i];
    for (var j = i + 1; j < ps.length; j++) {
      final pj = ps[j];
      final dx = pi.x - pj.x;
      final dy = pi.y - pj.y;
      checks++;
      if (dx * dx + dy * dy < _thresholdSq) links++;
    }
  }
  return (links: links, checks: checks);
}

/// The grid pass exactly as the widget's painter walks it: rebuild the buckets,
/// then ask [_SpatialGrid.getNearby] for a list of candidates per particle.
///
/// The rebuild is inside the timing on purpose. It happens every frame in the
/// real widget, because the particles moved, and timing only the query half
/// would be flattering rather than useful.
({int links, int checks}) _viaGrid(List<_Point> ps, _SpatialGrid grid) {
  grid.clear();
  for (var i = 0; i < ps.length; i++) {
    grid.insert(i, ps[i].x, ps[i].y);
  }

  var links = 0;
  var checks = 0;
  for (var i = 0; i < ps.length; i++) {
    final pi = ps[i];
    for (final j in grid.getNearby(pi.x, pi.y)) {
      // The pair (j, i) was handled when i's turn came around, and a particle
      // finds itself in its own cell. Both fall out of `j <= i`.
      if (j <= i) continue;
      final pj = ps[j];
      final dx = pi.x - pj.x;
      final dy = pi.y - pj.y;
      checks++;
      if (dx * dx + dy * dy < _thresholdSq) links++;
    }
  }
  return (links: links, checks: checks);
}

/// The same grid, walked without the candidate list.
///
/// Same cells, same order, same `j <= i` skip, same answer. The only difference
/// is that the nine cells are iterated where they sit instead of being copied
/// into a list first. That copy is the gap between the second and third time
/// columns of the first run, and it is how a better algorithm still loses.
({int links, int checks}) _viaGridInPlace(List<_Point> ps, _SpatialGrid grid) {
  grid.clear();
  for (var i = 0; i < ps.length; i++) {
    grid.insert(i, ps[i].x, ps[i].y);
  }

  var links = 0;
  var checks = 0;
  for (var i = 0; i < ps.length; i++) {
    final pi = ps[i];
    final cx = (pi.x / grid.cellSize).floor();
    final cy = (pi.y / grid.cellSize).floor();
    for (var dcx = -1; dcx <= 1; dcx++) {
      for (var dcy = -1; dcy <= 1; dcy++) {
        final cell = grid.cellAt(cx + dcx, cy + dcy);
        if (cell == null) continue;
        for (var k = 0; k < cell.length; k++) {
          final j = cell[k];
          if (j <= i) continue;
          final pj = ps[j];
          final dx = pi.x - pj.x;
          final dy = pi.y - pj.y;
          checks++;
          if (dx * dx + dy * dy < _thresholdSq) links++;
        }
      }
    }
  }
  return (links: links, checks: checks);
}

// ---------------------------------------------------------------------------
// Same work, or the timings mean nothing
// ---------------------------------------------------------------------------

/// Requires the passes to have drawn the same number of lines, and stops the
/// run if they did not.
///
/// A benchmark whose two sides are doing different amounts of work measures
/// nothing, and this is the cheap half of guarding against that. The link count
/// is a sensitive detector: halving the grid's cell size, which is the natural
/// way to get this wrong, drops it by a third — see
/// [_theCellSizeIsNotArbitrary].
void _requireSameAnswer(int n, Map<String, ({int links, int checks})> passes) {
  final reference = passes.entries.first;
  for (final other in passes.entries.skip(1)) {
    if (other.value.links != reference.value.links) {
      stderr.writeln(
        'the passes disagree at $n particles: ${reference.key} drew '
        '${reference.value.links} lines, ${other.key} drew '
        '${other.value.links}. Timing them against each other would be '
        'comparing different amounts of work.',
      );
      exit(1);
    }
  }
}

/// The strict half: proves the nine cells actually contain every pair worth
/// drawing, and that this check could tell if they didn't.
///
/// Equal link counts alone would leave room for two passes to find the same
/// number of lines and disagree about which. Rather than instrument the timed
/// loops to compare their output — a `record` parameter in those loops measured
/// about a nanosecond per iteration, which biased the comparison towards the
/// grid by inflating every-pair's far longer loop — the property is checked
/// directly against [_SpatialGrid.getNearby]: for every pair inside the
/// connection distance, is the neighbour in the neighbourhood?
///
/// The second half is the positive control. A completeness check that cannot
/// fail proves nothing, so the same check is run against a grid with cells half
/// the size, where it must find misses.
void _requireCompleteNeighbourhood(List<_Point> ps) {
  final missedWhenCorrect = _pairsOutsideTheNeighbourhood(
    ps,
    _SpatialGrid(_connectionDistance),
  );
  if (missedWhenCorrect != 0) {
    stderr.writeln(
      'at ${ps.length} particles, $missedWhenCorrect pairs inside the '
      'connection distance were not in the nine cells around them. The grid '
      'pass is dropping lines, so its lower check count is not a saving.',
    );
    exit(1);
  }

  final missedWhenHalved = _pairsOutsideTheNeighbourhood(
    ps,
    _SpatialGrid(_connectionDistance / 2),
  );
  if (missedWhenHalved == 0) {
    stderr.writeln(
      'the completeness check found nothing wrong with cells half the '
      'connection distance, which cannot be right. The check is broken, so '
      'its verdict on the real grid means nothing either.',
    );
    exit(1);
  }
}

/// How many pairs closer than the connection distance are absent from the nine
/// cells around one of them.
int _pairsOutsideTheNeighbourhood(List<_Point> ps, _SpatialGrid grid) {
  grid.clear();
  for (var i = 0; i < ps.length; i++) {
    grid.insert(i, ps[i].x, ps[i].y);
  }

  var missed = 0;
  for (var i = 0; i < ps.length; i++) {
    final pi = ps[i];
    final neighbourhood = grid.getNearby(pi.x, pi.y).toSet();
    for (var j = i + 1; j < ps.length; j++) {
      final pj = ps[j];
      final dx = pi.x - pj.x;
      final dy = pi.y - pj.y;
      if (dx * dx + dy * dy < _thresholdSq && !neighbourhood.contains(j)) {
        missed++;
      }
    }
  }
  return missed;
}

// ---------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------

/// A reproducible field. Fixed seed, so the check counts printed above are the
/// check counts you will get.
List<_Point> _field(int n, double width, double height) {
  final rng = math.Random(42);
  return List.generate(
    n,
    (_) => _Point(rng.nextDouble() * width, rng.nextDouble() * height),
  );
}

/// One pass, in microseconds, padded to [width] for the table.
///
/// The warm-up is not politeness. The first few hundred passes pay for JIT
/// compilation, and at 50 particles a pass is under a microsecond, so without
/// one the measurement would be mostly compiler.
///
/// Three rounds, and the fastest is reported rather than the mean. A round can
/// only be made slower by something that is not the code — a garbage collection
/// landing mid-loop, the scheduler taking the core away — so the minimum is the
/// closest thing here to the cost of the pass itself.
///
/// That is not a precaution against a hypothetical. An earlier version timed a
/// single round and ran the correctness check just before it, per population;
/// the check's garbage collected inside the timed loop and moved one column by a
/// factor of three, which was enough to reverse which pass looked faster. Hence
/// both: the check runs once, before any timing, and the minimum is reported.
///
/// [links] is the timed loop's own positive control. If a compiler ever decides
/// that a pass nobody reads the result of can be skipped, this run would still
/// print a plausible-looking number and the number would be a lie, so the last
/// result is read back and has to match what the untimed pass found. Folding
/// every result into a sink instead was measured against discarding them and
/// made no difference on either the JIT or AOT, so this stays a check rather
/// than a workaround.
String _micros(
  ({int links, int checks}) Function() pass, {
  required int n,
  required int links,
  required int width,
}) {
  final reps = math.max(30, 120000 ~/ n);
  for (var i = 0; i < reps + 20; i++) {
    pass();
  }

  var observed = -1;
  var best = double.infinity;
  for (var round = 0; round < 3; round++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < reps; i++) {
      observed = pass().links;
    }
    sw.stop();
    final micros = sw.elapsedMicroseconds / reps;
    if (micros < best) best = micros;
  }

  if (observed != links) {
    stderr.writeln(
      'the timed pass at $n particles found $observed links where the untimed '
      'one found $links. Something is measuring the wrong thing, so none of '
      'these numbers can be trusted.',
    );
    exit(1);
  }

  return best.toStringAsFixed(1).padLeft(width);
}

String _count(int value, int width) => value.toString().padLeft(width);

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;
}

// ---------------------------------------------------------------------------
// The grid, in the same shape as the widget's
// ---------------------------------------------------------------------------

/// Buckets particle indices into cells of [cellSize], so a neighbour query
/// visits nine cells instead of the whole population.
///
/// Kept deliberately close to the private grid in
/// `lib/constellation_particles.dart`, down to the `cx * 100000 + cy` key and
/// the list [getNearby] returns, so that what this script measures is what the
/// widget pays. [cellAt] is the one addition, and it only exposes what
/// [getNearby] already reads.
class _SpatialGrid {
  _SpatialGrid(this.cellSize);

  final double cellSize;
  final Map<int, List<int>> _cells = {};

  void clear() => _cells.clear();

  void insert(int index, double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    _cells.putIfAbsent(cx * 100000 + cy, () => <int>[]).add(index);
  }

  List<int>? cellAt(int cx, int cy) => _cells[cx * 100000 + cy];

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
