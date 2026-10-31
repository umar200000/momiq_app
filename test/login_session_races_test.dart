import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:momiq_app/core/storage/session_vault.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'role_switch_test.dart' show RoleApi;

class LoginHarness {
  final healthEntered = Completer<void>(), loginEntered = Completer<void>();
  Completer<void>? healthGate, loginGate;
  int logins = 0;
  Map<String, dynamic> result = {
    'token': 'TEST-token',
    'userId': 'TEST-user',
    'account': {
      'profile': {'first': 'TEST'},
    },
  };
  Future<Map<String, dynamic>> login({bool Function()? isCurrent}) =>
      HttpOverrides.runZoned(
        () => CustomerApi.login('998000000000', '111111', isCurrent: isCurrent),
        createHttpClient: (_) => LoginClient(this),
      );
  Future<Map<String, dynamic>> response(String path) async {
    if (path.endsWith('/health')) {
      if (!healthEntered.isCompleted) healthEntered.complete();
      await healthGate?.future;
      return {'mode': 'local'};
    }
    if (!path.endsWith('/auth/login')) {
      throw StateError('Unexpected test route');
    }
    logins++;
    if (!loginEntered.isCompleted) loginEntered.complete();
    await loginGate?.future;
    return result;
  }
}

class LoginClient implements HttpClient {
  LoginClient(this.harness);
  final LoginHarness harness;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async =>
      LoginRequest(harness, uri.path);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LoginHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  set contentType(ContentType? value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LoginRequest implements HttpClientRequest {
  LoginRequest(this.harness, this.path);
  final LoginHarness harness;
  final String path;
  @override
  final headers = LoginHeaders();
  @override
  bool followRedirects = true;
  @override
  set contentLength(int value) {}
  @override
  void add(List<int> data) {}
  @override
  Future<HttpClientResponse> close() async =>
      LoginResponse(await harness.response(path));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LoginResponse extends Stream<List<int>> implements HttpClientResponse {
  LoginResponse(this.data);
  final Map<String, dynamic> data;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(data))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedVault extends TestFlutterSecureStoragePlatform {
  DelayedVault() : super({});
  Completer<void>? gate;
  final entered = Completer<void>();
  bool fail = false;
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (key == SessionVault.key) {
      if (!entered.isCompleted) entered.complete();
      await gate?.future;
      if (fail) throw StateError('TEST vault failure');
    }
    return super.write(key: key, value: value, options: options);
  }
}

class DelayedPrefs extends InMemorySharedPreferencesStore {
  DelayedPrefs() : super.empty();
  final entered = Completer<void>(), gate = Completer<void>();
  bool delay = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (delay && key == 'flutter.momiq.api.account') {
      if (!entered.isCompleted) entered.complete();
      await gate.future;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DelayedVault vault;
  setUp(() {
    CustomerApi.active = null;
    SharedPreferences.setMockInitialValues({});
    vault = DelayedVault();
    FlutterSecureStoragePlatform.instance = vault;
  });
  tearDown(() async {
    await CustomerApi.clearLocal();
  });
  for (final atHealth in [true, false]) {
    test('logout invalidates pending login, health=$atHealth', () async {
      final h = LoginHarness();
      final gate = Completer<void>();
      if (atHealth) {
        h.healthGate = gate;
      } else {
        h.loginGate = gate;
      }
      final loggingIn = h.login();
      final rejected = expectLater(loggingIn, throwsStateError);
      await (atHealth ? h.healthEntered.future : h.loginEntered.future);
      await CustomerApi.clearLocal();
      gate.complete();
      await rejected;
      expect(CustomerApi.active, isNull);
      expect(await SessionVault.read(), isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(h.logins, atHealth ? 0 : 1);
    });
  }
  test(
    'concurrent login is rejected and confirmed login advances session once',
    () async {
      final h = LoginHarness()..loginGate = Completer<void>();
      final version = CustomerApi.sessionVersion;
      final login = h.login();
      await h.loginEntered.future;
      await expectLater(h.login(), throwsStateError);
      h.loginGate!.complete();
      await login;
      expect(h.logins, 1);
      expect(CustomerApi.sessionVersion, version + 1);
      expect(CustomerApi.active!.userId, 'TEST-user');
      expect((await SessionVault.read())!['token'], 'TEST-token');
      expect(
        (await SharedPreferences.getInstance()).getString('momiq.api.user'),
        'TEST-user',
      );
    },
  );
  test('restore waits for an in-flight credential commit', () async {
    vault.gate = Completer<void>();
    final login = LoginHarness().login();
    await vault.entered.future;
    var restored = false;
    final restore = CustomerApi.restore().then((api) {
      restored = true;
      return api;
    });
    await Future<void>.delayed(Duration.zero);
    expect(restored, isFalse);
    vault.gate!.complete();
    await login;
    expect(await restore, same(CustomerApi.active));
    expect((await SessionVault.read())!['userId'], 'TEST-user');
  });
  test(
    'logout waits for late secure write then removes it without resurrection',
    () async {
      vault.gate = Completer<void>();
      final login = LoginHarness().login();
      final rejected = expectLater(login, throwsStateError);
      await vault.entered.future;
      final logout = CustomerApi.clearLocal();
      final restored = CustomerApi.restore();
      vault.gate!.complete();
      await rejected;
      await logout;
      expect(await restored, isNull);
      expect(vault.data, isEmpty);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
  test(
    'failed secure write cleans partial session and allows a fresh retry',
    () async {
      vault.fail = true;
      await expectLater(LoginHarness().login(), throwsStateError);
      expect(CustomerApi.active, isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      vault.fail = false;
      await LoginHarness().login();
      expect(CustomerApi.active!.userId, 'TEST-user');
    },
  );
  test('late login response cannot overwrite a selected replacement', () async {
    final h = LoginHarness()..loginGate = Completer<void>();
    final login = h.login();
    final rejected = expectLater(login, throwsStateError);
    await h.loginEntered.future;
    final replacement = CustomerApi('replacement-token', 'replacement');
    CustomerApi.active = replacement;
    CustomerApi.sessionVersion++;
    await CustomerApi.rememberAccount({
      'profile': {'first': 'Replacement'},
    });
    h.loginGate!.complete();
    await rejected;
    expect(CustomerApi.active, same(replacement));
    expect(
      (await SharedPreferences.getInstance()).getString('momiq.api.account'),
      contains('Replacement'),
    );
  });
  test(
    'malformed login response does not clear the existing account',
    () async {
      final original = CustomerApi('old-token', 'old-user');
      CustomerApi.active = original;
      final version = CustomerApi.sessionVersion;
      await CustomerApi.rememberAccount({
        'profile': {'first': 'Existing'},
      });
      final h = LoginHarness()
        ..result = {'token': '', 'userId': 'new-user', 'account': {}};
      await expectLater(h.login(), throwsFormatException);
      expect(CustomerApi.active, same(original));
      expect(CustomerApi.sessionVersion, version);
      expect(
        (await SharedPreferences.getInstance()).getString('momiq.api.account'),
        contains('Existing'),
      );
    },
  );
  for (final atVault in [false, true]) {
    test(
      'disposed login form cannot publish credentials, atVault=$atVault',
      () async {
        var live = true;
        final gate = Completer<void>();
        final h = LoginHarness();
        if (atVault) {
          vault.gate = gate;
        } else {
          h.loginGate = gate;
        }
        final login = h.login(isCurrent: () => live);
        final rejected = expectLater(login, throwsStateError);
        await (atVault ? vault.entered.future : h.loginEntered.future);
        live = false;
        gate.complete();
        await rejected;
        expect(CustomerApi.active, isNull);
        expect(vault.data, isEmpty);
        expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      },
    );
  }
  for (final roleChange in [false, true]) {
    test(
      'logout runs after an already-started platform cache write, role=$roleChange',
      () async {
        final prefs = DelayedPrefs();
        SharedPreferencesStorePlatform.instance = prefs;
        CustomerApi.active = RoleApi();
        final write = roleChange
            ? CustomerApi.switchRole(customer: false)
            : CustomerApi.rememberAccount({'private': 'old'});
        final checked = roleChange
            ? expectLater(write, throwsStateError)
            : write;
        await prefs.entered.future;
        final clear = CustomerApi.clearLocal();
        prefs.gate.complete();
        await checked;
        await clear;
        expect(await prefs.getAll(), isEmpty);
        expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      },
    );
  }
}
