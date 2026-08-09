// Generates doc/benchmark.svg and doc/benchmark.png, the chart in the README.
//
//   dart run tool/benchmark_chart.dart
//
// Takes a couple of minutes: it runs `example/frame_cost.dart` and plots what
// that prints, rather than keeping its own copy of the figures. A chart with
// transcribed numbers can drift away from the script that produced them; this
// one cannot, because there is nothing here to transcribe.
//
// The SVG is written unconditionally. The PNG is rasterized with
// `rsvg-convert` if it is on PATH (`brew install librsvg`); otherwise the
// command is printed and the SVG is left for you to convert.
//
// Only the *distance check* columns are plotted, never the microseconds. The
// check counts are arithmetic over a fixed seed and come out the same
// everywhere, so the chart means the same thing on your machine as on mine.
// The timings do not: they move with the machine, and on a loaded one they
// move enough to reverse which pass looks faster. What the grid costs in wall
// clock is a question for example/README.md, which answers it with the
// hardware written down.
library;

import 'dart:io';
import 'dart:math' as math;

void main() {
  if (!Directory('doc').existsSync()) {
    stderr.writeln(
      'run this from the package root: doc/ not found in '
      '${Directory.current.path}',
    );
    exit(1);
  }

  final output = _runFrameCost();
  final fixed = _parseFixedCanvas(output);
  final growing = _parseGrowingCanvas(output);

  // Positive control. A regex that silently matches nothing would leave an
  // empty chart looking like a successful run, so require the shape of the
  // tables the script is known to print before drawing anything.
  _require(
      fixed.length == 6,
      'expected 6 fixed-canvas rows, got '
      '${fixed.length}. The table format changed and this parse is stale.');
  _require(
      growing.length == 4,
      'expected 4 constant-density rows, got '
      '${growing.length}. The table format changed and this parse is stale.');
  _require(
    fixed.first.pair == 1225 && fixed.last.grid == 144288,
    'the fixed-canvas check counts are not the ones this script has always '
    'printed (${fixed.first.pair}, ${fixed.last.grid}). Either the field '
    'changed or the columns were read in the wrong order.',
  );

  final svg = _buildSvg(fixed, growing);
  File('doc/benchmark.svg').writeAsStringSync(svg);
  stdout.writeln('wrote doc/benchmark.svg');

  final rsvg = _which('rsvg-convert');
  if (rsvg == null) {
    stdout.writeln(
      'rsvg-convert not on PATH; to rasterize:\n'
      '  rsvg-convert -w ${(_width * _scale).round()} '
      'doc/benchmark.svg -o doc/benchmark.png',
    );
    return;
  }
  final result = Process.runSync(rsvg, [
    '-w',
    '${(_width * _scale).round()}',
    'doc/benchmark.svg',
    '-o',
    'doc/benchmark.png',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('rsvg-convert failed: ${result.stderr}');
    exit(result.exitCode);
  }
  _quantize('doc/benchmark.png');
}

/// Cuts the palette down, in place.
///
/// A chart is a few flat colours plus the anti-aliasing around them, and full
/// truecolour spends most of its bytes on shades nothing here uses. Dropping
/// the resolution instead would be the wrong knob: it blurs the type and, on
/// the portfolio's other diagrams, has come out *larger* because interpolation
/// invents colours.
void _quantize(String path) {
  final before = File(path).lengthSync();
  final magick = _which('magick');
  if (magick == null) {
    stdout.writeln('wrote $path (${_kb(before)}, unquantized; '
        'install imagemagick to shrink it)');
    return;
  }
  final result = Process.runSync(magick, [
    path,
    '-colors',
    '$_colours',
    '-define',
    'png:compression-level=9',
    path,
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('magick failed: ${result.stderr}');
    exit(result.exitCode);
  }
  final after = File(path).lengthSync();
  stdout.writeln('wrote $path (${_kb(before)} -> ${_kb(after)} at '
      '$_colours colours, ${(_width * _scale).round()}x'
      '${(_height * _scale).round()})');
}

String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

// ---------------------------------------------------------------------------
// The measurement, straight from the script that owns it
// ---------------------------------------------------------------------------

String _runFrameCost() {
  stdout.writeln('running example/frame_cost.dart (this takes a minute)...');
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['run', 'example/frame_cost.dart'],
  );
  if (result.exitCode != 0) {
    stderr.writeln(
      'frame_cost.dart exited ${result.exitCode}, so there is nothing '
      'trustworthy to plot:\n${result.stderr}',
    );
    exit(1);
  }
  return result.stdout as String;
}

/// `n  pair-checks  grid-checks  <three timings>  links` on the fixed canvas.
List<_Row> _parseFixedCanvas(String out) => RegExp(
      r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+(\d+)\s*$',
      multiLine: true,
    )
        .allMatches(out)
        .map((m) => _Row(
              n: int.parse(m.group(1)!),
              pair: int.parse(m.group(2)!),
              grid: int.parse(m.group(3)!),
            ))
        .toList();

/// `n  canvas  pair-checks  grid-checks  <two timings>  links`.
List<_Row> _parseGrowingCanvas(String out) => RegExp(
      r'^\s*(\d+)\s+\d+x\d+\s+(\d+)\s+(\d+)\s+[\d.]+\s+[\d.]+\s+(\d+)\s*$',
      multiLine: true,
    )
        .allMatches(out)
        .map((m) => _Row(
              n: int.parse(m.group(1)!),
              pair: int.parse(m.group(2)!),
              grid: int.parse(m.group(3)!),
            ))
        .toList();

class _Row {
  const _Row({required this.n, required this.pair, required this.grid});
  final int n;
  final int pair;
  final int grid;
}

/// Least-squares slope of log10(checks) against log10(n).
///
/// On log-log axes a power law is a straight line whose slope is its exponent,
/// so this number is the shape of the curve rather than a description of it:
/// 2 is quadratic, 1 is linear. It is computed from the same rows that get
/// plotted, which is the point — the label cannot claim a shape the line does
/// not have.
double _slope(List<_Row> rows, int Function(_Row) y) {
  final xs = rows.map((r) => math.log(r.n) / math.ln10).toList();
  final ys = rows.map((r) => math.log(y(r)) / math.ln10).toList();
  final xBar = xs.reduce((a, b) => a + b) / xs.length;
  final yBar = ys.reduce((a, b) => a + b) / ys.length;
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < xs.length; i++) {
    num += (xs[i] - xBar) * (ys[i] - yBar);
    den += (xs[i] - xBar) * (xs[i] - xBar);
  }
  return num / den;
}

