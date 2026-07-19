import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import '../models/crayfish_detection.dart';

/// Loads the crayfish gender TFLite model and runs inference for both the
/// Upload (single image) and Live (camera stream) scan modes.
///
/// Supports two common YOLO TFLite output layouts:
///   - Channels-first: [1, 4+nc, N] (box coords + class scores, N anchors)
///   - Channels-last:  [1, N, 4+nc] (transposed)
///
/// Also supports classification-only output [1, nc] (no bounding boxes).
///
/// If the .tflite file isn't in assets/models/ yet, [init] fails gracefully
/// and [isReady] stays false.
class CrayfishDetectionService extends ChangeNotifier {
  static final CrayfishDetectionService instance = CrayfishDetectionService._();
  CrayfishDetectionService._();

  static const String _modelAsset = 'assets/models/crayfish_gender.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';

  static const double _confidenceThreshold = 0.25;
  static const double _iouThreshold = 0.45;

  Interpreter? _interpreter;
  List<String> _labels = [];
  int _inputSize = 224;
  bool _isReady = false;
  String? _error;

  // Output layout: set once during init based on model tensor shape.
  bool _channelsLast = false;
  int _numChannels = 0;
  int _numAnchors = 0;
  int _numClasses = 0;
  bool _isDetectionModel = false;

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
      final inputShape = _interpreter!.getInputTensor(0).shape;
      if (inputShape.length == 4) {
        _inputSize = inputShape[1];
      }

      // --- Detect output layout ---
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('CrayfishDetectionService: input=$inputShape output=$outputShape labels=$_labels');

      if (outputShape.length == 3) {
        // Detection model: [1, C, N] or [1, N, C]
        final dim1 = outputShape[1];
        final dim2 = outputShape[2];
        if (dim1 > dim2) {
          // e.g. [1, 8400, 6] → channels-last
          _channelsLast = true;
          _numAnchors = dim1;
          _numChannels = dim2;
        } else {
          // e.g. [1, 6, 8400] → channels-first
          _channelsLast = false;
          _numChannels = dim1;
          _numAnchors = dim2;
        }
        _numClasses = _numChannels - 4;
        _isDetectionModel = true;
      } else if (outputShape.length == 2) {
        // Classification model: [1, nc] — no bounding boxes
        _numClasses = outputShape[1];
        _numAnchors = 1;
        _isDetectionModel = false;
      }

      debugPrint(
        'CrayfishDetectionService: layout=${_channelsLast ? "channels-last" : "channels-first"} '
        'channels=$_numChannels anchors=$_numAnchors classes=$_numClasses '
        'isDetection=$_isDetectionModel',
      );

      _isReady = true;
      _error = null;
    } catch (e) {
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

    final dynamic inputBuffer = isFloat32
        ? Float32List(_inputSize * _inputSize * 3)
        : Uint8List(_inputSize * _inputSize * 3);

    _convertCameraImageToInputBuffer(frame, inputBuffer, isFloat32, inputParams);

    final totalOutput = _numChannels * _numAnchors;
    final dynamic outputBuffer = isOutputFloat32
        ? Float32List(totalOutput)
        : Uint8List(totalOutput);

    interpreter.run(inputBuffer, outputBuffer);

    debugPrint(
      '[Camera] output raw=${outputTensor.shape} type=${outputTensor.type} '
      'scale=${outputParams.scale} zp=${outputParams.zeroPoint}',
    );

    return _parseDetections(outputBuffer, outputTensor.type, outputParams, '[Camera]');
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

    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

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

    final totalOutput = _numChannels * _numAnchors;
    final dynamic outputBuffer = isOutputFloat32
        ? Float32List(totalOutput)
        : Uint8List(totalOutput);

    interpreter.run(inputBuffer, outputBuffer);

    debugPrint(
      '[Upload] output raw=${outputTensor.shape} type=${outputTensor.type} '
      'scale=${outputParams.scale} zp=${outputParams.zeroPoint}',
    );

    return _parseDetections(outputBuffer, outputTensor.type, outputParams, '[Upload]');
  }

  /// Shared output-parsing logic for both camera and upload paths.
  List<CrayfishDetection> _parseDetections(
    dynamic outputBuffer,
    TensorType outputType,
    QuantizationParams outputParams,
    String tag,
  ) {
    // --- Classification-only model: no bounding boxes ---
    if (!_isDetectionModel) {
      final double score0 = _readOutput(outputBuffer, outputType, outputParams, 0, 0);
      final double score1 = _readOutput(outputBuffer, outputType, outputParams, 1, 0);
      final int bestClass = score0 > score1 ? 0 : 1;
      final double bestScore = bestClass == 0 ? score0 : score1;
      debugPrint('$tag classification: [$score0, $score1] → ${_labels[bestClass]} ${(bestScore * 100).toStringAsFixed(1)}%');
      if (bestScore < _confidenceThreshold || bestClass >= _labels.length) return [];
      return [CrayfishDetection(
        label: _labels[bestClass],
        confidence: bestScore,
        left: 0.0, top: 0.0, right: 1.0, bottom: 1.0,
      )];
    }

    // --- Detection model ---
    final candidates = <CrayfishDetection>[];
    int aboveThreshold = 0;

    for (int i = 0; i < _numAnchors; i++) {
      double bestScore = 0;
      int bestClass = -1;
      for (int c = 0; c < _numClasses; c++) {
        final double score = _readOutput(outputBuffer, outputType, outputParams, 4 + c, i);
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestScore >= _confidenceThreshold) aboveThreshold++;

      if (bestClass == -1 || bestScore < _confidenceThreshold) continue;
      if (bestClass >= _labels.length) continue;

      final cx = _readOutput(outputBuffer, outputType, outputParams, 0, i);
      final cy = _readOutput(outputBuffer, outputType, outputParams, 1, i);
      final w = _readOutput(outputBuffer, outputType, outputParams, 2, i);
      final h = _readOutput(outputBuffer, outputType, outputParams, 3, i);

      debugPrint(
        '$tag det #${candidates.length} ${_labels[bestClass]} '
        '${(bestScore * 100).toStringAsFixed(1)}% '
        'raw=[cx=${cx.toStringAsFixed(4)} cy=${cy.toStringAsFixed(4)} '
        'w=${w.toStringAsFixed(4)} h=${h.toStringAsFixed(4)}]',
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

    debugPrint('$tag: $aboveThreshold anchors above threshold, ${candidates.length} after NMS');

    // Log a few raw values from the first anchor for debugging
    if (_numAnchors > 0) {
      final rawVals = <String>[];
      for (int ch = 0; ch < _numChannels; ch++) {
        rawVals.add('ch$ch=${_readOutput(outputBuffer, outputType, outputParams, ch, 0).toStringAsFixed(4)}');
      }
      debugPrint('$tag anchor0 raw: ${rawVals.join(' ')}');
    }

    return _nonMaxSuppression(candidates);
  }

  /// Read a single value from the flat output buffer.
  ///
  /// For channels-first [1, C, N]:  index = channel * N + anchor
  /// For channels-last  [1, N, C]:  index = anchor * C + channel
  double _readOutput(
    dynamic buffer,
    TensorType type,
    QuantizationParams params,
    int channel,
    int anchor,
  ) {
    final int index = _channelsLast
        ? anchor * _numChannels + channel
        : channel * _numAnchors + anchor;

    if (type == TensorType.float32) {
      return (buffer as Float32List)[index];
    } else {
      final raw = (buffer as Uint8List)[index];
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

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }
}
