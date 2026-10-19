import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:momiq_app/features/onboarding/data/profile_photo_source.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';

class PetPhotos extends ProfilePhotoSource {
  ImageSource? source;
  bool cancel = false;
  @override
  Future<Uint8List?> pickProfile({
    ImageSource source = ImageSource.gallery,
  }) async {
    this.source = source;
    return cancel
        ? null
        : File('assets/images/service_cat.png').readAsBytesSync();
  }
}

Future<void> seedTestPets(CustomerStore store) async {
  for (final item in [('momi', 'Momi', 'Mushuk'), ('boni', 'Boni', 'It')]) {
    await store.saveItem('pets', {
      'id': item.$1,
      'name': item.$2,
      'type': item.$3,
      'age': '2',
      'sex': '',
      'breed': '',
      'notes': '',
      'photo': base64Encode(
        File('assets/images/service_cat.png').readAsBytesSync(),
      ),
    });
  }
}
