import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/config/app_environment.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'login_session_races_test.dart'
    show DelayedVault, LoginClient, LoginHarness, LoginHeaders, LoginRequest;

class ProbeHeaders extends LoginHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value.toString();
  }
}

class ProbeRequest extends LoginRequest {
  ProbeRequest(super.harness, super.path);
  final recorded = ProbeHeaders();
  @override
  ProbeHeaders get headers => recorded;
}

class ProbeClient extends LoginClient {
  ProbeClient(super.harness, this.requests);
  final List<ProbeRequest> requests;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    final request = ProbeRequest(harness, uri.path);
    requests.add(request);
    return request;
  }
}

class Probe extends LoginHarness {
  bool healthy = false;
  bool compatible = false;
  @override
  Future<Map<String, dynamic>> response(String path) async {
    if (!path.endsWith('/health')) return {'ok': true};
    if (!healthEntered.isCompleted) healthEntered.complete();
    await healthGate?.future;
    return {
      'ok': true,
      'mode': healthy ? AppEnvironment.current.name : 'wrong',
      'mobileFeatures': compatible
          ? AppEnvironment.requiredMobileFeatures.toList()
          : [],
      'sms': true,
      'testLogin': false,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('closed hosted login stops before sending phone and OTP', () async {
    if (AppEnvironment.current.name == 'local') return;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = DelayedVault();
    final probe = Probe()
      ..healthy = true
      ..compatible = true;
    final requests = <ProbeRequest>[];
    await HttpOverrides.runZoned(() async {
      await expectLater(
        CustomerApi.login('998000000000', 'TEST'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('kirish vaqtincha yopiq'),
          ),
        ),
      );
      expect(requests.map((request) => request.path), ['/api/health']);
    }, createHttpClient: (_) => ProbeClient(probe, requests));
  });
  test(
    'a private session verifies its hosted API anonymously before sending a token',
    () async {
      final api = CustomerApi('TEST credential', 'owner'), probe = Probe();
      final requests = <ProbeRequest>[];
      final prior = CustomerApi.active;
      CustomerApi.active = api;
      addTearDown(() => CustomerApi.active = prior);
      await HttpOverrides.runZoned(() async {
        if (AppEnvironment.current.name == 'local') {
          await api.request('GET', '/me');
          expect(requests.single.path, '/api/me');
          return;
        }
        await expectLater(api.request('GET', '/me'), throwsStateError);
        expect(requests.single.path, '/api/health');
        expect(
          requests.single.headers.values.containsKey(
            HttpHeaders.authorizationHeader,
          ),
          false,
        );
        probe.healthy = true;
        await expectLater(api.request('GET', '/me'), throwsStateError);
        expect(requests.every((r) => r.path.endsWith('/health')), true);
        probe.compatible = true;
        await Future.wait([
          api.request('GET', '/me'),
          api.request('GET', '/notifications'),
        ]);
        expect(requests.where((r) => r.path.endsWith('/health')).length, 3);
        for (final r in requests.where((r) => !r.path.endsWith('/health'))) {
          expect(
            r.headers.values[HttpHeaders.authorizationHeader],
            'Bearer TEST credential',
          );
        }
        final lateApi = CustomerApi('TEST old', 'other');
        CustomerApi.active = lateApi;
        probe.healthGate = Completer<void>();
        final count = requests.length;
        final late = lateApi.request('GET', '/me');
        await Future<void>.delayed(Duration.zero);
        CustomerApi.active = api;
        probe.healthGate!.complete();
        await expectLater(late, throwsStateError);
        expect(requests.skip(count).map((r) => r.path), ['/api/health']);
      }, createHttpClient: (_) => ProbeClient(probe, requests));
    },
  );
}
