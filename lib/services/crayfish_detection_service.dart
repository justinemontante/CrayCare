import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import '../models/crayfish_detection.dart';

/// Loads the crayfish gender TFLite model and runs inference for both the
/// Upload (single image) and Live (camera stream) scan modes.
class CrayfishDetectionService extends ChangeNotifier {
  static final CrayfishDetectionService instance = CrayfishDetectionService._();
  CrayfishDetectionService._();

  static const String _modelAsset = 'assets/models/crayfish_gender.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';

  // Confidence threshold
  static const double _confidenceThreshold = 0.05;
  static const double _iouThreshold = 0.45;

  Interpreter? _interpreter;
  List<String> _labels = [];
  List<CrayfishDetection> _latestDetections = [];

  int _inputSize = 640;
  bool _isReady = false;
  String? _error;

  // Model architecture flags (auto-detected at init)
  bool _inputChannelsFirst = false;
  bool _channelsLast = false;
  int _numChannels = 0;
  int _numAnchors = 0;
  int _numClasses = 0;
  bool _isDetectionModel = false;

  // Public getters
  bool get isReady => _isReady;
  String? get error => _error;
  List<String> get labels => _labels;
  List<CrayfishDetection> get latestDetections => _latestDetections;
  double lastBestScore = 0.0;
  String modelInfo = '';

