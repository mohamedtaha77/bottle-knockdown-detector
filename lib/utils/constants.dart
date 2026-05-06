// All configurable constants used across the app.
//
// Centralises magic numbers so they can be tuned from a single place
// without hunting through service code.
class AppConstants {
  // ---------------------------------------------------------------------------
  // Model
  // ---------------------------------------------------------------------------

  /// Path to the fine-tuned YOLOv11s TFLite model (exported with nms=True).
  /// Output tensor shape: [1, N, 6] → [x1, y1, x2, y2, conf, class_id].
  static const String yoloModelPath = 'assets/models/best_float32.tflite';

  /// Minimum confidence a detection must have to be kept.
  static const double yoloConfidenceThreshold = 0.15;

  // ---------------------------------------------------------------------------
  // Class IDs — must match the order in the model's classes.txt
  // ---------------------------------------------------------------------------

  static const int carClassId    = 0;  // "Car"
  static const int bottleClassId = 1;  // "bottle" (standing)
  static const int fallenClassId = 2;  // "fallen" (knocked down)

  static const String carClassName    = 'car';
  static const String bottleClassName = 'bottle';
  static const String fallenClassName = 'fallen';

  // ---------------------------------------------------------------------------
  // Tracking
  // ---------------------------------------------------------------------------

  /// Max centroid points stored per bottle (used for velocity estimation).
  static const int maxCentroidHistory = 300;

  /// IoU threshold for NMS — overlapping boxes above this are suppressed.
  static const double iouThreshold = 0.3;

  /// Maximum normalised centroid distance to consider a match between
  /// a tracked bottle and a new detection (relative to image diagonal).
  static const double centroidMaxDistance = 0.2;

  /// How many consecutive missed frames before a bottle is considered lost.
  static const int maxMissedFrames = 15;

  // ---------------------------------------------------------------------------
  // Fall detection
  // ---------------------------------------------------------------------------

  /// Number of "fallen" signals needed in the sliding window to confirm a fall.
  static const int fallenStreakRequired = 2;

  /// Size of the sliding window (most recent N evaluations).
  static const int fallenStreakWindow = 3;

  // ---------------------------------------------------------------------------
  // Video processing
  // ---------------------------------------------------------------------------

  /// Base frame skip: inference runs every (frameSkip + 1) frames.
  static const int frameSkip = 2;

  // ---------------------------------------------------------------------------
  // Overlay rendering
  // ---------------------------------------------------------------------------

  /// Padding inside per-bottle label backgrounds (pixels).
  static const int labelTextPadding = 4;

  /// Padding inside the HUD panel (pixels).
  static const int hudPadding = 12;

  /// Line height for HUD text rows (pixels).
  static const int hudLineHeight = 48;
}
