import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/config/app_environment.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release and hosted environments reject unsafe destinations', () {
    for (final config in [
      const AppEnvironment('production', 'http://api.momiq.net/api'),
      const AppEnvironment('production', 'https://localhost/api'),
      const AppEnvironment('staging', 'https://api.momiq.net/api'),
      const AppEnvironment('local', 'https://api.momiq.net/api'),
      const AppEnvironment('prodution', 'https://api.momiq.net/api'),
      const AppEnvironment('production', 'https://token@api.momiq.net/api'),
    ]) {
      expect(config.validate, throwsStateError);
    }
    expect(
      () => const AppEnvironment(
        'local',
        'http://127.0.0.1:8080/api',
      ).validate(release: true),
      throwsStateError,
    );
    const AppEnvironment(
      'production',
      'https://api.momiq.net/api',
    ).validate(release: true);
  });

  test('production refuses test authentication and mismatched servers', () {
    const config = AppEnvironment('production', 'https://api.momiq.net/api');
    expect(
      () => config.validateHealth({
        'mode': 'production',
        'testLogin': true,
        'sms': false,
      }),
      throwsStateError,
    );
    expect(
      () => config.validateHealth({
        'mode': 'staging',
        'testLogin': false,
        'sms': true,
      }),
      throwsStateError,
    );
    config.validateHealth({
      'mode': 'production',
      'testLogin': false,
      'sms': true,
    });
  });

  test('hosted builds cannot fall back to API-disabled preview behavior', () {
    for (final config in [
      const AppEnvironment('production', 'https://api.momiq.net/api'),
      const AppEnvironment('staging', 'https://staging.example/api'),
    ]) {
      expect(() => config.validate(apiEnabled: false), throwsStateError);
      expect(
        () => config.validate(release: true, apiEnabled: false),
        throwsStateError,
      );
    }
    const AppEnvironment(
      'local',
      'http://127.0.0.1:8081/api',
    ).validate(apiEnabled: false);
  });

  for (final scope in [null, 'staging|https://another.example/api']) {
    test(
      'legacy is cleared but different-environment data is preserved ($scope)',
      () async {
        CustomerApi.active = null;
        SharedPreferences.setMockInitialValues({
          'momiq.api.token': 'do-not-send',
          'momiq.api.user': 'old-user',
          'momiq.api.account': '{}',
          'momiq.api.scope': ?scope,
        });
        if (scope == null) {
          expect(await CustomerApi.restore(), isNull);
          expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
        } else {
          await expectLater(
            CustomerApi.restore(),
            throwsA(isA<SessionEnvironmentMismatch>()),
          );
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('momiq.api.scope'), scope);
          expect(prefs.getString('momiq.api.user'), 'old-user');
          expect(CustomerApi.active, isNull);
        }
      },
    );
  }
}