  Future<void> init() async {
    try {
      // Load labels
      final labelsString = await rootBundle.loadString(_labelsAsset);
      _labels = labelsString
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      debugPrint('═══════════════════════════════════════');
      debugPrint('🔥 LABELS LOADED: $_labels');
      debugPrint('═══════════════════════════════════════');

      // NOTE: threads was previously 4. Multi-threaded CPU execution on this
      // detection model has been observed to trigger a known TFLite/XNNPACK
      // delegate bug ("Input tensor N lacks data" / Bad state: failed
      // precondition) where an internal graph tensor is left unpopulated
      // during subgraph partitioning (see tensorflow/tensorflow#55331 for the
      // same symptom class). Forcing single-threaded execution avoids that
      // code path. If this resolves the crash, we can look at re-enabling
      // multi-threading later once we confirm it's stable on this model.
      final options = InterpreterOptions()..threads = 1;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: options);

      _isReady = true;
      _error = null;

      // Inspect tensor shapes
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      final inputShape = inputTensor.shape;
      final outputShape = outputTensor.shape;
      final inputType = inputTensor.type;
      final outputType = outputTensor.type;

      debugPrint('📊 MODEL TENSOR INFO:');
      debugPrint('  Input shape:   $inputShape');
      debugPrint('  Input type:    $inputType');
      debugPrint(
          '  Input params:  scale=${inputTensor.params.scale}, zp=${inputTensor.params.zeroPoint}');
      debugPrint('  Output shape:  $outputShape');
      debugPrint('  Output type:   $outputType');
      debugPrint(
          '  Output params: scale=${outputTensor.params.scale}, zp=${outputTensor.params.zeroPoint}');
      debugPrint('═══════════════════════════════════════');

      // ── Input layout detection ──────────────────────────────────────────
      if (inputShape.length == 4) {
        if (inputShape[1] == 3) {
          // NCHW format: [1, 3, H, W]
          _inputChannelsFirst = true;
          _inputSize = inputShape[2];
          debugPrint('✅ Input format: NCHW (channels first)');
        } else if (inputShape[3] == 3) {
          // NHWC format: [1, H, W, 3]
          _inputChannelsFirst = false;
          _inputSize = inputShape[1];
          debugPrint('✅ Input format: NHWC (channels last)');
        }
      }

      // ── Output layout detection ─────────────────────────────────────────
      if (outputShape.length == 3) {
        final dim1 = outputShape[1];
        final dim2 = outputShape[2];
        if (dim1 > dim2) {
          // [1, anchors, channels] — e.g. [1, 8400, 6]
          _channelsLast = true;
          _numAnchors = dim1;
          _numChannels = dim2;
        } else {
          // [1, channels, anchors] — YOLOv11 default [1, 6, 8400]
          _channelsLast = false;
          _numChannels = dim1;
          _numAnchors = dim2;
        }
        _numClasses = _numChannels - 4;
        _isDetectionModel = true;
      } else if (outputShape.length == 2) {
        _numClasses = outputShape[1];
        _numAnchors = 1;
        _isDetectionModel = false;
      }

      debugPrint('📐 Model architecture:');
      debugPrint('  Input size:       ${_inputSize}x${_inputSize}');
      debugPrint('  Channels first:   $_inputChannelsFirst');
      debugPrint('  Num anchors:      $_numAnchors');
      debugPrint('  Num channels:     $_numChannels');
      debugPrint('  Num classes:      $_numClasses');
      debugPrint('  Output ch-last:   $_channelsLast');
      debugPrint('  Detection model:  $_isDetectionModel');
      debugPrint('═══════════════════════════════════════');

      modelInfo = '${inputType.name.toUpperCase()} $inputShape';
    } catch (e, stack) {
      _isReady = false;
      _error = e.toString();
      debugPrint('❌ Model init failed: $e');
      debugPrint(stack.toString());
    }
    notifyListeners();
  }

  // ── Public inference API ──────────────────────────────────────────────────

  Future<List<CrayfishDetection>> detectFromFile(File imageFile) async {
    if (!_isReady) return [];
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      debugPrint('❌ [Upload] Failed to decode image');
      return [];
    }
    debugPrint('📸 [Upload] Image: ${decoded.width}x${decoded.height}');
    final detections = _runInference(decoded, '[Upload]');
    _latestDetections = detections;
    notifyListeners();
    return detections;
  }

  Future<List<CrayfishDetection>> detectFromCameraImage(CameraImage frame) async {
    if (!_isReady) return [];
    final decoded = _convertYUV420ToImage(frame);
    if (decoded == null) return [];
    final detections = _runInference(decoded, '[Camera]');
    _latestDetections = detections;
    notifyListeners();
    return detections;
  }

  void clearDetections() {
    _latestDetections = [];
    notifyListeners();
  }

  // ── Core inference ────────────────────────────────────────────────────────

  List<CrayfishDetection> _runInference(img.Image decoded, String tag) {
    final interpreter = _interpreter;
    if (interpreter == null) return [];

    // Resize to model input size
    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final isFloat32 = inputTensor.type == TensorType.float32;

    // ── Build input tensor ─────────────────────────────────────────────────
    dynamic inputBuffer;
    if (_inputChannelsFirst) {
      // NCHW: [1, 3, H, W]
      inputBuffer = List.generate(
        1,
        (_) => List.generate(
          3,
          (c) => List.generate(
            _inputSize,
            (y) => List.generate(_inputSize, (x) {
              final pixel = resized.getPixel(x, y);
              if (isFloat32) {
                if (c == 0) return pixel.r / 255.0;
                if (c == 1) return pixel.g / 255.0;
                return pixel.b / 255.0;
              } else {
                if (c == 0) return pixel.r.toInt();
                if (c == 1) return pixel.g.toInt();
                return pixel.b.toInt();
              }
            }),
          ),
        ),
      );
    } else {
      // NHWC: [1, H, W, 3]
      inputBuffer = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(_inputSize, (x) {
            final pixel = resized.getPixel(x, y);
            if (isFloat32) {
              return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
            } else {
              return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
            }
          }),
        ),
      );
    }

    // ── Build output tensor ────────────────────────────────────────────────
    final outputShape = outputTensor.shape;
    final isOutputFloat32 = outputTensor.type == TensorType.float32;
    dynamic outputBuffer;
    if (outputShape.length == 3) {
      outputBuffer = List.generate(
        outputShape[0],
        (_) => List.generate(
          outputShape[1],
          (_) => isOutputFloat32
              ? List<double>.filled(outputShape[2], 0.0)
              : List<int>.filled(outputShape[2], 0),
        ),
      );
    } else if (outputShape.length == 2) {
      outputBuffer = List.generate(
        outputShape[0],
        (_) => isOutputFloat32
            ? List<double>.filled(outputShape[1], 0.0)
            : List<int>.filled(outputShape[1], 0),
      );
    }

    // ── Run inference ──────────────────────────────────────────────────────
    try {
      interpreter.run(inputBuffer, outputBuffer);
    } catch (e) {
      debugPrint('❌ Inference error: $e');
      return [];
    }

    // ── Flatten output for parsing ─────────────────────────────────────────
    final List<double> flat = [];
    void flatten(dynamic obj) {
      if (obj is List) {
        for (final item in obj) flatten(item);
      } else if (obj is double) {
        flat.add(obj);
      } else if (obj is int) {
        flat.add(obj.toDouble());
      }
    }
    flatten(outputBuffer);

    // ── Debug output ───────────────────────────────────────────────────────
    if (flat.isNotEmpty) {
      double mn = flat[0], mx = flat[0];
      for (final v in flat) {
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
      debugPrint(
          '$tag Output len=${flat.length} min=${mn.toStringAsFixed(4)} max=${mx.toStringAsFixed(4)}');
      debugPrint(
          '$tag First 12: ${flat.take(12).map((v) => v.toStringAsFixed(3)).join(", ")}');

      if (_isDetectionModel) {
        double bestC0 = -999, bestC1 = -999;
        for (int i = 0; i < _numAnchors; i++) {
          final s0 = _readFlat(flat, 4, i);
          final s1 = _numClasses > 1 ? _readFlat(flat, 5, i) : 0.0;
          if (s0 > bestC0) bestC0 = s0;
          if (s1 > bestC1) bestC1 = s1;
        }
        debugPrint(
            '$tag Best raw: class0(female)=${bestC0.toStringAsFixed(4)} class1(male)=${bestC1.toStringAsFixed(4)}');
      }
    }

    return _parseDetections(flat, tag);
  }

  // ── Detection parser ──────────────────────────────────────────────────────

  List<CrayfishDetection> _parseDetections(List<double> output, String tag) {
    if (output.isEmpty) return [];

    if (!_isDetectionModel) {
      // Classification fallback: [score0, score1]
      final s0 = output.isNotEmpty ? output[0] : 0.0;
      final s1 = output.length > 1 ? output[1] : 0.0;
      final bestClass = s0 > s1 ? 0 : 1;
      final bestScore = (bestClass == 0 ? s0 : s1).abs().clamp(0.0, 1.0);
      lastBestScore = bestScore;
      debugPrint(
          '$tag Classification: ${_labels[bestClass]} ${(bestScore * 100).toStringAsFixed(1)}%');
      if (bestClass >= _labels.length) return [];
      return [
        CrayfishDetection(
          label: _labels[bestClass],
          confidence: bestScore,
          left: 0.0,
          top: 0.0,
          right: 1.0,
          bottom: 1.0,
        )
      ];
    }

    final candidates = <CrayfishDetection>[];
    double globalBestScore = 0;
    int aboveThreshold = 0;

    for (int i = 0; i < _numAnchors; i++) {
      double bestScore = 0;
      int bestClass = -1;

      for (int c = 0; c < _numClasses; c++) {
        double score = _readFlat(output, 4 + c, i);
        // Apply sigmoid if values look like raw logits
        if (score < -0.1 || score > 1.1) score = _sigmoid(score);
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }

      if (bestScore > globalBestScore) globalBestScore = bestScore;
      if (bestScore >= _confidenceThreshold) aboveThreshold++;

      // Bounding box (YOLO outputs in pixel space)
      double cx = _readFlat(output, 0, i);
      double cy = _readFlat(output, 1, i);
      double w = _readFlat(output, 2, i);
      double h = _readFlat(output, 3, i);

      // Normalise to 0-1 if values are in pixel space
      if (cx > 1.0 || cy > 1.0 || w > 1.0 || h > 1.0) {
        cx /= _inputSize;
        cy /= _inputSize;
        w /= _inputSize;
        h /= _inputSize;
      }

      if (bestClass == -1 || bestScore < _confidenceThreshold) continue;
      if (bestClass >= _labels.length) continue;

      candidates.add(CrayfishDetection(
        label: _labels[bestClass],
        confidence: bestScore,
        left: (cx - w / 2).clamp(0.0, 1.0),
        top: (cy - h / 2).clamp(0.0, 1.0),
        right: (cx + w / 2).clamp(0.0, 1.0),
        bottom: (cy + h / 2).clamp(0.0, 1.0),
      ));
    }

    debugPrint(
        '$tag ✅ $aboveThreshold anchors above threshold, ${candidates.length} candidates, bestScore=${globalBestScore.toStringAsFixed(4)}');
    lastBestScore = globalBestScore;

    final nms = _nonMaxSuppression(candidates);

    // If NMS removed everything but we have raw detections, return the best one
    if (nms.isEmpty && candidates.isNotEmpty) {
      return [candidates.first];
    }

    return nms;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Read from flat output using [channel, anchor] coordinates.
  double _readFlat(List<double> buf, int channel, int anchor) {
    final int index = _channelsLast
        ? anchor * _numChannels + channel
        : channel * _numAnchors + anchor;
    if (index < 0 || index >= buf.length) return 0.0;
    return buf[index];
  }

  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  List<CrayfishDetection> _nonMaxSuppression(List<CrayfishDetection> boxes) {
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <CrayfishDetection>[];
    for (final box in boxes) {
      if (!kept.any((k) => _iou(box, k) > _iouThreshold)) kept.add(box);
    }
    return kept;
  }

  double _iou(CrayfishDetection a, CrayfishDetection b) {
    final interLeft = math.max(a.left, b.left);
    final interTop = math.max(a.top, b.top);
    final interRight = math.min(a.right, b.right);
    final interBottom = math.min(a.bottom, b.bottom);
    final interW = math.max(0.0, interRight - interLeft);
    final interH = math.max(0.0, interBottom - interTop);
    final interArea = interW * interH;
    final unionArea = (a.width * a.height) + (b.width * b.height) - interArea;
    if (unionArea <= 0) return 0;
    return interArea / unionArea;
  }

  /// Convert Android YUV_420_888 CameraImage to an RGB img.Image.
  img.Image? _convertYUV420ToImage(CameraImage frame) {
    try {
      final width = frame.width;
      final height = frame.height;
      final yPlane = frame.planes[0];
      final uPlane = frame.planes[1];
      final vPlane = frame.planes[2];

      final image = img.Image(width: _inputSize, height: _inputSize);
      final double scaleX = width / _inputSize;
      final double scaleY = height / _inputSize;

      for (int ty = 0; ty < _inputSize; ty++) {
        final int sy = (ty * scaleY).toInt().clamp(0, height - 1);
        for (int tx = 0; tx < _inputSize; tx++) {
          final int sx = (tx * scaleX).toInt().clamp(0, width - 1);
          final yIndex = sy * yPlane.bytesPerRow + sx;
          final uvPixelStride = uPlane.bytesPerPixel ?? 1;
          final uvIndex =
              (sy ~/ 2) * uPlane.bytesPerRow + (sx ~/ 2) * uvPixelStride;

          if (yIndex >= yPlane.bytes.length ||
              uvIndex >= uPlane.bytes.length ||
              uvIndex >= vPlane.bytes.length) {
            image.setPixelRgb(tx, ty, 0, 0, 0);
            continue;
          }

          final yVal = yPlane.bytes[yIndex];
          final uVal = uPlane.bytes[uvIndex];
          final vVal = vPlane.bytes[uvIndex];

          final r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
          final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
              .clamp(0, 255)
              .toInt();
          final b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
          image.setPixelRgb(tx, ty, r, g, b);
        }
      }
      return image;
    } catch (e) {
      debugPrint('❌ YUV conversion failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }
}
