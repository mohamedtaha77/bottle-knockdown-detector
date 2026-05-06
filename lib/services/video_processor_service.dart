// Orchestrates the full video processing pipeline.
//
// NEW ARCHITECTURE (fast):
//  1. Extract frames at 5fps, resized to 640px via native Android code.
//     → 80 frames for a 16s video instead of 480 (6× fewer).
//  2. For each frame: Dart decodes small JPEG → TFLite inference → track.
//     → No per-frame Dart image encoding/overlay (saves ~30ms/frame).
//  3. Collect annotation metadata (boxes, labels, car, HUD) per frame.
//  4. Single native call: annotateAndEncode draws overlays using Android
//     Canvas and encodes to H.264 directly — hardware accelerated.
//
// Result: 16s video ~30–60s instead of ~20 minutes.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/bottle.dart';
import '../models/processing_result.dart';
import '../services/detector_service.dart';
import '../services/tracker_service.dart';
import '../services/fall_detector_service.dart';
import '../services/car_tracker_service.dart';

import '../utils/logger.dart';

/// Snapshot of processing progress — sent to the UI on every frame.
class VideoProcessingProgress {
  final int currentFrame;
  final int totalFrames;
  final int bottlesDetected;
  final int bottlesFallen;

  const VideoProcessingProgress({
    required this.currentFrame,
    required this.totalFrames,
    this.bottlesDetected = 0,
    this.bottlesFallen = 0,
  });

  double get percentage =>
      totalFrames == 0 ? 0.0 : currentFrame / totalFrames * 100;
}

class VideoProcessorService {
  static const _channel = MethodChannel('com.dsai352.bottleknockdown/video');

  final _progressController =
      StreamController<VideoProcessingProgress>.broadcast();
  Stream<VideoProcessingProgress> get progress => _progressController.stream;

  bool _cancelled = false;

  // Extraction settings — 5fps with 640px max dimension.
  static const int _extractFps = 5;
  static const int _extractMaxDim = 640;

  // -------------------------------------------------------------------------
  // Main entry point
  // -------------------------------------------------------------------------

  Future<ProcessingResult> processVideo(String inputPath) async {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    final tempDir = await getTemporaryDirectory();
    final id = DateTime.now().millisecondsSinceEpoch;
    final framesDir = Directory('${tempDir.path}/frames_$id');
    await framesDir.create();

    try {
      // Step 1 — Extract at 5fps, resized to 640px (native, fast).
      appLogger.i('Extracting at ${_extractFps}fps / ${_extractMaxDim}px...');
      final totalFrames = await _channel.invokeMethod<int>('extractFrames', {
        'videoPath': inputPath,
        'outputDir': framesDir.path,
        'fps': _extractFps,
        'maxDim': _extractMaxDim,
      }) ?? 0;
      if (totalFrames == 0) throw Exception('Frame extraction returned 0 frames');
      appLogger.i('Extracted $totalFrames frames');

      // Step 2 — Initialise services.
      final detector     = DetectorService();
      final tracker      = TrackerService();
      final fallDetector = FallDetectorService();
      final carTracker   = CarTrackerService();
      await detector.initialize();

      final frameFiles = framesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      appLogger.i('Processing ${frameFiles.length} frames...');

      // Per-frame annotation metadata to send to native at the end.
      final annotations = <Map<String, dynamic>>[];

      // Step 3 — Inference loop (no Dart image rendering).
      for (int i = 0; i < frameFiles.length; i++) {
        if (_cancelled) break;

        final bytes = await frameFiles[i].readAsBytes();
        final frame = img.decodeJpg(bytes);
        if (frame == null) continue;

        // Run inference + tracking on every extracted frame (all are 5fps).
        try {
          final detections = detector.detect(frame);
          tracker.update(detections, i, frame);
          fallDetector.update(tracker.bottles, i);
          tracker.updateFallenCount(fallDetector.countFallen(tracker.bottles));
          carTracker.update(detections, i);
        } catch (e, st) {
          appLogger.e('Inference failed frame $i: $e\n$st');
        }

        // Build annotation metadata for this frame (no image ops — just data).
        annotations.add(_buildAnnotation(
          frameIndex: i,
          bottles: tracker.activeBottles,
          carTracker: carTracker,
          fallenCount: tracker.peakFallenCount,
          totalCount: tracker.peakTotalCount,
        ));

        // Report progress.
        _progressController.add(VideoProcessingProgress(
          currentFrame: i + 1,
          totalFrames: frameFiles.length,
          bottlesDetected: tracker.peakTotalCount,
          bottlesFallen: tracker.peakFallenCount,
        ));

        await Future.delayed(Duration.zero);
      }

      detector.dispose();

      // Step 4 — Native annotate + encode (Android Canvas + MediaCodec).
      final outputPath = '${tempDir.path}/output_$id.mp4';
      appLogger.i('Native annotate+encode → $outputPath');
      await _channel.invokeMethod('annotateAndEncode', {
        'framesDir': framesDir.path,
        'outputPath': outputPath,
        'fps': _extractFps,
        'annotations': annotations,
      });

      return ProcessingResult(
        totalBottlesDetected: tracker.peakTotalCount,
        bottlesKnockedDown: tracker.peakFallenCount,
        outputVideoPath: outputPath,
        processingTimeSeconds: stopwatch.elapsed.inSeconds,
      );
    } finally {
      stopwatch.stop();
      await framesDir.delete(recursive: true);
    }
  }

  // -------------------------------------------------------------------------
  // Annotation builder
  // -------------------------------------------------------------------------

  /// Converts the current tracking state into a plain-Dart map that can be
  /// sent over MethodChannel to the native annotation renderer.
  Map<String, dynamic> _buildAnnotation({
    required int frameIndex,
    required Map<int, Bottle> bottles,
    required CarTrackerService carTracker,
    required int fallenCount,
    required int totalCount,
  }) {
    // Serialize bounding boxes with colour.
    final boxes = bottles.values.map((b) {
      // Colour: red = fallen, orange = signal seen, green = standing.
      final hasFallenSignal = b.fallenWindow.any((x) => x);
      final int cr, cg, cb;
      if (b.isFallen) { cr = 220; cg = 0;   cb = 0;   }
      else if (hasFallenSignal) { cr = 220; cg = 140; cb = 0; }
      else { cr = 0; cg = 210; cb = 0; }

      return <String, dynamic>{
        'l': b.boundingBox.left,
        't': b.boundingBox.top,
        'r': b.boundingBox.right,
        'b': b.boundingBox.bottom,
        'label': 'B#${b.id} ${b.className} '
            '${b.confidence.toStringAsFixed(2)}',
        'cr': cr, 'cg': cg, 'cb': cb,
      };
    }).toList();

    // Car box.
    Map<String, dynamic>? carMap;
    if (carTracker.currentBox != null) {
      final c = carTracker.currentBox!;
      carMap = {'l': c.left, 't': c.top, 'r': c.right, 'b': c.bottom};
    }

    // Car trajectory (flat list of x,y pairs — last 80 points max).
    final traj = carTracker.trajectory
        .skip((carTracker.trajectory.length - 80).clamp(0, 99999))
        .expand((p) => [p.dx, p.dy])
        .toList();

    return {
      'idx': frameIndex,
      'boxes': boxes,
      if (carMap != null) 'car': carMap,
      'traj': traj,
      'fallen': fallenCount,
      'total': totalCount,
    };
  }

  void cancel() => _cancelled = true;
  void dispose() => _progressController.close();
}
