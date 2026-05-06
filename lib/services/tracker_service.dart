// Assigns persistent IDs to bottles and tracks them across frames.
//
// On each inference frame the tracker:
//  1. Matches new detections to existing active bottles using a composite
//     score of IoU, centroid distance, and colour similarity.
//  2. Updates matched bottles with the new bounding box and metadata.
//  3. Interpolates positions for active but unmatched bottles ("coasting").
//  4. Creates new [Bottle] objects for unmatched detections.
//
// The tracker maintains monotonic high-water-mark counters for both total
// bottles detected and fallen bottles, ensuring the HUD numbers never
// decrease even when bottles go inactive.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/bottle.dart';
import '../models/detection.dart';
import '../utils/constants.dart';
import '../utils/extensions.dart';

class TrackerService {
  /// All bottles ever created, keyed by ID.
  final Map<int, Bottle> _bottles = {};

  /// Next ID to assign — only ever increments.
  int _nextId = 0;

  // High-water-mark counters — these NEVER decrease.
  int _peakTotalCount = 0;
  int _peakFallenCount = 0;

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  /// All bottles (including long-lost inactive ones).
  Map<int, Bottle> get bottles => Map.unmodifiable(_bottles);

  /// Only bottles that are currently active (recently detected or coasting).
  Map<int, Bottle> get activeBottles => Map.unmodifiable(
      Map.fromEntries(_bottles.entries.where((e) => e.value.isActive)));

  /// Monotonic total-bottle count.
  int get peakTotalCount => _peakTotalCount;

  /// Monotonic fallen-bottle count.
  int get peakFallenCount => _peakFallenCount;

  /// Called after fall detection to bump the fallen high-water mark.
  void updateFallenCount(int currentFallenCount) {
    if (currentFallenCount > _peakFallenCount) {
      _peakFallenCount = currentFallenCount;
    }
  }

  // ---------------------------------------------------------------------------
  // Per-frame update
  // ---------------------------------------------------------------------------

