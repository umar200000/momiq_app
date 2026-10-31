import 'customer_store.dart' show CustomerPetSession;
import '../../listings/data/listing_store.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../../wallet/data/wallet_draft_storage.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
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

class SessionEnvironmentMismatch implements Exception {
  const SessionEnvironmentMismatch();
  @override
  String toString() => 'Saved session belongs to another app environment';
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
  // Credentials/cache cleanup cannot race a still-running platform write.
  static Future<void>? _storageWrites;
  static Future<T> _sessionStorage<T>(Future<T> Function() action) {
    final previous = _storageWrites;
    final result = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    late final Future<void> tail;
    void release() {
      if (identical(_storageWrites, tail)) _storageWrites = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _storageWrites = tail;
    return result;
  }

  static bool hasProfile(Map<String, dynamic> account, {bool customer = true}) {
    final profile = account['profile'] as Map? ?? {};
    return '${profile['first'] ?? ''}'.trim().isNotEmpty &&
        '${profile['last'] ?? ''}'.trim().isNotEmpty &&
        (customer || account['sitterProfile'] is Map);
  }

  static Future<bool> customerRole() async =>
      (await SharedPreferences.getInstance()).getString('momiq.api.role') !=
      'sitter';
  static Future<Map<String, dynamic>>? _roleChange;
  static Future<Map<String, dynamic>> switchRole({required bool customer}) {
    if (_roleChange != null) throw StateError('Rol almashmoqda');
    return _roleChange = _switchRole(
      customer: customer,
    ).whenComplete(() => _roleChange = null);
  }

  static Future<Map<String, dynamic>> _switchRole({
    required bool customer,
  }) async {
    final api = await restore();
    if (api == null) throw CustomerApiException('Qayta kiring', 401);
    final version = sessionVersion;
    final role = customer ? 'customer' : 'sitter';
    final response = await api.request('POST', '/me/role', {'role': role});
    if (!identical(active, api) || version != sessionVersion) {
      throw StateError('Sessiya o‘zgargan');
    }
    if (response['userId'] != api.userId || response['role'] != role) {
      throw StateError('Rol javobi mos emas');
    }
    final account = Map<String, dynamic>.from(response['account']);
    await _sessionStorage(() async {
      void check() {
        if (!identical(active, api) || version != sessionVersion) {
          throw StateError('Sessiya o‘zgargan');
        }
      }

      check();
      final prefs = await SharedPreferences.getInstance();
      check();
      if (!await prefs.setString('momiq.api.account', jsonEncode(account))) {
        throw StateError('Rol saqlanmadi');
      }
      check();
      if (!await prefs.setString('momiq.api.role', role)) {
        throw StateError('Rol saqlanmadi');
      }
      check();
      // Same person, token and wallet drafts; invalidate outgoing page stores.
      sessionVersion++;
      ListingStore.instance.resetSession();
    });
    return account;
  }

  static Future<void> rememberAccount(
    Map<String, dynamic> account, {
    bool Function()? isCurrent,
  }) async {
    final current = active;
    final version = sessionVersion;
    if (current == null || isCurrent?.call() == false) return;
    await _sessionStorage(() async {
      bool valid() =>
          identical(active, current) &&
          version == sessionVersion &&
          isCurrent?.call() != false;
      if (!valid()) return;
      final prefs = await SharedPreferences.getInstance();
      if (!valid()) return;
      if (!await prefs.setString('momiq.api.account', jsonEncode(account))) {
        throw StateError('Profil saqlanmadi');
      }
    });
  }

  final String token, userId, baseUrl;
  Future<void>? _checkingBackend;
  Stopwatch? _healthySince;

  Future<void> verifyPrivateDestination() async {
    if (AppEnvironment.current.name == 'local' || token.isEmpty) return;
    final version = sessionVersion;
    void checkSession() {
      if (!identical(active, this) || version != sessionVersion) {
        throw StateError('Sessiya o‘zgargan');
      }
    }

    checkSession();
    if (baseUrl != configuredUrl) throw StateError('Server manzili mos emas');
    final age = _healthySince;
    if (age != null && age.elapsed < const Duration(minutes: 5)) return;
    final check = _checkingBackend ??= _checkAnonymousHealth();
    try {
      await check;
      checkSession();
      _healthySince = Stopwatch()..start();
    } finally {
      if (identical(_checkingBackend, check)) _checkingBackend = null;
    }
  }

  Future<void> _checkAnonymousHealth() async {
    AppEnvironment.current.validate();
    final response = await CustomerApi('', '').request('GET', '/health');
    AppEnvironment.current.validateHealth(response);
  }

  static bool _loggingIn = false;
  static Future<Map<String, dynamic>>? _loginCommit;
  static Future<Map<String, dynamic>> login(
    String phone,
    String code, {
    bool customer = true,
    bool Function()? isCurrent,
  }) async {
    if (_loggingIn) throw StateError('Kirish allaqachon tekshirilmoqda');
    _loggingIn = true;
    try {
      final version = sessionVersion;
      // A replacement build must not overwrite another environment's local data.
      final original = await restore();
      void check() {
        if (version != sessionVersion ||
            !identical(active, original) ||
            isCurrent?.call() == false) {
          throw StateError('Sessiya o‘zgargan');
        }
      }

      check();
      final anonymous = CustomerApi('', '');
      AppEnvironment.current.validate();
      AppEnvironment.current.validateHealth(
        await anonymous.request('GET', '/health'),
      );
      check();
      final data = await anonymous.request('POST', '/auth/login', {
        'phone': phone,
        'code': code,
        'role': customer ? 'customer' : 'sitter',
      });
      check();
      if (data['token'] is! String ||
          (data['token'] as String).isEmpty ||
          data['userId'] is! String ||
          (data['userId'] as String).isEmpty ||
          data['account'] is! Map) {
        throw const FormatException('Invalid login response');
      }
      final account = Map<String, dynamic>.from(data['account']);
      final committing = _saveLogin(data, account, customer, check, isCurrent);
      _loginCommit = committing;
      try {
        return await committing;
      } finally {
        if (identical(_loginCommit, committing)) _loginCommit = null;
      }
    } finally {
      _loggingIn = false;
    }
  }

  static Future<Map<String, dynamic>> _saveLogin(
    Map<String, dynamic> data,
    Map<String, dynamic> account,
    bool customer,
    void Function() checkOriginal,
    bool Function()? isCurrent,
  ) async {
    int? claimedVersion;
    try {
      return await _sessionStorage(() async {
        checkOriginal();
        final prefs = await SharedPreferences.getInstance();
        checkOriginal();
        claimedVersion = ++sessionVersion;
        active = null;
        CustomerPetSession.current.clear();
        ListingStore.instance.resetSession();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        void check() {
          if (claimedVersion != sessionVersion ||
              active != null ||
              isCurrent?.call() == false) {
            throw StateError('Sessiya o‘zgargan');
          }
        }

        for (final entry in <String, String>{
          'momiq.api.user': data['userId'],
          'momiq.api.role': customer ? 'customer' : 'sitter',
          'momiq.api.account': jsonEncode(account),
          'momiq.api.scope': AppEnvironment.current.sessionScope,
        }.entries) {
          check();
          if (!await prefs.setString(entry.key, entry.value)) {
            throw StateError('Sessiya saqlanmadi');
          }
          check();
        }
        await SessionVault.save(
          token: data['token'],
          userId: data['userId'],
          scope: AppEnvironment.current.sessionScope,
        );
        check();
        if (!await prefs.remove('momiq.api.token')) {
          throw StateError('Sessiya saqlanmadi');
        }
        check();
        active = CustomerApi(data['token'], data['userId']);
        return account;
      });
    } catch (_) {
      // Cleanup queues after the failed write, never inside its own queue slot.
      if (claimedVersion != null &&
          claimedVersion == sessionVersion &&
          active == null) {
        await clearLocal();
      }
      rethrow;
    }
  }

  static Future<CustomerApi?>? _restoring;
  static Future<void>? _clearing;
  static Future<CustomerApi?> restore() {
    final clearing = _clearing;
    if (clearing != null) return clearing.then((_) => restore());
    final committing = _loginCommit;
    if (committing != null) {
      return committing.then(
        (_) => restore(),
        onError: (Object _) => restore(),
      );
    }
    if (active != null) return Future.value(active);
    return _restoring ??= _restore().whenComplete(() => _restoring = null);
  }

  static Future<CustomerApi?> _restore() async {
    if (active != null) return active;
    final version = sessionVersion;
    bool current() => version == sessionVersion && active == null;
    final prefs = await SharedPreferences.getInstance();
    if (!current()) return active;
    final credential = await SessionVault.read(isCurrent: current);
    if (!current()) return active;
    final savedScope = prefs.getString('momiq.api.scope');
    if ((credential != null &&
            credential['scope'] != AppEnvironment.current.sessionScope) ||
        (savedScope != null &&
            savedScope != AppEnvironment.current.sessionScope)) {
      // Keep encrypted keys, outboxes and credentials intact for the matching build.
      // No API request or cached account screen is allowed across this boundary.
      throw const SessionEnvironmentMismatch();
    }
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
      // Unknown legacy or inconsistent credentials must never be transmitted.
      await clearLocal();
      return null;
    }
    await prefs.remove('momiq.api.token');
    if (!current()) return active;
    return active = CustomerApi(credential['token']!, credential['userId']!);
  }

