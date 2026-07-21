import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Debug inference output', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final interpreter = Interpreter.fromFile(
      File('assets/models/crayfish_gender.tflite'),
    );

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    print('Input: ${inputTensor.shape} type=${inputTensor.type}');
    print('Output: ${outputTensor.shape} type=${outputTensor.type}');

    final inputShape = inputTensor.shape;
    final int inputSize = inputShape[2]; // 224
    final channelsFirst = inputShape[1] <= 4 && inputShape[3] > 4;
    print('channelsFirst=$channelsFirst inputSize=$inputSize');

    final outputShape = outputTensor.shape;
    final int numChannels = outputShape[1];
    final int numAnchors = outputShape[2];
    print('numChannels=$numChannels numAnchors=$numAnchors');

    // Load test image
    final imageBytes = await File('test_tools/test_crayfish.jpg').readAsBytes();
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) { print('Failed to decode image'); return; }
    print('Image: ${decoded.width}x${decoded.height}');
    final resized = img.copyResize(decoded, width: inputSize, height: inputSize);

    final plane = inputSize * inputSize;

    // === Test 1: Simple /255 normalization (YOLO standard) ===
    print('\n=== Test 1: /255 normalization ===');
    var inputBuffer1 = Float32List(inputSize * inputSize * 3);
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final idx = y * inputSize + x;
        if (channelsFirst) {
          inputBuffer1[idx] = pixel.r / 255.0;
          inputBuffer1[plane + idx] = pixel.g / 255.0;
          inputBuffer1[2 * plane + idx] = pixel.b / 255.0;
        } else {
          final offset = idx * 3;
          inputBuffer1[offset] = pixel.r / 255.0;
          inputBuffer1[offset + 1] = pixel.g / 255.0;
          inputBuffer1[offset + 2] = pixel.b / 255.0;
        }
      }
    }
    final outputBuffer1 = Float32List(numChannels * numAnchors);
    interpreter.run(inputBuffer1, outputBuffer1);
    _printResults(outputBuffer1, numChannels, numAnchors, channelsFirst);

    // === Test 2: ImageNet normalization ===
    print('\n=== Test 2: ImageNet normalization ===');
    const mean = [0.485, 0.456, 0.406];
    const std = [0.229, 0.224, 0.225];
    var inputBuffer2 = Float32List(inputSize * inputSize * 3);
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final idx = y * inputSize + x;
        if (channelsFirst) {
          inputBuffer2[idx] = (pixel.r / 255.0 - mean[0]) / std[0];
          inputBuffer2[plane + idx] = (pixel.g / 255.0 - mean[1]) / std[1];
          inputBuffer2[2 * plane + idx] = (pixel.b / 255.0 - mean[2]) / std[2];
        } else {
          final offset = idx * 3;
          inputBuffer2[offset] = (pixel.r / 255.0 - mean[0]) / std[0];
          inputBuffer2[offset + 1] = (pixel.g / 255.0 - mean[1]) / std[1];
          inputBuffer2[offset + 2] = (pixel.b / 255.0 - mean[2]) / std[2];
        }
      }
    }
    final outputBuffer2 = Float32List(numChannels * numAnchors);
    interpreter.run(inputBuffer2, outputBuffer2);
    _printResults(outputBuffer2, numChannels, numAnchors, channelsFirst);

    interpreter.close();
  });
}

void _printResults(Float32List output, int numChannels, int numAnchors, bool channelsLast) {
  double bestClass0 = -999, bestClass1 = -999;
  int bestAnchor0 = -1, bestAnchor1 = -1;

  for (int i = 0; i < numAnchors; i++) {
    final int idx4 = channelsLast ? i * numChannels + 4 : 4 * numAnchors + i;
    final int idx5 = channelsLast ? i * numChannels + 5 : 5 * numAnchors + i;
    final s0 = output[idx4];
    final s1 = output[idx5];
    if (s0 > bestClass0) { bestClass0 = s0; bestAnchor0 = i; }
    if (s1 > bestClass1) { bestClass1 = s1; bestAnchor1 = i; }
  }
  print('  Best class0 (female): score=${bestClass0.toStringAsFixed(6)} anchor=$bestAnchor0');
  print('  Best class1 (male):   score=${bestClass1.toStringAsFixed(6)} anchor=$bestAnchor1');

  // Show box coords of best anchor
  final bestAnchor = bestClass0 > bestClass1 ? bestAnchor0 : bestAnchor1;
  final int idxCx = channelsLast ? bestAnchor * numChannels + 0 : 0 * numAnchors + bestAnchor;
  final int idxCy = channelsLast ? bestAnchor * numChannels + 1 : 1 * numAnchors + bestAnchor;
  final int idxW = channelsLast ? bestAnchor * numChannels + 2 : 2 * numAnchors + bestAnchor;
  final int idxH = channelsLast ? bestAnchor * numChannels + 3 : 3 * numAnchors + bestAnchor;
  print('  Best anchor #$bestAnchor box: cx=${output[idxCx].toStringAsFixed(3)} cy=${output[idxCy].toStringAsFixed(3)} w=${output[idxW].toStringAsFixed(3)} h=${output[idxH].toStringAsFixed(3)}');

  // Count anchors above thresholds
  int above25 = 0, above10 = 0, above05 = 0;
  for (int i = 0; i < numAnchors; i++) {
    final int idx4 = channelsLast ? i * numChannels + 4 : 4 * numAnchors + i;
    final int idx5 = channelsLast ? i * numChannels + 5 : 5 * numAnchors + i;
    final best = output[idx4] > output[idx5] ? output[idx4] : output[idx5];
    if (best >= 0.25) above25++;
    if (best >= 0.10) above10++;
    if (best >= 0.05) above05++;
  }
  print('  Anchors above 5%: $above05  10%: $above10  25%: $above25');
}
