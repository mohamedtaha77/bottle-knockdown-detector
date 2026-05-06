// Runs YOLOv11s TFLite inference on a single video frame.
//
// Responsibilities:
//  1. Load the .tflite model at startup ([initialize]).
//  2. Letterbox-resize each frame to the model's expected input size.
//  3. Run inference and parse the [1, N, 6] output tensor.
//  4. Apply per-class NMS and return a list of [Detection] objects
//     with coordinates mapped back to the original image space.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/detection.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class DetectorService {
  Interpreter? _interpreter;

  /// The square input size the model expects (read from the model itself).
  late int _inputSize;

  /// Flag to log diagnostic info only on the very first inference call.
  bool _firstInference = true;

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Loads the TFLite model from assets and allocates tensors.
  /// Uses 4 CPU threads for parallelism.
  Future<void> initialize() async {
    final options = InterpreterOptions()..threads = 4;

    _interpreter = await Interpreter.fromAsset(
        AppConstants.yoloModelPath,
        options: options);
    appLogger.i('Detector: initialised with CPU (4 threads)');

    // Read the actual input size from the model tensor (e.g. [1,320,320,3]).
    final inputShape = _interpreter!.getInputTensor(0).shape;
    _inputSize = inputShape[1];

    final outShape = _interpreter!.getOutputTensor(0).shape;
    appLogger.i('Detector init: input=$inputShape output=$outShape '
        'inputSize=$_inputSize');
  }

  // -------------------------------------------------------------------------
  // Inference
  // -------------------------------------------------------------------------

  /// Runs detection on a single decoded [frame] and returns a list of
  /// [Detection] objects with bounding boxes in original-image coordinates.
  List<Detection> detect(img.Image frame) {
    assert(_interpreter != null, 'Call initialize() before detect()');

    // Step 1 — Letterbox the frame to [_inputSize × _inputSize].
    final letterboxed = _letterbox(frame);
    final lb = letterboxed.image;

    // Step 2 — Build the [1, H, W, 3] float32 input tensor (0-1 normalised).
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final p = lb.getPixel(x, y);
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        }),
      ),
    );

    // Step 3 — Validate the output shape is [1, N, 6].
    final outShape = _interpreter!.getOutputTensor(0).shape;
    if (outShape.length != 3 || outShape[2] != 6) {
      appLogger.e('Unexpected output shape $outShape — expected [1,N,6]');
      return const [];
    }
    final numDetections = outShape[1];

    // Step 4 — Allocate output buffer and run inference.
    final output = List.generate(
      1,
      (_) => List.generate(numDetections, (_) => List<double>.filled(6, 0.0)),
    );
    _interpreter!.run(input, output);

    // Step 5 — Convert raw detections to image-space [Detection] objects.
    return _postprocess(
      output[0],
      letterboxed.scale,
      letterboxed.padX,
      letterboxed.padY,
      frame.width.toDouble(),
      frame.height.toDouble(),
    );
  }

  // -------------------------------------------------------------------------
  // Letterboxing
  // -------------------------------------------------------------------------

  /// Resizes [image] into a square canvas of [_inputSize] with black padding,
  /// preserving aspect ratio. Returns the padded image plus the transform
  /// parameters needed to un-map coordinates later.
  _LetterboxResult _letterbox(img.Image image) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // Scale factor that fits the image inside [_inputSize × _inputSize].
    final scale = math.min(_inputSize / imgW, _inputSize / imgH);
    final newW = (imgW * scale).toInt();
    final newH = (imgH * scale).toInt();

    final resized = img.copyResize(image, width: newW, height: newH);

    // Centre the resized image on a black canvas.
    final padX = (_inputSize - newW) ~/ 2;
    final padY = (_inputSize - newH) ~/ 2;
    final canvas = img.Image(width: _inputSize, height: _inputSize);

    for (int y = 0; y < newH; y++) {
      for (int x = 0; x < newW; x++) {
        final pixel = resized.getPixel(x, y);
        canvas.setPixelRgba(
          padX + x, padY + y,
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), pixel.a.toInt(),
        );
      }
    }

    return _LetterboxResult(canvas, scale, padX, padY);
  }

  // -------------------------------------------------------------------------
  // Post-processing
  // -------------------------------------------------------------------------

  /// Filters raw model output by confidence, maps normalised coordinates back
  /// to original image space, and keeps only our three target classes.
  List<Detection> _postprocess(
    List<List<double>> dets,
    double scale,
    int padX,
    int padY,
    double imgW,
    double imgH,
  ) {
    final candidates = <_Candidate>[];
    int aboveConf = 0;
    double maxConfSeen = 0;

    // On first inference, collect ALL detected class IDs for diagnostics.
    final classHits = <int, int>{};

    for (final det in dets) {
      final conf = det[4];
      if (conf > maxConfSeen) maxConfSeen = conf;
      if (conf < AppConstants.yoloConfidenceThreshold) continue;
      aboveConf++;

      final cls = det[5].toInt();

      if (_firstInference) {
        classHits[cls] = (classHits[cls] ?? 0) + 1;
      }

      // Only keep our three classes — ignore anything else.
      if (cls != AppConstants.bottleClassId &&
          cls != AppConstants.fallenClassId &&
          cls != AppConstants.carClassId) {
        continue;
      }

      // Un-map normalised coordinates → original image pixels.
      final x1 = det[0], y1 = det[1], x2 = det[2], y2 = det[3];
      var left   = (x1 * _inputSize - padX) / scale;
      var top    = (y1 * _inputSize - padY) / scale;
      var right  = (x2 * _inputSize - padX) / scale;
      var bottom = (y2 * _inputSize - padY) / scale;

      // Clamp to image bounds.
      left   = left.clamp(0.0, imgW);
      top    = top.clamp(0.0, imgH);
      right  = right.clamp(0.0, imgW);
      bottom = bottom.clamp(0.0, imgH);

      // Skip degenerate boxes.
      if (right <= left || bottom <= top) continue;

      candidates.add(_Candidate(
        left: left, top: top, right: right, bottom: bottom,
        confidence: conf, classId: cls,
      ));
    }

    // Log class distribution once so we can verify the model output.
    if (_firstInference) {
      appLogger.i('DIAG first frame: maxConf=${maxConfSeen.toStringAsFixed(3)} '
          'aboveThreshold=$aboveConf classHits=$classHits');
      _firstInference = false;
    }

    appLogger.d(
      'Postprocess: maxConf=${maxConfSeen.toStringAsFixed(3)} '
      'aboveConf=$aboveConf kept=${candidates.length}',
    );
    return _nms(candidates);
  }

  // -------------------------------------------------------------------------
  // Non-Maximum Suppression
  // -------------------------------------------------------------------------

  /// Per-class greedy NMS: for each class, sort by confidence and suppress
  /// boxes that overlap an already-kept box above [iouThreshold].
  List<Detection> _nms(List<_Candidate> candidates) {
    final result = <Detection>[];

    // Group candidates by class so NMS is applied independently per class.
    final byClass = <int, List<_Candidate>>{};
    for (final c in candidates) {
      byClass.putIfAbsent(c.classId, () => []).add(c);
    }

    for (final entry in byClass.entries) {
      final sorted = entry.value
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      final kept = <_Candidate>[];

      for (final d in sorted) {
        bool suppressed = false;
        for (final k in kept) {
          if (_iou(d, k) > AppConstants.iouThreshold) {
            suppressed = true;
            break;
          }
        }
        if (!suppressed) kept.add(d);
      }

      // Map numeric class ID → human-readable class name.
      final String className;
      if (entry.key == AppConstants.carClassId) {
        className = AppConstants.carClassName;
      } else if (entry.key == AppConstants.fallenClassId) {
        className = AppConstants.fallenClassName;
      } else {
        className = AppConstants.bottleClassName;
      }

      for (final d in kept) {
        result.add(Detection(
          box: Rect.fromLTRB(d.left, d.top, d.right, d.bottom),
          confidence: d.confidence,
          className: className,
        ));
      }
    }
    return result;
  }

  /// Intersection-over-Union between two candidate boxes.
  double _iou(_Candidate a, _Candidate b) {
    final il = math.max(a.left, b.left);
    final it = math.max(a.top, b.top);
    final ir = math.min(a.right, b.right);
    final ib = math.min(a.bottom, b.bottom);
    if (il >= ir || it >= ib) return 0.0;
    final inter = (ir - il) * (ib - it);
    final union = (a.right - a.left) * (a.bottom - a.top) +
        (b.right - b.left) * (b.bottom - b.top) - inter;
    return union == 0 ? 0.0 : inter / union;
  }

  /// Releases the TFLite interpreter.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

// ---------------------------------------------------------------------------
// Internal helper classes
// ---------------------------------------------------------------------------

/// Raw detection candidate before NMS.
class _Candidate {
  final double left, top, right, bottom, confidence;
  final int classId;
  const _Candidate({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
    required this.classId,
  });
}

/// Return type of [_letterbox] — bundles the padded image with the
/// transform parameters needed to un-map coordinates.
class _LetterboxResult {
  final img.Image image;
  final double scale;
  final int padX;
  final int padY;
  _LetterboxResult(this.image, this.scale, this.padX, this.padY);
}
