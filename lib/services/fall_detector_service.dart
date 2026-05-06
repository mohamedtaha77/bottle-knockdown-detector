// Detects knocked-down bottles using the fine-tuned model's "fallen" class.
//
// The model has three classes: Car (0), bottle (1), fallen (2).
// When the tracker updates a bottle's [className] to "fallen" (because the
// model detected it as class 2), this service records it in the bottle's
// [fallenWindow] sliding window. Once the model says "fallen" on at least
// [fallenStreakRequired] out of the last [fallenStreakWindow] inference
// frames, the bottle is permanently marked as [BottleState.fallen].
//
// Only bottles with real detections this frame (missedFrames == 0) are
// evaluated — coasting bottles keep their last className and would produce
// stale signals.
import '../models/bottle.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class FallDetectorService {
  /// Evaluate every active bottle on this inference frame.
  void update(Map<int, Bottle> bottles, int frameNumber) {
    for (final b in bottles.values) {
      // Already confirmed fallen — nothing to do.
      if (b.isFallen) continue;

      // Skip coasting bottles — they have stale classNames from their last
      // real detection, which would produce misleading fall signals.
      if (b.missedFrames > 0) continue;

      // Check if the model classified this bottle as "fallen".
      final fallenLike = b.className == AppConstants.fallenClassName;

      // Add the signal to the sliding window.
      b.fallenWindow.add(fallenLike);
      if (b.fallenWindow.length > AppConstants.fallenStreakWindow) {
        b.fallenWindow.removeAt(0);
      }

      // If enough recent frames say "fallen", confirm the knock-down.
      final fallenCount = b.fallenWindow.where((x) => x).length;
      if (fallenCount >= AppConstants.fallenStreakRequired) {
        b.state = BottleState.fallen;
        b.fallenAtFrame = frameNumber;
        appLogger.d('Bottle ${b.id} → fallen at frame $frameNumber '
            '(model classified as "fallen")');
      }
    }
  }

  /// Counts all fallen bottles (including inactive ones) so the HUD number
  /// never decreases when a bottle goes out of view.
  int countFallen(Map<int, Bottle> bottles) =>
      bottles.values.where((b) => b.isFallen).length;
}
