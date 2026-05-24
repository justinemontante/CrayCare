// Image picker + base64 — i-convert ang picture para ma-save sa RTDB
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();
  final ImagePicker _picker = ImagePicker();

  /// Pumili ng picture sa gallery at i-convert sa base64
  /// Return: base64 data URL (hal. "data:image/jpeg;base64,/9j...")
  Future<String?> pickAndConvertToBase64() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (image == null) return null;

      final bytes = await image.readAsBytes();
      final b64 = base64Encode(bytes);
      return 'data:image/jpeg;base64,$b64';
    } catch (e) {
      throw Exception('Failed to process picture: $e');
    }
  }
}
