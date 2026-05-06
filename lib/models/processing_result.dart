// Final output produced after the full video processing pipeline completes.
//
// Passed from [VideoProcessorService] → [VideoProcessorNotifier] →
// [ResultScreen] for display.
class ProcessingResult {
  /// Total unique bottles the tracker ever created (monotonic high-water mark).
  final int totalBottlesDetected;

  /// How many of those bottles were confirmed as knocked down.
  final int bottlesKnockedDown;

  /// Knock-down percentage (0–100).
  final double scorePercentage;

  /// Absolute path to the annotated output video on disk.
  final String outputVideoPath;

  /// Wall-clock processing time in seconds.
  final int processingTimeSeconds;

  ProcessingResult({
    required this.totalBottlesDetected,
    required this.bottlesKnockedDown,
    required this.outputVideoPath,
    required this.processingTimeSeconds,
  }) : scorePercentage = totalBottlesDetected == 0
            ? 0.0
            : (bottlesKnockedDown / totalBottlesDetected) * 100;

  /// Human-readable summary string, e.g. "Knocked Down: 3/5 (60.0%)".
  String get scoreText =>
      'Knocked Down: $bottlesKnockedDown/$totalBottlesDetected '
      '(${scorePercentage.toStringAsFixed(1)}%)';
}
