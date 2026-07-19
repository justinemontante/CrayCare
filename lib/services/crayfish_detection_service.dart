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
  /// Directly downsamples the YUV420 frame to the target size into a flat
  /// typed list buffer, avoiding expensive intermediate image creation, resizing,
  /// and multi-dimensional array list allocations.
  Future<List<CrayfishDetection>> detectFromCameraImage(CameraImage frame) async {
    if (!_isReady) return [];
    
    final interpreter = _interpreter;
    if (interpreter == null) return [];

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputParams = inputTensor.params;
    final outputParams = outputTensor.params;

    final isFloat32 = inputTensor.type == TensorType.float32;
    final isOutputFloat32 = outputTensor.type == TensorType.float32;

    // Allocate flat input buffer
    final dynamic inputBuffer = isFloat32
        ? Float32List(_inputSize * _inputSize * 3)
        : Uint8List(_inputSize * _inputSize * 3);

    // Directly convert and scale YUV frame to input buffer
    _convertCameraImageToInputBuffer(frame, inputBuffer, isFloat32, inputParams);

    final outputShape = outputTensor.shape; // [1, 4 + numClasses, N]
    final numChannels = outputShape[1];
    final numAnchors = outputShape[2];
    final numClasses = numChannels - 4;

    // Allocate flat output buffer
    final dynamic outputBuffer = isOutputFloat32
        ? Float32List(numChannels * numAnchors)
        : Uint8List(numChannels * numAnchors);

    // Run inference using flat buffers
    interpreter.run(inputBuffer, outputBuffer);

    debugPrint(
      '[Camera] output shape=$outputShape outputType=${outputTensor.type} '
      'scale=${outputParams.scale} zp=${outputParams.zeroPoint}',
    );

    final candidates = <CrayfishDetection>[];
    for (int i = 0; i < numAnchors; i++) {
      double bestScore = 0;
      int bestClass = -1;
      for (int c = 0; c < numClasses; c++) {
        final double score = getOutputValue(4 + c, i, outputBuffer, outputTensor.type, outputParams);
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestClass == -1 || bestScore < _confidenceThreshold) continue;
      if (bestClass >= _labels.length) continue;

      final cx = getOutputValue(0, i, outputBuffer, outputTensor.type, outputParams);
      final cy = getOutputValue(1, i, outputBuffer, outputTensor.type, outputParams);
      final w = getOutputValue(2, i, outputBuffer, outputTensor.type, outputParams);
      final h = getOutputValue(3, i, outputBuffer, outputTensor.type, outputParams);

      debugPrint(
        '[Camera] det #${candidates.length} ${_labels[bestClass]} '
        '${(bestScore * 100).toStringAsFixed(1)}% '
        'box=[${cx.toStringAsFixed(3)}, ${cy.toStringAsFixed(3)}, '
        '${w.toStringAsFixed(3)}, ${h.toStringAsFixed(3)}]',
      );

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

  List<CrayfishDetection> _runInference(img.Image decoded) {
    final interpreter = _interpreter;
    if (interpreter == null) return [];

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputParams = inputTensor.params;
    final outputParams = outputTensor.params;

    final isFloat32 = inputTensor.type == TensorType.float32;
    final isOutputFloat32 = outputTensor.type == TensorType.float32;

    // Resize image to input size
    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

    // Build input buffer
    final dynamic inputBuffer = isFloat32
        ? Float32List(_inputSize * _inputSize * 3)
        : Uint8List(_inputSize * _inputSize * 3);

    int offset = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final rVal = pixel.r / 255.0;
        final gVal = pixel.g / 255.0;
        final bVal = pixel.b / 255.0;

        if (isFloat32) {
          inputBuffer[offset++] = rVal;
          inputBuffer[offset++] = gVal;
          inputBuffer[offset++] = bVal;
        } else {
          inputBuffer[offset++] = _quantize(rVal, inputParams);
          inputBuffer[offset++] = _quantize(gVal, inputParams);
          inputBuffer[offset++] = _quantize(bVal, inputParams);
        }
      }
    }

    final outputShape = outputTensor.shape; // [1, 4 + numClasses, N]
    final numChannels = outputShape[1];
    final numAnchors = outputShape[2];
    final numClasses = numChannels - 4;

    final dynamic outputBuffer = isOutputFloat32
        ? Float32List(numChannels * numAnchors)
        : Uint8List(numChannels * numAnchors);

    interpreter.run(inputBuffer, outputBuffer);

    debugPrint(
      '[Upload] output shape=$outputShape outputType=${outputTensor.type} '
      'scale=${outputParams.scale} zp=${outputParams.zeroPoint}',
    );

    final candidates = <CrayfishDetection>[];
    for (int i = 0; i < numAnchors; i++) {
      double bestScore = 0;
      int bestClass = -1;
      for (int c = 0; c < numClasses; c++) {
        final double score = getOutputValue(4 + c, i, outputBuffer, outputTensor.type, outputParams);
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestClass == -1 || bestScore < _confidenceThreshold) continue;
      if (bestClass >= _labels.length) continue;

      final cx = getOutputValue(0, i, outputBuffer, outputTensor.type, outputParams);
      final cy = getOutputValue(1, i, outputBuffer, outputTensor.type, outputParams);
      final w = getOutputValue(2, i, outputBuffer, outputTensor.type, outputParams);
      final h = getOutputValue(3, i, outputBuffer, outputTensor.type, outputParams);

      debugPrint(
        '[Upload] det #${candidates.length} ${_labels[bestClass]} '
        '${(bestScore * 100).toStringAsFixed(1)}% '
        'box=[${cx.toStringAsFixed(3)}, ${cy.toStringAsFixed(3)}, '
        '${w.toStringAsFixed(3)}, ${h.toStringAsFixed(3)}]',
      );

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

  double getOutputValue(
    int channel,
    int anchor,
    dynamic outputBuffer,
    TensorType type,
    QuantizationParams params,
  ) {
    final numAnchors = _interpreter!.getOutputTensor(0).shape[2];
    final index = channel * numAnchors + anchor;
    if (type == TensorType.float32) {
      return (outputBuffer as Float32List)[index];
    } else {
      final raw = (outputBuffer as Uint8List)[index];
      return _dequantize(raw, params);
    }
  }

  void _convertCameraImageToInputBuffer(
    CameraImage frame,
    dynamic inputBuffer,
    bool isFloat32,
    QuantizationParams inputParams,
  ) {
    final width = frame.width;
    final height = frame.height;
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];

    final double scaleX = width / _inputSize;
    final double scaleY = height / _inputSize;

    int offset = 0;

    for (int ty = 0; ty < _inputSize; ty++) {
      final int y = (ty * scaleY).toInt().clamp(0, height - 1);
      final int yRowOffset = y * yPlane.bytesPerRow;
      final int uvRowOffset = (y ~/ 2) * uPlane.bytesPerRow;

      for (int tx = 0; tx < _inputSize; tx++) {
        final int x = (tx * scaleX).toInt().clamp(0, width - 1);
        final int yIndex = yRowOffset + x;

        final int uvPixelStride = uPlane.bytesPerPixel ?? 1;
        final int uvIndex = uvRowOffset + (x ~/ 2) * uvPixelStride;

        if (yIndex >= yPlane.bytes.length || uvIndex >= uPlane.bytes.length || uvIndex >= vPlane.bytes.length) {
          if (isFloat32) {
            inputBuffer[offset++] = 0.0;
            inputBuffer[offset++] = 0.0;
            inputBuffer[offset++] = 0.0;
          } else {
            inputBuffer[offset++] = 0;
            inputBuffer[offset++] = 0;
            inputBuffer[offset++] = 0;
          }
          continue;
        }

        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];

        final rVal = (yVal + 1.402 * (vVal - 128)).clamp(0.0, 255.0);
        final gVal = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).clamp(0.0, 255.0);
        final bVal = (yVal + 1.772 * (uVal - 128)).clamp(0.0, 255.0);

        if (isFloat32) {
          inputBuffer[offset++] = rVal / 255.0;
          inputBuffer[offset++] = gVal / 255.0;
          inputBuffer[offset++] = bVal / 255.0;
        } else {
          inputBuffer[offset++] = _quantize(rVal / 255.0, inputParams);
          inputBuffer[offset++] = _quantize(gVal / 255.0, inputParams);
          inputBuffer[offset++] = _quantize(bVal / 255.0, inputParams);
        }
      }
    }
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