// ---------------------------------------------------------------------------
// Canvas
// ---------------------------------------------------------------------------

const _width = 1000.0;
const _height = 640.0;
const _scale = 2;

/// Palette size after rasterizing. 64 is the portfolio default for flat
/// diagrams; a chart carries anti-aliased type over a dark ground, which needs
/// more shades before the edges start to step.
const _colours = 128;

const _plotTop = 178.0;
const _plotBottom = 506.0;
const _panelALeft = 80.0;
const _panelARight = 462.0;
const _panelBLeft = 564.0;
const _panelBRight = 946.0;

// Decades covered by the y axis. The data runs from 197 checks to 20,476,800.
const _yMin = 100.0;
const _yMax = 100000000.0;

// The widget's own palette: the dark the example app paints and the teal the
// particles are drawn in, so the chart and the demo above it are recognisably
// the same package. Amber carries the pass we are not recommending.
const _bg = '#0A0E14';
const _panel = '#0E1420';
const _gridLine = '#1B2635';
const _muted = '#7D8FA3';
const _ink = '#E2E8F0';
const _teal = '#64FFDA';
const _amber = '#FFB86B';

const _sans = "'Helvetica Neue', Helvetica, Arial, sans-serif";
const _mono = "'SF Mono', Menlo, Consolas, monospace";

String _buildSvg(List<_Row> fixed, List<_Row> growing) {
  final b = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
        'width="$_width" height="$_height" '
        'viewBox="0 0 $_width $_height">')
    ..writeln('<rect width="$_width" height="$_height" fill="$_bg"/>');

  _text(b, 40, 52, 'What the spatial grid removes',
      size: 27, fill: _ink, weight: '600');
  _text(
    b,
    40,
    82,
    'Distance checks per frame. Both axes are logarithmic, so a straight '
    'line is a power law and its slope is the exponent.',
    size: 15,
    fill: _muted,
  );

  _panelChart(
    b,
    left: _panelALeft,
    right: _panelARight,
    rows: fixed,
    title: 'Canvas stays 1200x800',
    caption: 'turning particleCount up on one window',
  );
  _panelChart(
    b,
    left: _panelBLeft,
    right: _panelBRight,
    rows: growing,
    title: 'Canvas grows with the count',
    caption: 'same crowding per particle, bigger field',
  );

  _text(
    b,
    _width / 2,
    580,
    'Fewer checks is not less time. On the left the grid does the work in '
    'the shape it already had,',
    size: 14,
    fill: _muted,
    anchor: 'middle',
  );
  _text(
    b,
    _width / 2,
    600,
    'and pays for the bookkeeping: measured there, it is the slower pass. '
    'example/README.md has the wall clock.',
    size: 14,
    fill: _muted,
    anchor: 'middle',
  );

  b.writeln('</svg>');
  return b.toString();
}