  static Future<void> clearLocal() =>
      _clearing ??= _clearLocal().whenComplete(() => _clearing = null);

  static Future<void> _clearLocal() async {
    sessionVersion++;
    active = null;
    CustomerPetSession.current.clear();
    ListingStore.instance.resetSession();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await _sessionStorage(() async {
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
    });
  }

  static Future<void> logout({bool allDevices = false}) async {
    final version = sessionVersion;
    final current = active ?? await restore();
    bool ownsSession() =>
        version == sessionVersion && identical(active, current);
    if (!ownsSession()) throw StateError('Sessiya o‘zgargan');
    if (allDevices && current != null) {
      // An offline request must not claim that other devices were signed out.
      await current.request('POST', '/auth/logout-all', {});
      if (!ownsSession()) throw StateError('Sessiya o‘zgargan');
      await clearLocal();
      return;
    }
    try {
      if (current != null) await current.request('POST', '/auth/logout', {});
    } catch (_) {
      // Offline logout still clears this device. Server sessions expire normally.
    } finally {
      if (!ownsSession()) throw StateError('Sessiya o‘zgargan');
      await clearLocal();
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) => _http(method, path, body, 'application/json', (response) async {
    final text = await utf8.decoder.bind(response).join();
    final data = Map<String, dynamic>.from(jsonDecode(text));
    if (response.statusCode >= 400) {
      throw CustomerApiException(
        data['error'] ?? 'Server xatosi',
        response.statusCode,
      );
    }
    return data;
  });

  Future<Uint8List> videoPoster(String path) {
    if (!RegExp(
      r'^/bookings/[0-9a-f]{32}/videos/[0-9a-f]{32}/poster$',
    ).hasMatch(path)) {
      throw ArgumentError('Invalid poster path');
    }
    return _http('GET', path, null, 'image/jpeg', (response) async {
      if (response.statusCode != 200 ||
          response.headers.contentType?.mimeType != 'image/jpeg') {
        throw CustomerApiException(
          'Video rasmi ochilmadi',
          response.statusCode,
        );
      }
      const limit = 2 * 1024 * 1024;
      if (response.contentLength > limit) {
        throw const FormatException('Poster too large');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Poster too large');
        }
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      if (data.length < 4 ||
          data[0] != 0xff ||
          data[1] != 0xd8 ||
          data[data.length - 2] != 0xff ||
          data.last != 0xd9) {
        throw const FormatException('Invalid JPEG poster');
      }
      return data;
    });
  }

  Future<T> _http<T>(
    String method,
    String path,
    Map<String, dynamic>? body,
    String accept,
    Future<T> Function(HttpClientResponse response) decode,
  ) async {
    final version = sessionVersion;
    if (token.isNotEmpty && AppEnvironment.current.name != 'local') {
      await verifyPrivateDestination();
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .openUrl(method, Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 8));
      req.followRedirects = false;
      if (AppEnvironment.current.name != 'local' &&
          token.isNotEmpty &&
          (version != sessionVersion || !identical(active, this))) {
        throw StateError('Sessiya o‘zgargan');
      }
      req.headers.set(HttpHeaders.acceptHeader, accept);
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
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw CustomerApiException(
          'Server manzili kutilmaganda o‘zgardi.',
          response.statusCode,
        );
      }
      return await decode(response).timeout(const Duration(seconds: 15));
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
