// A single object detection returned by [DetectorService].
//
// Contains the bounding box in original-image coordinates, the model's
// confidence score, and the human-readable class name.
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class Detection {
  /// Bounding box in original (un-letterboxed) image pixel coordinates.
  final Rect box;

  /// Model confidence for this detection (0.0 – 1.0).
  final double confidence;

  /// Human-readable class name: "car", "bottle", or "fallen".
  final String className;

  const Detection({
    required this.box,
    required this.confidence,
    required this.className,
  });

  /// True for BOTH standing ("bottle") and knocked-down ("fallen") bottles.
  /// The tracker treats them as the same trackable object type.
  bool get isBottle =>
      className == AppConstants.bottleClassName ||
      className == AppConstants.fallenClassName;

  /// True only for car detections.
  bool get isCar => className == AppConstants.carClassName;
}
