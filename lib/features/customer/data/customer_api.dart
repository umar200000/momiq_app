import 'customer_store.dart' show CustomerPetSession;
import '../../listings/data/listing_store.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../../wallet/data/wallet_draft_storage.dart';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/storage/session_vault.dart';

class CustomerApiException implements Exception {
  CustomerApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Override MOMIQ_API_URL to use a local development server.
class CustomerApi {
  CustomerApi(this.token, this.userId, {String? baseUrl})
    : baseUrl = baseUrl ?? configuredUrl;
  static String get configuredUrl => AppEnvironment.current.apiUrl;
  static bool get enabled =>
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      const bool.fromEnvironment('MOMIQ_API_ENABLED', defaultValue: true);
  static CustomerApi? active;
  static int sessionVersion = 0;
  static bool hasProfile(Map<String, dynamic> account, {bool customer = true}) {
    final profile = account['profile'] as Map? ?? {};
    return '${profile['first'] ?? ''}'.trim().isNotEmpty &&
        '${profile['last'] ?? ''}'.trim().isNotEmpty &&
        (customer || account['sitterProfile'] is Map);
  }

  static Future<bool> customerRole() async =>
      (await SharedPreferences.getInstance()).getString('momiq.api.role') !=
      'sitter';
  static Future<void> rememberAccount(Map<String, dynamic> account) async {
    final current = active;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!identical(active, current)) return;
    if (!await prefs.setString('momiq.api.account', jsonEncode(account))) {
      throw StateError('Profil saqlanmadi');
    }
  }

  final String token, userId, baseUrl;
  static Future<Map<String, dynamic>> login(
    String phone,
    String code, {
    bool customer = true,
  }) async {
    final anonymous = CustomerApi('', '');
    AppEnvironment.current.validate();
    AppEnvironment.current.validateHealth(
      await anonymous.request('GET', '/health'),
    );
    final data = await anonymous.request('POST', '/auth/login', {
      'phone': phone,
      'code': code,
      'role': customer ? 'customer' : 'sitter',
    });
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('momiq.api.user', data['userId']) ||
        !await prefs.setString(
          'momiq.api.role',
          customer ? 'customer' : 'sitter',
        ) ||
        !await prefs.setString(
          'momiq.api.account',
          jsonEncode(data['account']),
        ) ||
        !await prefs.setString(
          'momiq.api.scope',
          AppEnvironment.current.sessionScope,
        )) {
      await clearLocal();
      throw StateError('Sessiya saqlanmadi');
    }
    try {
      await SessionVault.save(
        token: data['token'],
        userId: data['userId'],
        scope: AppEnvironment.current.sessionScope,
      );
      await prefs.remove('momiq.api.token');
    } catch (_) {
      await clearLocal();
      rethrow;
    }
    active = CustomerApi(data['token'], data['userId']);
    return Map<String, dynamic>.from(data['account']);
  }

  static Future<CustomerApi?> restore() async {
    if (active != null) return active;
    final prefs = await SharedPreferences.getInstance();
    final credential = await SessionVault.read();
    if (credential == null &&
        prefs.getString('momiq.api.token') == null &&
        prefs.getString('momiq.api.user') == null &&
        prefs.getString('momiq.api.scope') == null) {
      return null;
    }
    if (credential == null ||
        credential['scope'] != AppEnvironment.current.sessionScope ||
        prefs.getString('momiq.api.scope') !=
            AppEnvironment.current.sessionScope ||
        prefs.getString('momiq.api.user') != credential['userId']) {
      // Unknown legacy or other-environment credentials must never be transmitted.
      await clearLocal();
      return null;
    }
    await prefs.remove('momiq.api.token');
    return active = CustomerApi(credential['token']!, credential['userId']!);
  }

  static Future<void> clearLocal() async {
    sessionVersion++;
    active = null;
    CustomerPetSession.current.clear();
    ListingStore.instance.resetSession();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await SessionVault.clear();
    await EncryptedWalletDraftStorage.clearAll(
      removeFiles: !Platform.environment.containsKey('FLUTTER_TEST'),
    );
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('momiq.') || key.startsWith('mock.')) {
        if (!await prefs.remove(key)) {
          throw StateError('Mahalliy ma’lumotlar tozalanmadi');
        }
      }
    }
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      final directory = await getApplicationSupportDirectory();
      final videos = Directory('${directory.path}/care_videos');
      if (await videos.exists()) await videos.delete(recursive: true);
    }
  }

  static Future<void> logout({bool allDevices = false}) async {
    final current = active ?? await restore();
    if (allDevices && current != null) {
      // An offline request must not claim that other devices were signed out.
      await current.request('POST', '/auth/logout-all', {});
      await clearLocal();
      return;
    }
    try {
      if (current != null) await current.request('POST', '/auth/logout', {});
    } catch (_) {
      // Offline logout still clears this device. Server sessions expire normally.
    } finally {
      await clearLocal();
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .openUrl(method, Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        final bytes = utf8.encode(jsonEncode(body));
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final response = await req.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      final data = Map<String, dynamic>.from(jsonDecode(text));
      if (response.statusCode >= 400) {
        throw CustomerApiException(
          data['error'] ?? 'Server xatosi',
          response.statusCode,
        );
      }
      return data;
    } on SocketException {
      throw CustomerApiException(
        'Backendga ulanib bo‘lmadi. Internet ulanishini tekshiring.',
      );
    } on HttpException {
      throw CustomerApiException(
        'Server bilan aloqa uzildi. Qayta urinib ko‘ring.',
      );
    } on TimeoutException {
      throw CustomerApiException('Server javob bermadi. Qayta urinib ko‘ring.');
    } finally {
      client.close(force: true);
    }
  }
}
