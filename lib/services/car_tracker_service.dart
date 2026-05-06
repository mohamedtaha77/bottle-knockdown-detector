// Tracks the toy car across frames and records its trajectory.
//
// Unlike bottles (which need multi-object matching), only one car is
// expected at a time. When multiple car detections appear in a frame,
// the one closest to the last known position is selected.
//
// The trajectory (list of centroid points) is never cleared during
// processing, so the car's path remains visible on the overlay even on
// frames where the car isn't detected.
import 'package:flutter/material.dart';
import '../models/detection.dart';
import '../utils/constants.dart';
import '../utils/extensions.dart';

class CarTrackerService {
  /// Last known bounding box — persists even when the car is temporarily lost.
  Rect? _lastKnownBox;

  /// Confidence score of the most recent car detection.
  double? _currentConfidence;

  /// Accumulated list of centroid positions (the car's path).
  final List<Offset> trajectory = [];

  Rect? get currentBox => _lastKnownBox;
  double? get currentConfidence => _currentConfidence;

  /// Called once per inference frame with the full list of detections.
  void update(List<Detection> detections, int frameNumber) {
    final cars = detections.where((d) => d.isCar).toList();

    // No car detected this frame — keep the old box (coasting).
    if (cars.isEmpty) return;

    // Pick the best car detection:
    //  • First detection ever → highest confidence.
    //  • Subsequent frames → closest to last known position.
    final best = _lastKnownBox == null
        ? cars.reduce((a, b) => a.confidence > b.confidence ? a : b)
        : cars.reduce((a, b) {
            final distA = _lastKnownBox!.centroid.distanceTo(a.box.centroid);
            final distB = _lastKnownBox!.centroid.distanceTo(b.box.centroid);
            return distA < distB ? a : b;
          });

    _lastKnownBox = best.box;
    _currentConfidence = best.confidence;

    // Add to trajectory (avoid duplicate consecutive points).
    final centroid = best.box.centroid;
    if (trajectory.isEmpty || trajectory.last != centroid) {
      trajectory.add(centroid);
      if (trajectory.length > AppConstants.maxCentroidHistory) {
        trajectory.removeAt(0);
      }
    }
  }

  /// Resets all state — called when the user processes a new video.
  void reset() {
    _lastKnownBox = null;
    _currentConfidence = null;
    trajectory.clear();
  }
}
