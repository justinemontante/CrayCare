import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import '../models/crayfish_detection.dart';

/// Loads the crayfish gender TFLite model and runs inference for both the
/// Upload (single image) and Live (camera stream) scan modes.
///
/// Model contract this service expects (trained via the CrayCare YOLOv11
/// Colab notebook, exported with `model.export(format="tflite", int8=True)`):
///   - Asset path: assets/models/crayfish_gender.tflite
///   - Labels file: assets/models/labels.txt (one label per line, in class
///     index order — currently "male" then "female")
///   - Input: 224x224x3, quantized uint8
///   - Output: Ultralytics-style detection head, shape [1, 4 + numClasses, N]
///     (box coords in rows 0-3, per-class scores in the remaining rows,
///     one column per anchor), quantized uint8
///
/// If the .tflite file isn't in assets/models/ yet, [init] fails gracefully
/// and [isReady] stays false — callers should check that before invoking
/// detection methods, and the scan screen shows a "model not ready" state
/// instead of crashing.
class CrayfishDetectionService extends ChangeNotifier {
  static final CrayfishDetectionService instance = CrayfishDetectionService._();
  CrayfishDetectionService._();

  static const String _modelAsset = 'assets/models/crayfish_gender.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';

  // Tune these once real model results come in.
  static const double _confidenceThreshold = 0.45;
  static const double _iouThreshold = 0.45;

  Interpreter? _interpreter;
  List<String> _labels = [];
  int _inputSize = 224;
  bool _isReady = false;
  String? _error;

  bool get isReady => _isReady;
  String? get error => _error;
  List<String> get labels => _labels;

  Future<void> init() async {
    try {
      _labels = (await rootBundle.loadString(_labelsAsset))
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      _interpreter = await Interpreter.fromAsset(_modelAsset);
      final inputShape = _interpreter!.getInputTensor(0).shape; // [1, H, W, 3]
      if (inputShape.length == 4) {
        _inputSize = inputShape[1];
      }

      _isReady = true;
      _error = null;
      debugPrint(
        'CrayfishDetectionService: model loaded. input=${_interpreter!.getInputTensor(0).shape} '
        'output=${_interpreter!.getOutputTensor(0).shape} labels=$_labels',
      );
    } catch (e) {
      // Expected until the .tflite file is added to assets/models/ —
      // fail quietly so the rest of the app keeps working.
      _isReady = false;
      _error = e.toString();
      debugPrint('CrayfishDetectionService: model not ready ($e)');
    }
    notifyListeners();
  }

  /// Runs detection on a single still image (Upload mode).
  Future<List<CrayfishDetection>> detectFromFile(File imageFile) async {
    if (!_isReady) return [];
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return [];
    return _runInference(decoded);
  }

  /// Runs detection on a single camera frame (Live mode).
  ///
  /// Converts the YUV420 camera frame to an RGB image first. This is the
  /// simplest correct approach; if frame rate becomes an issue on real
  /// devices, this is the place to optimize (e.g. skip frames, downscale
  /// before full conversion).
  Future<List<CrayfishDetection>> detectFromCameraImage(CameraImage frame) async {
    if (!_isReady) return [];
    final decoded = _convertYUV420ToImage(frame);
    if (decoded == null) return [];
    return _runInference(decoded);
  }

  List<CrayfishDetection> _runInference(img.Image decoded) {
    final interpreter = _interpreter;
    if (interpreter == null) return [];

    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputParams = inputTensor.params; // QuantizationParams(scale, zeroPoint)
    final outputParams = outputTensor.params;

    // Build quantized uint8 input buffer [1, H, W, 3].
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            _quantize(pixel.r / 255.0, inputParams),
            _quantize(pixel.g / 255.0, inputParams),
            _quantize(pixel.b / 255.0, inputParams),
          ];
        }),
      ),
    );

    final outputShape = outputTensor.shape; // [1, 4+numClasses, N]
    final numChannels = outputShape[1];
    final numAnchors = outputShape[2];
    final numClasses = numChannels - 4;

    final output = List.generate(
      1,
      (_) => List.generate(numChannels, (_) => List.filled(numAnchors, 0)),
    );

    interpreter.run(input, output);

    final candidates = <CrayfishDetection>[];
    for (int i = 0; i < numAnchors; i++) {
      double bestScore = 0;
      int bestClass = -1;
      for (int c = 0; c < numClasses; c++) {
        final raw = output[0][4 + c][i] as int;
        final score = _dequantize(raw, outputParams);
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestClass == -1 || bestScore < _confidenceThreshold) continue;
      if (bestClass >= _labels.length) continue;

      final cx = _dequantize(output[0][0][i] as int, inputParams);
      final cy = _dequantize(output[0][1][i] as int, inputParams);
      final w = _dequantize(output[0][2][i] as int, inputParams);
      final h = _dequantize(output[0][3][i] as int, inputParams);

      candidates.add(CrayfishDetection(
        label: _labels[bestClass],
        confidence: bestScore,
        left: (cx - w / 2).clamp(0.0, 1.0),
        top: (cy - h / 2).clamp(0.0, 1.0),
        right: (cx + w / 2).clamp(0.0, 1.0),
        bottom: (cy + h / 2).clamp(0.0, 1.0),
      ));
    }

    return _nonMaxSuppression(candidates);
  }

  int _quantize(double realValue, QuantizationParams params) {
    if (params.scale == 0) return realValue.round().clamp(0, 255);
    return ((realValue / params.scale) + params.zeroPoint).round().clamp(0, 255);
  }

  double _dequantize(int quantized, QuantizationParams params) {
    if (params.scale == 0) return quantized.toDouble();
    return (quantized - params.zeroPoint) * params.scale;
  }

  List<CrayfishDetection> _nonMaxSuppression(List<CrayfishDetection> boxes) {
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <CrayfishDetection>[];
    for (final box in boxes) {
      final overlapsKept = kept.any((k) => _iou(box, k) > _iouThreshold);
      if (!overlapsKept) kept.add(box);
    }
    return kept;
  }

  double _iou(CrayfishDetection a, CrayfishDetection b) {
    final interLeft = a.left > b.left ? a.left : b.left;
    final interTop = a.top > b.top ? a.top : b.top;
    final interRight = a.right < b.right ? a.right : b.right;
    final interBottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    final interW = (interRight - interLeft).clamp(0.0, 1.0);
    final interH = (interBottom - interTop).clamp(0.0, 1.0);
    final interArea = interW * interH;
    final unionArea = (a.width * a.height) + (b.width * b.height) - interArea;
    if (unionArea <= 0) return 0;
    return interArea / unionArea;
  }

  img.Image? _convertYUV420ToImage(CameraImage frame) {
    try {
      final width = frame.width;
      final height = frame.height;
      final yPlane = frame.planes[0];
      final uPlane = frame.planes[1];
      final vPlane = frame.planes[2];

      final image = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yPlane.bytesPerRow + x;
          final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * (uPlane.bytesPerPixel ?? 1);
          final yVal = yPlane.bytes[yIndex];
          final uVal = uPlane.bytes[uvIndex];
          final vVal = vPlane.bytes[uvIndex];

          final r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
          final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).clamp(0, 255).toInt();
          final b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
          image.setPixelRgb(x, y, r, g, b);
        }
      }
      return image;
    } catch (e) {
      debugPrint('CrayfishDetectionService: frame conversion failed ($e)');
      return null;
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }
}
