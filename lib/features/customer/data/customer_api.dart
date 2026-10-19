import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerApiException implements Exception {
  CustomerApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// USB phone: adb reverse tcp:8080 tcp:8080. Change only MOMIQ_API_URL for deployment.
class CustomerApi {
  CustomerApi(this.token, this.userId, {String? baseUrl})
    : baseUrl = baseUrl ?? configuredUrl;
  static const configuredUrl = String.fromEnvironment(
    'MOMIQ_API_URL',
    defaultValue: 'http://127.0.0.1:8080/api',
  );
  static bool get enabled =>
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      const bool.fromEnvironment('MOMIQ_API_ENABLED', defaultValue: true);
  static CustomerApi? active;
  final String token, userId, baseUrl;
  static Future<Map<String, dynamic>> login(String phone, String code) async {
    final anonymous = CustomerApi('', '');
    final data = await anonymous.request('POST', '/auth/login', {
      'phone': phone,
      'code': code,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('momiq.api.token', data['token']);
    await prefs.setString('momiq.api.user', data['userId']);
    active = CustomerApi(data['token'], data['userId']);
    return Map<String, dynamic>.from(data['account']);
  }

  static Future<CustomerApi?> restore() async {
    if (!enabled) return null;
    if (active != null) return active;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('momiq.api.token');
    final user = prefs.getString('momiq.api.user');
    if (token == null || user == null) return null;
    return active = CustomerApi(token, user);
  }

  static Future<void> logout() async {
    final current = active;
    try {
      if (current != null) await current.request('POST', '/auth/logout', {});
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('momiq.api.token');
      await prefs.remove('momiq.api.user');
      active = null;
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
        'Backendga ulanib bo‘lmadi. Server va USB ulanishini tekshiring.',
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
