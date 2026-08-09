// Generates doc/params.svg and doc/params.webp, the parameter sweep in the
// README and the first entry under `screenshots:` in the pubspec.
//
//   flutter test tool/param_grid.dart
//
// It is a widget test rather than a script because the thing being pictured is
// the widget: each of the four panels is a real `ConstellationParticles`
// painted by its own painter and captured with `RepaintBoundary.toImage`.
// Redrawing the field from a copy of the layout maths would produce a picture
// of what this file believes the widget does, which is a different and much
// weaker claim.
//
// Labels are added afterwards in SVG. `flutter test` has no real font loaded,
// so text drawn inside the capture would come out as boxes; `rsvg-convert`
// renders it with the system fonts instead.
//
// Both rows use the package's default seed, so the two panels in a row are the
// same field twice and the only difference is the parameter named above them.
// That is the whole point of the picture: it is a controlled comparison, not
// four screenshots.
//
// `rsvg-convert` and `cwebp` are required for the raster output
// (`brew install librsvg webp`); without them the SVG is still written and the
// remaining commands are printed.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:constellation_particles/constellation_particles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two values each swept parameter takes.
const _counts = [60, 200];
const _distances = [80.0, 160.0];

/// Panel size in logical pixels, and the ratio it is captured at. 340 at 2x is
/// 680 device pixels, which `rsvg-convert` then scales to whatever the output
/// width asks for.
const _panel = 340.0;
const _captureRatio = 2.0;

/// Frames to advance before capturing.
///
/// At least one is required rather than tidy: the grid is filled by the
/// ticker, and the very first paint happens before any tick has run, so a
/// capture taken then would show particles with no lines between them — the
/// opposite of what this picture is for. A few more let the field drift off
/// its initial layout.
const _frames = 8;

const _bg = Color(0xFF0A0E14);

void main() {
  testWidgets('parameter sweep', (tester) async {
    final panels = <String, Uint8List>{};
    for (final count in _counts) {
      for (final distance in _distances) {
        panels['$count/$distance'] = await _capture(
          tester,
          ConstellationParticles(
            particleCount: count,
            connectionDistance: distance,
          ),
        );
      }
    }

    final svg = _buildSvg(panels);
    File('doc/params.svg').writeAsStringSync(svg);
    stdout.writeln('wrote doc/params.svg');
    _rasterize();
  });
}

/// Paints [field] on the example app's background and returns it as PNG bytes.
Future<Uint8List> _capture(WidgetTester tester, Widget field) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: _panel,
              height: _panel,
              child: ColoredBox(color: _bg, child: field),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < _frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // `runAsync` is load-bearing, not decoration. A `testWidgets` body runs in a
  // fake-async zone where the real event loop never turns, and both of these
  // futures are completed by the engine rather than by the test clock, so
  // awaiting them directly deadlocks: the tester sits at zero CPU until it is
  // killed. Measured before this call was here.
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _captureRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });

  // Unmount before the next configuration. The field runs a repeating ticker,
  // and the test framework fails a test that ends with one still scheduled.
  await tester.pumpWidget(const SizedBox.shrink());
  return bytes!;
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

const _width = 872.0;
const _height = 900.0;
const _outputWidth = 1000;

/// Left margin wide enough for the row label. `particleCount` set in 13px
/// mono is about 105px, and an earlier 92px margin clipped it to
/// "rticleCount" in the rendered PNG — the kind of defect that only shows up
/// after rasterizing, since the SVG itself happily draws outside the canvas.
const _gridLeft = 136.0;
const _rowLabelRight = 124.0;
const _gridTop = 128.0;
const _gutter = 18.0;

const _ink = '#E2E8F0';
const _muted = '#7D8FA3';
const _teal = '#64FFDA';
const _sans = "'Helvetica Neue', Helvetica, Arial, sans-serif";
const _mono = "'SF Mono', Menlo, Consolas, monospace";

