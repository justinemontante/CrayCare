import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  test('Check model tensors', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      print('Loading model...');
      final interpreter = await Interpreter.fromFile(
        File('assets/models/crayfish_gender.tflite'),
      );
      
      final inputTensor = interpreter.getInputTensor(0);
      print('INPUT TENSOR:');
      print('  Shape: ${inputTensor.shape}');
      print('  Type: ${inputTensor.type}');
      print('  Scale: ${inputTensor.params.scale}');
      print('  ZeroPoint: ${inputTensor.params.zeroPoint}');
      
      final outputTensor = interpreter.getOutputTensor(0);
      print('OUTPUT TENSOR:');
      print('  Shape: ${outputTensor.shape}');
      print('  Type: ${outputTensor.type}');
      print('  Scale: ${outputTensor.params.scale}');
      print('  ZeroPoint: ${outputTensor.params.zeroPoint}');
      
      interpreter.close();
    } catch (e) {
      print('Error: $e');
    }
  });
}
