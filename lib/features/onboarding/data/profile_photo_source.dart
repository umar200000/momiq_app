import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

/// Picked photos remain local; there is no upload or backend in this flow.
class ProfilePhotoSource {
  final ImagePicker _picker = ImagePicker();

  Future<Uint8List?> pickProfile({
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }

  Future<List<Uint8List>> pickHome(
    int remaining, {
    ImageSource source = ImageSource.gallery,
  }) async {
    if (remaining <= 0) return [];
    if (source == ImageSource.camera || remaining == 1) {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      return file == null ? [] : [await file.readAsBytes()];
    }
    final files = await _picker.pickMultiImage(
      limit: remaining,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return Future.wait(files.take(remaining).map((file) => file.readAsBytes()));
  }
}
