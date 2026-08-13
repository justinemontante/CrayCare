import 'dart:convert';
import 'package:image_picker/image_picker.dart';

/// Produces a compact profile image data URL for users/{uid}.photo_url.
/// Firestore documents are limited to 1 MiB, so the encoded image is bounded
/// well below that limit and stored only once in the profile document.
class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  final ImagePicker _picker = ImagePicker();
  static const int _maxEncodedBytes = 750 * 1024;

  Future<String?> pickAndConvertToBase64() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 384,
        maxHeight: 384,
        imageQuality: 70,
      );
      if (image == null) return null;

      final bytes = await image.readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      if (utf8.encode(dataUrl).length > _maxEncodedBytes) {
        throw Exception(
          'The selected image is still too large. Please choose a simpler or smaller photo.',
        );
      }
      return dataUrl;
    } catch (e) {
      throw Exception('Failed to process picture: $e');
    }
  }
}
