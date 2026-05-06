// Convenience extensions used by the tracker and overlay renderer.
import 'package:flutter/material.dart';

extension RectExtensions on Rect {
  /// Centre point of the rectangle.
  Offset get centroid => Offset(left + width / 2, top + height / 2);

  /// Intersection-over-Union — measures how much two boxes overlap.
  /// Returns 0.0 (no overlap) to 1.0 (identical boxes).
  double iou(Rect other) {
    final intersection = intersect(other);
    if (intersection.isEmpty) return 0.0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        width * height + other.width * other.height - intersectionArea;
    return unionArea == 0 ? 0.0 : intersectionArea / unionArea;
  }
}

extension OffsetExtensions on Offset {
  /// Euclidean distance between this point and [other].
  double distanceTo(Offset other) => (this - other).distance;
}