String _buildSvg(Map<String, Uint8List> panels) {
  final b = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="$_width" height="$_height" '
        'viewBox="0 0 $_width $_height">')
    ..writeln('<rect width="$_width" height="$_height" fill="#0A0E14"/>');

  _text(b, 36, 50, 'Two parameters, one field',
      size: 27, fill: _ink, weight: '600');
  _text(
    b,
    36,
    78,
    'Both rows are the same particles at the default seed. Only the linking '
    'distance changes across a row.',
    size: 15,
    fill: _muted,
  );

  for (var col = 0; col < _distances.length; col++) {
    final x = _gridLeft + col * (_panel + _gutter) + _panel / 2;
    _text(b, x, 116, 'connectionDistance: ${_distances[col].toInt()}',
        size: 15, fill: _teal, anchor: 'middle', family: _mono);
  }

  for (var row = 0; row < _counts.length; row++) {
    final y = _gridTop + row * (_panel + _gutter);
    _text(b, _rowLabelRight, y + _panel / 2 - 6, 'particleCount',
        size: 13, fill: _muted, anchor: 'end', family: _mono);
    _text(b, _rowLabelRight, y + _panel / 2 + 14, '${_counts[row]}',
        size: 19, fill: _teal, anchor: 'end', family: _mono, weight: '600');

    for (var col = 0; col < _distances.length; col++) {
      final x = _gridLeft + col * (_panel + _gutter);
      final png = panels['${_counts[row]}/${_distances[col]}']!;
      b
        ..writeln('<image x="$x" y="$y" width="$_panel" height="$_panel" '
            'xlink:href="data:image/png;base64,${base64Encode(png)}"/>')
        ..writeln('<rect x="$x" y="$y" width="$_panel" height="$_panel" '
            'fill="none" stroke="#1B2635" stroke-width="1"/>');
    }
  }

  _text(
    b,
    36,
    _height - 42,
    'Raising the count multiplies lines faster than particles: the panels '
    'below hold 3.3x the particles of the ones',
    size: 14,
    fill: _muted,
  );
  _text(
    b,
    36,
    _height - 22,
    'above them. Cost is set by the lines, so reach for connectionDistance '
    'before particleCount.',
    size: 14,
    fill: _muted,
  );

  b.writeln('</svg>');
  return b.toString();
}

/// Rasterizes the SVG and encodes it as WebP.
///
/// WebP rather than PNG, and lossy rather than lossless, because of what this
/// particular picture is made of: four rendered particle fields are thousands
/// of anti-aliased hairlines, which is high-entropy content that a palette
/// cannot compress. Measured on this image at 1000px: PNG quantized to 128
/// colours 174 KB, lossless WebP 453 KB, WebP q80 **58 KB**.
///
/// Lossy was checked rather than assumed, because the same trick fails badly
/// on the animated demo: encoding that GIF at q60 erases most of the
/// connecting lines, which are the whole subject. Here it does not. Counting
/// pixels brighter than the background, q80 keeps 98.8% of them, and an
/// 18x-amplified difference against the original puts all of the error on line
/// and glyph edges with the flat ground untouched — softening, not signal
/// loss. The difference between the two cases is inter-frame prediction, not
/// the codec.
void _rasterize() {
  final rsvg = _which('rsvg-convert');
  if (rsvg == null) {
    stdout.writeln('rsvg-convert not on PATH; to rasterize:\n'
        '  rsvg-convert -w $_outputWidth doc/params.svg -o /tmp/params.png\n'
        '  cwebp -q $_quality -m 6 /tmp/params.png -o doc/params.webp');
    return;
  }
  final png = File('${Directory.systemTemp.path}/params_render.png');
  _run(rsvg, ['-w', '$_outputWidth', 'doc/params.svg', '-o', png.path]);

  final cwebp = _which('cwebp');
  if (cwebp == null) {
    stdout.writeln('cwebp not on PATH (`brew install webp`); rendered PNG '
        'left at ${png.path}');
    return;
  }
  _run(cwebp, [
    '-quiet',
    '-q',
    '$_quality',
    '-m',
    '6',
    png.path,
    '-o',
    'doc/params.webp'
  ]);

  final before = png.lengthSync();
  final after = File('doc/params.webp').lengthSync();
  png.deleteSync();
  stdout.writeln('wrote doc/params.webp (${_kb(before)} PNG -> ${_kb(after)} '
      'WebP q$_quality, ${_outputWidth}px wide)');
}

const _quality = 80;

String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

void _run(String binary, List<String> args) {
  final result = Process.runSync(binary, args);
  if (result.exitCode != 0) {
    stderr.writeln('$binary failed: ${result.stderr}');
    exit(result.exitCode);
  }
}

String? _which(String binary) {
  final result = Process.runSync('which', [binary]);
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trim();
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
      '${value.replaceAll('&', '&amp;').replaceAll('<', '&lt;')}</text>');
}
