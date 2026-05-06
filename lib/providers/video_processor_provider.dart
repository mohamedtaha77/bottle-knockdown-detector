// Riverpod state management for the video processing pipeline.
//
// [videoProcessorProvider] is the single source of truth for the
// processing lifecycle. The UI watches [ProcessingState] to show the
// correct screen (processing / results / error).
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/processing_result.dart';
import '../services/video_processor_service.dart';

/// The four possible states of the processing lifecycle.
enum ProcessingStatus { idle, running, done, error }

/// Immutable snapshot of the current processing state.
class ProcessingState {
  final ProcessingStatus status;

  /// Live progress (frame count, bottle counts) — only set while [running].
  final VideoProcessingProgress? progress;

  /// Final result — only set when [done].
  final ProcessingResult? result;

  /// Error message — only set when [error].
  final String? errorMessage;

  const ProcessingState({
    required this.status,
    this.progress,
    this.result,
    this.errorMessage,
  });

  const ProcessingState.idle() : this(status: ProcessingStatus.idle);
}

/// Global Riverpod provider for the processing pipeline.
final videoProcessorProvider =
    StateNotifierProvider<VideoProcessorNotifier, ProcessingState>(
  (ref) => VideoProcessorNotifier(),
);

/// StateNotifier that drives [videoProcessorProvider].
///
/// Manages the lifecycle: idle → running (with progress) → done/error → idle.
class VideoProcessorNotifier extends StateNotifier<ProcessingState> {
  VideoProcessorNotifier() : super(const ProcessingState.idle());

  final _service = VideoProcessorService();
  StreamSubscription<VideoProcessingProgress>? _sub;

  /// Starts processing [videoPath]. Updates state with progress snapshots
  /// as frames are processed, and transitions to done/error when complete.
  Future<void> startProcessing(String videoPath) async {
    state = const ProcessingState(status: ProcessingStatus.running);

    // Listen to the progress stream from the service.
    _sub = _service.progress.listen((progress) {
      if (state.status == ProcessingStatus.running) {
        state = ProcessingState(
            status: ProcessingStatus.running, progress: progress);
      }
    });

    try {
      final result = await _service.processVideo(videoPath);
      _sub?.cancel();
      if (state.status == ProcessingStatus.running) {
        state = ProcessingState(status: ProcessingStatus.done, result: result);
      }
    } catch (e) {
      _sub?.cancel();
      if (state.status == ProcessingStatus.running) {
        state = ProcessingState(
            status: ProcessingStatus.error, errorMessage: e.toString());
      }
    }
  }

  /// Cancels the current processing run and resets to idle.
  void cancel() {
    _service.cancel();
    _sub?.cancel();
    state = const ProcessingState.idle();
  }

  /// Resets to idle (e.g. when the user wants to process another video).
  void reset() => state = const ProcessingState.idle();

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
