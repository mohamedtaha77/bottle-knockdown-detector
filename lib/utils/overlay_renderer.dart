// Draws detection overlays onto each video frame using the `image` package.
//
// Rendering layers (bottom to top):
//  1. Car trajectory polyline (blue).
//  2. Bottle bounding boxes (green = standing, red = fallen).
//  3. Car bounding box (blue).
//  4. Per-bottle labels with three-state background colour:
//     • Green  — stable/standing.
//     • Orange — model has signalled "fallen" at least once but not confirmed.
//     • Red    — confirmed fallen.
//  5. Car label.
//  6. HUD panel — total + knocked counts in the top-left corner.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/bottle.dart';
import '../utils/constants.dart';

class OverlayRenderer {
  /// Annotates [frame] in-place and returns it.
  static img.Image render({
    required img.Image frame,
    required Map<int, Bottle> bottles,
    required Rect? carBox,
    required List<Offset> carTrajectory,
    required int fallenCount,
    required int totalCount,
    double? carConfidence,
  }) {
    final out = frame;

    // Scale stroke thickness relative to frame resolution.
    final boxStroke     = math.max(3, (out.width / 640 * 3).round());
    final carTrajStroke = math.max(6.0, out.width / 640.0 * 6.0);

    // --- Layer 1: Car trajectory ---
    if (carTrajectory.length > 1) {
      _drawPolyline(
          out, carTrajectory, img.ColorRgb8(100, 100, 255), carTrajStroke);
    }

    // --- Layer 2: Bottle bounding boxes ---
    for (final bottle in bottles.values) {
      _drawBox(
        out,
        bottle.boundingBox,
        bottle.isFallen ? img.ColorRgb8(255, 0, 0) : img.ColorRgb8(0, 255, 0),
        boxStroke,
      );
    }

    // --- Layer 3: Car bounding box ---
    if (carBox != null) {
      _drawBox(out, carBox, img.ColorRgb8(0, 100, 255), boxStroke);
    }

    // --- Layer 4: Per-bottle labels ---
    for (final bottle in bottles.values) {
      final label =
          'B#${bottle.id} ${bottle.className} '
          '${bottle.confidence.toStringAsFixed(2)}';

      // Three-state colour: green (standing), orange (signal seen), red (fallen).
      final hasFallenSignal = bottle.fallenWindow.any((x) => x);
      final bg = bottle.isFallen
          ? img.ColorRgb8(200, 0, 0)
          : hasFallenSignal
              ? img.ColorRgb8(220, 140, 0)
              : img.ColorRgb8(0, 160, 0);

      _drawLabel(out, label,
          bottle.boundingBox.left.toInt(), bottle.boundingBox.top.toInt(), bg);
    }

    // --- Layer 5: Car label ---
    if (carBox != null) {
      final confStr =
          carConfidence != null ? ' ${carConfidence.toStringAsFixed(2)}' : '';
      _drawLabel(out, 'CAR$confStr',
          carBox.left.toInt(), carBox.top.toInt(), img.ColorRgb8(0, 80, 200));
    }

    // --- Layer 6: HUD panel (top-left) ---
    final hp   = AppConstants.hudPadding;
    final hl   = AppConstants.hudLineHeight;
    final hudW = math.max(360, (out.width / 1920 * 520).round());
    final hudH = hp * 2 + hl * 2;

    // Semi-transparent black background.
    img.fillRect(out,
        x1: 8, y1: 8, x2: 8 + hudW, y2: 8 + hudH,
        color: img.ColorRgba8(0, 0, 0, 180));

    // "Total: N"
    img.drawString(out, 'Total: $totalCount',
        font: img.arial48, x: 8 + hp, y: 8 + hp,
        color: img.ColorRgb8(255, 255, 255));

    // "Knocked: N"
    img.drawString(out, 'Knocked: $fallenCount',
        font: img.arial48, x: 8 + hp, y: 8 + hp + hl,
        color: img.ColorRgb8(255, 100, 100));

    return out;
  }

  // -------------------------------------------------------------------------
  // Drawing helpers
  // -------------------------------------------------------------------------

  /// Draws a text label with a coloured background rectangle above position
  /// ([bx], [by]).
  static void _drawLabel(
      img.Image image, String text, int bx, int by, img.Color bg) {
    final font = img.arial24;
    const pad = AppConstants.labelTextPadding;
    const th = 24;
    final tw = _measureWidth(text, font);
    final lx = bx;
    final ly = (by - th - pad * 2).clamp(0, image.height - th - pad * 2).toInt();

    img.fillRect(image,
        x1: lx, y1: ly, x2: lx + tw + pad * 2, y2: ly + th + pad * 2,
        color: bg);
    img.drawString(image, text,
        font: font, x: lx + pad, y: ly + pad,
        color: img.ColorRgb8(255, 255, 255));
  }

  /// Measures the pixel width of [s] using bitmap font [f].
  static int _measureWidth(String s, img.BitmapFont f) {
    var w = 0;
    for (final c in s.codeUnits) {
      w += f.characters[c]?.xAdvance ?? 0;
    }
    return w;
  }

  /// Draws a rectangle outline.
  static void _drawBox(
      img.Image image, Rect box, img.Color color, int thickness) {
    img.drawRect(image,
        x1: box.left.toInt(), y1: box.top.toInt(),
        x2: box.right.toInt(), y2: box.bottom.toInt(),
        color: color, thickness: thickness);
  }

  /// Draws a connected line through a list of points.
  static void _drawPolyline(
      img.Image image, List<Offset> points, img.Color color, double thickness) {
    for (int i = 1; i < points.length; i++) {
      img.drawLine(image,
          x1: points[i - 1].dx.toInt(), y1: points[i - 1].dy.toInt(),
          x2: points[i].dx.toInt(), y2: points[i].dy.toInt(),
          color: color, thickness: thickness);
    }
  }
}