  /// Core tracking logic — call once per inference frame.
  void update(List<Detection> detections, int frameNumber, img.Image frame) {
    // Filter to bottle-class detections only (includes "fallen" bottles).
    final bottleDetections = detections.where((d) => d.isBottle).toList();

    // First frame — create a new Bottle for every detection.
    if (_bottles.isEmpty) {
      for (final d in bottleDetections) {
        _createBottle(d, frameNumber, frame);
      }
      _updatePeakTotal();
      return;
    }

    // --- Build match score matrix (active bottles × new detections) ---
    final activeList = _bottles.values.where((b) => b.isActive).toList();
    final matched = <int>{};          // bottle IDs that got matched
    final usedDetections = <int>{};   // detection indices that got matched

    final pairs = <_MatchPair>[];
    for (int bi = 0; bi < activeList.length; bi++) {
      for (int di = 0; di < bottleDetections.length; di++) {
        final score = _matchScore(activeList[bi], bottleDetections[di], frame);
        if (score > 0) {
          pairs.add(_MatchPair(
              bottleIndex: bi, detectionIndex: di, score: score));
        }
      }
    }

    // Greedy matching — highest score first.
    pairs.sort((a, b) => b.score.compareTo(a.score));

    for (final pair in pairs) {
      final bottleId = activeList[pair.bottleIndex].id;
      if (matched.contains(bottleId)) continue;
      if (usedDetections.contains(pair.detectionIndex)) continue;

      final bottle = activeList[pair.bottleIndex];
      final det = bottleDetections[pair.detectionIndex];

      // Update the bottle with the new detection data.
      bottle.boundingBox = det.box;
      bottle.confidence = det.confidence;
      bottle.className = det.className;
      bottle.addCentroid(det.box.centroid);
      bottle.lastDetectedFrame = frameNumber;
      bottle.averageColor = _sampleAverageColor(frame, det.box);
      bottle.missedFrames = 0;

      matched.add(bottleId);
      usedDetections.add(pair.detectionIndex);
    }

    // --- Coasting: interpolate positions for unmatched active bottles ---
    for (final bottle in activeList) {
      if (matched.contains(bottle.id)) continue;

      bottle.missedFrames++;

      if (bottle.isActive) {
        // Predict next position using the last velocity vector.
        final vel = bottle.estimatedVelocity;
        final lastBox = bottle.boundingBox;
        final predictedCenter = lastBox.center + vel;
        bottle.boundingBox = Rect.fromCenter(
          center: predictedCenter,
          width: lastBox.width,
          height: lastBox.height,
        );
        bottle.addCentroid(predictedCenter);
      }
    }

    // --- Create new Bottle objects for unmatched detections ---
    for (int di = 0; di < bottleDetections.length; di++) {
      if (!usedDetections.contains(di)) {
        _createBottle(bottleDetections[di], frameNumber, frame);
      }
    }

    _updatePeakTotal();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Bumps the peak total if new bottles were created.
  void _updatePeakTotal() {
    if (_nextId > _peakTotalCount) _peakTotalCount = _nextId;
  }

  /// Composite match score: prioritises keeping existing IDs.
  double _matchScore(Bottle bottle, Detection det, img.Image frame) {
    // Normalise centroid distance by image diagonal.
    final imgDiag = math.sqrt(
        frame.width * frame.width + frame.height * frame.height.toDouble());
    final dist =
        bottle.boundingBox.centroid.distanceTo(det.box.centroid) / imgDiag;

    // Fast-moving or falling bottles get a larger search radius.
    final isLikelyMoving = bottle.estimatedVelocity.distance > 5.0 ||
        bottle.isFallen ||
        det.isFallen;
    final maxDist = isLikelyMoving
        ? AppConstants.centroidMaxDistance * 1.5
        : AppConstants.centroidMaxDistance;

    if (dist > maxDist) return 0.0;

    final iouScore = bottle.boundingBox.iou(det.box);
    final detColor = _sampleAverageColor(frame, det.box);
    final colorSim = _colorSimilarity(bottle.averageColor, detColor);

    // If IoU is low (common during fast motion/blur), rely more on proximity.
    double score = iouScore * 0.4 + (1 - dist) * 0.4 + colorSim * 0.2;

    // Persistence Bonus: if we are sure this is a bottle and it's near,
    // strongly prefer the existing ID over creating a new one.
    if (dist < 0.1) score += 0.3;

    return score;
  }

  /// Samples ~100 evenly-spaced pixels from [box] and returns their average
  /// colour. Used for the colour-similarity component of matching.
  Color _sampleAverageColor(img.Image frame, Rect box) {
    final x0 = box.left.toInt().clamp(0, frame.width - 1);
    final y0 = box.top.toInt().clamp(0, frame.height - 1);
    final x1 = box.right.toInt().clamp(0, frame.width);
    final y1 = box.bottom.toInt().clamp(0, frame.height);

    double r = 0, g = 0, b = 0;
    int count = 0;

    final step = math.max(1, ((x1 - x0) * (y1 - y0) / 100).round());
    for (int y = y0; y < y1; y += step) {
      for (int x = x0; x < x1; x += step) {
        final pixel = frame.getPixel(x, y);
        r += pixel.r.toDouble();
        g += pixel.g.toDouble();
        b += pixel.b.toDouble();
        count++;
      }
    }

    if (count == 0) return Colors.white;
    return Color.fromARGB(
        255, (r / count).round(), (g / count).round(), (b / count).round());
  }

  /// Euclidean distance between two colours in RGB space, normalised to [0,1].
  double _colorSimilarity(Color a, Color b) {
    final dr = a.r - b.r;
    final dg = a.g - b.g;
    final db = a.b - b.b;
    return 1.0 - math.sqrt(dr * dr + dg * dg + db * db) / math.sqrt(3.0);
  }

  /// Creates a brand-new [Bottle] from a detection and adds it to the map.
  void _createBottle(Detection det, int frameNumber, img.Image frame) {
    final id = _nextId++;
    final bottle = Bottle(
      id: id,
      boundingBox: det.box,
      firstDetectedFrame: frameNumber,
      confidence: det.confidence,
      className: det.className,
    );
    bottle.addCentroid(det.box.centroid);
    bottle.averageColor = _sampleAverageColor(frame, det.box);
    _bottles[id] = bottle;
  }

  /// Clears all state — called when the user processes a new video.
  void reset() {
    _bottles.clear();
    _nextId = 0;
    _peakTotalCount = 0;
    _peakFallenCount = 0;
  }
}

/// Internal helper — stores a candidate bottle↔detection pairing with its
/// composite match score for greedy assignment.
class _MatchPair {
  final int bottleIndex, detectionIndex;
  final double score;
  const _MatchPair({
    required this.bottleIndex,
    required this.detectionIndex,
    required this.score,
  });
}
