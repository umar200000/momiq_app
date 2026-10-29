import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/config/app_environment.dart';
import 'package:momiq_app/core/storage/session_vault.dart';
import 'package:momiq_app/features/auth/presentation/session_destination.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

class DelayedSessionApi extends CustomerApi {
  DelayedSessionApi(String user) : super('test-$user', user);
  final gate = Completer<void>();
  CustomerApiException? failure;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    await gate.future;
    if (failure != null) throw failure!;
    return {
      'account': {
        'profile': {'first': userId, 'last': 'Test', 'photo': null},
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    CustomerApi.active = null;
    CustomerApi.sessionVersion = 0;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => CustomerApi.active = null);

  Future<void> savedCredential() async {
    await SessionVault.save(
      token: 'test-token',
      userId: 'test-user',
      scope: AppEnvironment.current.sessionScope,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('momiq.api.user', 'test-user');
    await prefs.setString(
      'momiq.api.scope',
      AppEnvironment.current.sessionScope,
    );
  }

  test('parallel restore uses one API instance', () async {
    await savedCredential();
    final a = CustomerApi.restore();
    final b = CustomerApi.restore();
    expect(identical(a, b), isTrue);
    expect(await a, same(await b));
    expect(CustomerApi.active!.userId, 'test-user');
  });

  test(
    'logout invalidates pending restore and concurrent restore waits for cleanup',
    () async {
      await savedCredential();
      final restoring = CustomerApi.restore();
      final clearing = CustomerApi.clearLocal();
      final secondClear = CustomerApi.clearLocal();
      final afterLogout = CustomerApi.restore();
      expect(identical(clearing, secondClear), isTrue);
      await clearing;
      expect(await restoring, isNull);
      expect(await afterLogout, isNull);
      expect(CustomerApi.active, isNull);
      expect(await SessionVault.read(), isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test('pending restore never replaces an already selected account', () async {
    await savedCredential();
    final restoring = CustomerApi.restore();
    final replacement = CustomerApi('new-token', 'new-user');
    CustomerApi.active = replacement;
    CustomerApi.sessionVersion++;
    expect(await restoring, same(replacement));
    expect(CustomerApi.active, same(replacement));
  });

  test(
    'invalidated vault reader cannot delete a replacement credential',
    () async {
      await SessionVault.storage.write(
        key: SessionVault.key,
        value: 'malformed',
      );
      var current = true;
      final read = SessionVault.read(isCurrent: () => current);
      current = false;
      await savedCredential();
      expect(await read, isNull);
      expect((await SessionVault.read())!['userId'], 'test-user');
    },
  );

  for (final allDevices in [false, true]) {
    test(
      'late logout cannot clear another session, allDevices=$allDevices',
      () async {
        final old = DelayedSessionApi('old');
        CustomerApi.active = old;
        final loggingOut = CustomerApi.logout(allDevices: allDevices);
        final rejected = expectLater(loggingOut, throwsStateError);
        final replacement = CustomerApi('new-token', 'new-user');
        CustomerApi.active = replacement;
        CustomerApi.sessionVersion++;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('momiq.api.account', 'replacement-cache');
        old.gate.complete();
        await rejected;
        expect(CustomerApi.active, same(replacement));
        expect(prefs.getString('momiq.api.account'), 'replacement-cache');
      },
    );
  }

  for (final status in [null, 401, 403]) {
    test(
      'late startup result cannot cache or clear a replacement session, status=$status',
      () async {
        final old = DelayedSessionApi('old');
        if (status != null) {
          old.failure = CustomerApiException('Expired', status);
        }
        CustomerApi.active = old;
        final destination = restoreDestination();
        await Future<void>.delayed(Duration.zero);
        final replacement = CustomerApi('new-token', 'new-user');
        CustomerApi.active = replacement;
        CustomerApi.sessionVersion++;
        final prefs = await SharedPreferences.getInstance();
        final newCache = jsonEncode({
          'profile': {'first': 'new-user'},
        });
        await prefs.setString('momiq.api.account', newCache);
        old.gate.complete();
        expect(await destination, isA<SessionRecoveryPage>());
        expect(CustomerApi.active, same(replacement));
        expect(prefs.getString('momiq.api.account'), newCache);
      },
    );
  }
}
