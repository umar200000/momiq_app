import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One atomic credential record, scoped to the API and this installation.
class SessionVault {
  static const key = 'momiq.session.v1';
  static const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(migrateWithBackup: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  static Future<void> save({
    required String token,
    required String userId,
    required String scope,
  }) => storage.write(
    key: key,
    value: jsonEncode({'token': token, 'userId': userId, 'scope': scope}),
  );

  static Future<Map<String, String>?> read() async {
    final raw = await storage.read(key: key);
    if (raw == null) return null;
    try {
      final data = Map<String, String>.from(jsonDecode(raw) as Map);
      if ([
        'token',
        'userId',
        'scope',
      ].any((key) => data[key]?.isNotEmpty != true)) {
        throw const FormatException('Incomplete credential');
      }
      return data;
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  static Future<void> clear() => storage.delete(key: key);
}
