import 'dart:io';
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

  static const double _confidenceThreshold = 0.15;
  static const double _iouThreshold = 0.45;
  static const bool _inputBGR = false;

  static const List<double> _normMean = [0.0, 0.0, 0.0];
  static const List<double> _normStd = [1.0, 1.0, 1.0];

  Interpreter? _interpreter;
  List<String> _labels = [];
  int _inputSize = 224;
  bool _isReady = false;
  String? _error;

  bool _inputChannelsFirst = false;

  bool _channelsLast = false;
  int _numChannels = 0;
  int _numAnchors = 0;
  int _numClasses = 0;
  bool _isDetectionModel = false;

  bool get isReady => _isReady;
  String? get error => _error;
  List<String> get labels => _labels;
  double lastBestScore = 0.0;
  String modelInfo = '';

  Future<void> init() async {
    try {
      _labels = (await rootBundle.loadString(_labelsAsset))
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      _interpreter = await Interpreter.fromAsset(_modelAsset);

      _isReady = true;
      _error = null;

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final inputType = _interpreter!.getInputTensor(0).type;
      final outputType = _interpreter!.getOutputTensor(0).type;

      if (inputShape.length == 4) {
        if (inputShape[1] <= 4 && inputShape[3] > 4) {
          _inputChannelsFirst = true;
          _inputSize = inputShape[2];
        } else {
          _inputChannelsFirst = false;
          _inputSize = inputShape[1];
        }
      }

      if (outputShape.length == 3) {
        final dim1 = outputShape[1];
        final dim2 = outputShape[2];
        if (dim1 > dim2) {
          _channelsLast = true;
          _numAnchors = dim1;
          _numChannels = dim2;
        } else {
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

      debugPrint(
        'CrayfishDetectionService: model loaded.\n'
        '  input shape=$inputShape type=$inputType channelsFirst=$_inputChannelsFirst\n'
        '  output shape=$outputShape type=$outputType\n'
        '  inputSize=$_inputSize labels=$_labels',
      );

      modelInfo = '${inputType.name.toUpperCase()} $inputShape';
    } catch (e) {
      _isReady = false;
      _error = e.toString();
      debugPrint('CrayfishDetectionService: model not ready ($e)');
    }
    notifyListeners();
  }

  Future<List<CrayfishDetection>> detectFromFile(File imageFile) async {
    if (!_isReady) return [];
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      debugPrint('[Upload] Failed to decode image');
      return [];
    }
    debugPrint('[Upload] Decoded image: ${decoded.width}x${decoded.height}');
    return _runInference(decoded, '[Upload]');
  }

  Future<List<CrayfishDetection>> detectFromCameraImage(CameraImage frame) async {
    if (!_isReady) return [];
    final decoded = _convertYUV420ToImage(frame);
    if (decoded == null) return [];
    return _runInference(decoded, '[Camera]');
  }

  List<CrayfishDetection> _runInference(img.Image decoded, String tag) {
    final interpreter = _interpreter;
    if (interpreter == null) return [];

    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputParams = inputTensor.params;
    final isFloat32 = inputTensor.type == TensorType.float32;

    final dynamic inputBuffer = isFloat32
        ? Float32List(_inputSize * _inputSize * 3)
        : Uint8List(_inputSize * _inputSize * 3);

    final int plane = _inputSize * _inputSize;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final double rVal;
        final double gVal;
        final double bVal;
        if (isFloat32) {
          rVal = (pixel.r / 255.0 - _normMean[0]) / _normStd[0];
          gVal = (pixel.g / 255.0 - _normMean[1]) / _normStd[1];
          bVal = (pixel.b / 255.0 - _normMean[2]) / _normStd[2];
        } else {
          rVal = pixel.r.toDouble();
          gVal = pixel.g.toDouble();
          bVal = pixel.b.toDouble();
        }
        final double ch1Val;
        final double ch2Val;
        final double ch3Val;
        if (_inputBGR) {
          ch1Val = bVal;
          ch2Val = gVal;
          ch3Val = rVal;
        } else {
          ch1Val = rVal;
          ch2Val = gVal;
          ch3Val = bVal;
        }
        if (_inputChannelsFirst) {
          final int pixelIndex = y * _inputSize + x;
          if (isFloat32) {
            inputBuffer[pixelIndex] = ch1Val;
            inputBuffer[plane + pixelIndex] = ch2Val;
            inputBuffer[2 * plane + pixelIndex] = ch3Val;
          } else {
            inputBuffer[pixelIndex] = _quantize(ch1Val, inputParams);
            inputBuffer[plane + pixelIndex] = _quantize(ch2Val, inputParams);
            inputBuffer[2 * plane + pixelIndex] = _quantize(ch3Val, inputParams);
          }
        } else {
          final int offset = (y * _inputSize + x) * 3;
          if (isFloat32) {
            inputBuffer[offset] = ch1Val;
            inputBuffer[offset + 1] = ch2Val;
            inputBuffer[offset + 2] = ch3Val;
          } else {
            inputBuffer[offset] = _quantize(ch1Val, inputParams);
            inputBuffer[offset + 1] = _quantize(ch2Val, inputParams);
            inputBuffer[offset + 2] = _quantize(ch3Val, inputParams);
          }
        }
      }
    }

    final totalOutput = _numChannels * _numAnchors;
    final isOutputFloat32 = outputTensor.type == TensorType.float32;
    final dynamic outputBuffer = isOutputFloat32
        ? Float32List(totalOutput)
        : Uint8List(totalOutput);

    interpreter.run(inputBuffer, outputBuffer);

    debugPrint(
      '$tag output raw=${outputTensor.shape} type=${outputTensor.type} '
      'scale=${outputTensor.params.scale} zp=${outputTensor.params.zeroPoint}',
    );

    if (isOutputFloat32) {
      final buf = outputBuffer as Float32List;
      double mn = buf[0], mx = buf[0];
      for (int i = 1; i < buf.length; i++) {
        if (buf[i] < mn) mn = buf[i];
        if (buf[i] > mx) mx = buf[i];
      }
      debugPrint('$tag output range: min=${mn.toStringAsFixed(6)} max=${mx.toStringAsFixed(6)} len=${buf.length}');
      if (!_isDetectionModel && buf.length >= 2) {
        debugPrint('$tag raw scores: [0]=${buf[0].toStringAsFixed(6)} [1]=${buf[1].toStringAsFixed(6)}');
      }
      if (_isDetectionModel) {
        double bestC0 = -999, bestC1 = -999;
        int bestA0 = 0, bestA1 = 0;
        for (int i = 0; i < _numAnchors; i++) {
          final s0 = _readOutput(outputBuffer, outputTensor.type, outputTensor.params, 4, i);
          final s1 = _numClasses > 1 ? _readOutput(outputBuffer, outputTensor.type, outputTensor.params, 5, i) : 0.0;
          if (s0 > bestC0) { bestC0 = s0; bestA0 = i; }
          if (s1 > bestC1) { bestC1 = s1; bestA1 = i; }
        }
        debugPrint('$tag detection best: male(c0)=${bestC0.toStringAsFixed(6)}@anchor$bestA0 female(c1)=${bestC1.toStringAsFixed(6)}@anchor$bestA1');
      }
    }

    return _parseDetections(outputBuffer, outputTensor.type, outputTensor.params, tag);
  }

  List<CrayfishDetection> _parseDetections(
    dynamic outputBuffer,
    TensorType outputType,
    QuantizationParams outputParams,
    String tag,
  ) {
    if (!_isDetectionModel) {
      final double score0 = _readOutput(outputBuffer, outputType, outputParams, 0, 0);
      final double score1 = _readOutput(outputBuffer, outputType, outputParams, 1, 0);
      debugPrint('$tag classification raw: male=${score0.toStringAsFixed(6)} female=${score1.toStringAsFixed(6)}');
      final int bestClass = score0 > score1 ? 0 : 1;
      final double bestScore = bestClass == 0 ? score0 : score1;
      debugPrint('$tag classification result: ${_labels[bestClass]} ${(bestScore * 100).toStringAsFixed(1)}% (threshold=${(_confidenceThreshold * 100).toStringAsFixed(0)}%)');
      lastBestScore = bestScore;
      if (bestScore < _confidenceThreshold || bestClass >= _labels.length) {
        debugPrint('$tag classification: REJECTED (score ${bestScore.toStringAsFixed(4)} < threshold ${_confidenceThreshold.toStringAsFixed(4)})');
        return [];
      }
      return [CrayfishDetection(
        label: _labels[bestClass],
        confidence: bestScore,
        left: 0.0, top: 0.0, right: 1.0, bottom: 1.0,
      )];
    }

    final candidates = <CrayfishDetection>[];
    int aboveThreshold = 0;
    double globalBestScore = 0;

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
      if (bestScore > globalBestScore) {
        globalBestScore = bestScore;
      }
      if (bestScore >= _confidenceThreshold) aboveThreshold++;

      if (bestClass == -1 || bestScore < _confidenceThreshold) continue;
      if (bestClass >= _labels.length) continue;

      double cx = _readOutput(outputBuffer, outputType, outputParams, 0, i);
      double cy = _readOutput(outputBuffer, outputType, outputParams, 1, i);
      double w = _readOutput(outputBuffer, outputType, outputParams, 2, i);
      double h = _readOutput(outputBuffer, outputType, outputParams, 3, i);

      if (cx > 1.0 || cy > 1.0 || w > 1.0 || h > 1.0) {
        cx /= _inputSize;
        cy /= _inputSize;
        w /= _inputSize;
        h /= _inputSize;
      }

      debugPrint(
        '$tag det #${candidates.length}: ${_labels[bestClass]} '
        '${(bestScore * 100).toStringAsFixed(1)}% '
        'box=[cx=${cx.toStringAsFixed(3)} cy=${cy.toStringAsFixed(3)} '
        'w=${w.toStringAsFixed(3)} h=${h.toStringAsFixed(3)}]',
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

    debugPrint('$tag: $aboveThreshold anchors above threshold, ${candidates.length} after NMS, globalBest=${globalBestScore.toStringAsFixed(4)}');
    lastBestScore = globalBestScore;

    return _nonMaxSuppression(candidates);
  }

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

  int _quantize(double realValue, QuantizationParams params) {
    if (params.scale == 0) return realValue.round().clamp(0, 255);
    return ((realValue / params.scale) + params.zeroPoint).round().clamp(0, 255);
  }

  double _dequantize(int quantized, QuantizationParams params) {
    if (params.scale == 0) return quantized.toDouble();
    return (quantized - params.zeroPoint) * params.scale;
  }

  bool scoreGreaterThanThreshold(double score) => score > _confidenceThreshold;

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

      final image = img.Image(width: _inputSize, height: _inputSize);
      final double scaleX = width / _inputSize;
      final double scaleY = height / _inputSize;

      for (int ty = 0; ty < _inputSize; ty++) {
        final int sy = (ty * scaleY).toInt().clamp(0, height - 1);
        for (int tx = 0; tx < _inputSize; tx++) {
          final int sx = (tx * scaleX).toInt().clamp(0, width - 1);

          final yIndex = sy * yPlane.bytesPerRow + sx;
          final uvPixelStride = uPlane.bytesPerPixel ?? 1;
          final uvIndex = (sy ~/ 2) * uPlane.bytesPerRow + (sx ~/ 2) * uvPixelStride;

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
          final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).clamp(0, 255).toInt();
          final b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();
          image.setPixelRgb(tx, ty, r, g, b);
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
