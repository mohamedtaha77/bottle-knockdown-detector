// Data class representing a single tracked bottle across video frames.
//
// Each bottle has a unique [id] assigned by [TrackerService] when it is
// first detected. The tracker updates [boundingBox], [confidence], and
// [className] on every frame where the bottle is re-matched to a
// detection. If the bottle is not detected for a few frames it enters
// "coasting" mode ([missedFrames] > 0) until it exceeds
// [AppConstants.maxMissedFrames] and becomes inactive.
import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// The two possible states of a bottle.
enum BottleState { standing, fallen }

class Bottle {
  /// Unique ID assigned by the tracker (monotonically increasing).
  final int id;

  /// Current state — starts as [standing], changes to [fallen] once the
  /// fall detector confirms the knock-down.
  BottleState state;

  /// Latest bounding box (either from a real detection or interpolated).
  Rect boundingBox;

  /// Rolling history of centroid positions — used for velocity estimation
  /// and for matching detections across frames.
  final List<Offset> centroidHistory;

  /// Average RGB colour sampled from the bounding box region, used by the
  /// tracker's colour-similarity component when matching.
  Color averageColor;

  /// Frame index when this bottle was first created.
  final int firstDetectedFrame;

  /// Frame index of the most recent real (non-interpolated) detection.
  int lastDetectedFrame;

  /// Frame index when the bottle was confirmed fallen (null if still standing).
  int? fallenAtFrame;

  /// Model confidence of the most recent detection.
  double confidence;

  /// Class name from the most recent detection ("bottle" or "fallen").
  String className;

  /// Sliding window of recent fall evaluations — each entry is true if the
  /// model classified the bottle as "fallen" on that inference frame.
  /// Used by [FallDetectorService] to require [fallenStreakRequired]-of-
  /// [fallenStreakWindow] before confirming a fall.
  final List<bool> fallenWindow;

  /// How many consecutive inference frames this bottle has NOT been matched
  /// to any detection. Reset to 0 when re-acquired.
  int missedFrames;

  Bottle({
    required this.id,
    required this.boundingBox,
    required this.firstDetectedFrame,
    this.confidence = 0.0,
    this.className = 'bottle',
  })  : state = BottleState.standing,
        centroidHistory = [],
        averageColor = Colors.white,
        lastDetectedFrame = firstDetectedFrame,
        missedFrames = 0,
        fallenWindow = [];

  /// Whether the fall detector has confirmed this bottle as knocked down.
  bool get isFallen => state == BottleState.fallen;

  /// A bottle is "active" if it was recently detected or is still coasting
  /// (missed fewer than [maxMissedFrames] consecutive inference frames).
  bool get isActive => missedFrames <= AppConstants.maxMissedFrames;

  /// Appends a centroid point, keeping the list bounded to
  /// [AppConstants.maxCentroidHistory].
  void addCentroid(Offset point) {
    centroidHistory.add(point);
    if (centroidHistory.length > AppConstants.maxCentroidHistory) {
      centroidHistory.removeAt(0);
    }
  }

  /// Estimated velocity (pixels per inference frame) derived from the last
  /// two centroid positions. Returns [Offset.zero] if fewer than two points.
  Offset get estimatedVelocity {
    if (centroidHistory.length < 2) return Offset.zero;
    return centroidHistory.last - centroidHistory[centroidHistory.length - 2];
  }
}