void _panelChart(
  StringBuffer b, {
  required double left,
  required double right,
  required List<_Row> rows,
  required String title,
  required String caption,
}) {
  final nMin = rows.first.n.toDouble();
  final nMax = rows.last.n.toDouble();
  double x(num n) =>
      left +
      (_log(n) - _log(nMin)) / (_log(nMax) - _log(nMin)) * (right - left);
  double y(num v) =>
      _plotBottom -
      (_log(v) - _log(_yMin)) /
          (_log(_yMax) - _log(_yMin)) *
          (_plotBottom - _plotTop);

  b.writeln('<rect x="$left" y="$_plotTop" width="${right - left}" '
      'height="${_plotBottom - _plotTop}" fill="$_panel"/>');

  _text(b, left, 142, title, size: 18, fill: _ink, weight: '600');
  _text(b, left, 164, caption, size: 13, fill: _muted);

  // Horizontal decade rules.
  for (var decade = 2; decade <= 8; decade++) {
    final value = math.pow(10, decade).toDouble();
    final yy = y(value);
    b.writeln('<line x1="$left" y1="$yy" x2="$right" y2="$yy" '
        'stroke="$_gridLine" stroke-width="1"/>');
    _text(b, left - 10, yy + 4, _compact(value),
        size: 12, fill: _muted, anchor: 'end', family: _mono);
  }

  // Series.
  _series(b, rows, x, y, (r) => r.pair, _amber);
  _series(b, rows, x, y, (r) => r.grid, _teal);

  // Series key, with the measured exponent, in the panel's top-left corner.
  //
  // Anchoring these to the lines themselves was tried twice and abandoned.
  // Both series rise to the right, so a right-anchored label runs back into
  // descending ink: below the grid endpoint it crossed the grid line, and
  // above it it crossed the all-pairs line, which sits under one decade higher
  // on this panel. The top-left corner is empty in both panels by
  // construction, because the smallest population is at the left edge and the
  // axis runs two decades past the largest value plotted.
  final pairSlope = _slope(rows, (r) => r.pair);
  final gridSlope = _slope(rows, (r) => r.grid);
  _key(b, left + 16, _plotTop + 30, _amber, 'every pair', pairSlope);
  _key(b, left + 16, _plotTop + 52, _teal, 'spatial grid', gridSlope);

  // X ticks.
  for (final r in rows) {
    final xx = x(r.n);
    b.writeln('<line x1="$xx" y1="$_plotBottom" x2="$xx" '
        'y2="${_plotBottom + 5}" stroke="$_muted" stroke-width="1"/>');
    _text(b, xx, _plotBottom + 22, '${r.n}',
        size: 12, fill: _muted, anchor: 'middle', family: _mono);
  }
  _text(b, (left + right) / 2, _plotBottom + 44, 'particles',
      size: 13, fill: _muted, anchor: 'middle');
}

void _series(
  StringBuffer b,
  List<_Row> rows,
  double Function(num) x,
  double Function(num) y,
  int Function(_Row) value,
  String colour,
) {
  final points = rows
      .map((r) => '${x(r.n).toStringAsFixed(1)},'
          '${y(value(r)).toStringAsFixed(1)}')
      .join(' ');
  b.writeln('<polyline points="$points" fill="none" stroke="$colour" '
      'stroke-width="2.5" stroke-linejoin="round"/>');
  for (final r in rows) {
    b.writeln('<circle cx="${x(r.n).toStringAsFixed(1)}" '
        'cy="${y(value(r)).toStringAsFixed(1)}" r="4" fill="$colour"/>');
  }
}

/// One row of the per-panel key: a sample of the line, its name, and the
/// exponent least-squares fitted to the points actually drawn.
void _key(StringBuffer b, double x, double y, String colour, String label,
    double slope) {
  b
    ..writeln('<line x1="$x" y1="${y - 4}" x2="${x + 22}" y2="${y - 4}" '
        'stroke="$colour" stroke-width="2.5"/>')
    ..writeln('<circle cx="${x + 11}" cy="${y - 4}" r="3.5" fill="$colour"/>');
  _text(b, x + 32, y, label, size: 13, fill: _ink);
  _text(b, x + 140, y, 'slope ${slope.toStringAsFixed(1)}',
      size: 13, fill: colour, family: _mono);
}

void _text(
  StringBuffer b,
  double x,
  double y,
  String value, {
  required double size,
  required String fill,
  String anchor = 'start',
  String weight = 'normal',
  String family = _sans,
}) {
  b.writeln('<text x="$x" y="$y" font-family="$family" font-size="$size" '
      'fill="$fill" text-anchor="$anchor" font-weight="$weight">'
      '${_escape(value)}</text>');
}

double _log(num v) => math.log(v) / math.ln10;

String _compact(double v) {
  if (v >= 1000000) return '${(v / 1000000).round()}M';
  if (v >= 1000) return '${(v / 1000).round()}k';
  return '${v.round()}';
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

void _require(bool condition, String message) {
  if (!condition) {
    stderr.writeln(message);
    exit(1);
  }
}

String? _which(String binary) {
  final result = Process.runSync('which', [binary]);
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trim();
}
