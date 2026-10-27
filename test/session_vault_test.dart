import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/config/app_environment.dart';
import 'package:momiq_app/core/storage/session_vault.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    CustomerApi.active = null;
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'credential is never written to preferences and logout removes it',
    () async {
      await SessionVault.save(
        token: 'private',
        userId: 'user',
        scope: AppEnvironment.current.sessionScope,
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect((await SessionVault.read())!['token'], 'private');
      await CustomerApi.clearLocal();
      expect(await SessionVault.read(), isNull);
    },
  );

  test(
    'legacy plaintext token forces sign-in even with a valid environment',
    () async {
      SharedPreferences.setMockInitialValues({
        'momiq.api.token': 'old',
        'momiq.api.user': 'user',
        'momiq.api.scope': AppEnvironment.current.sessionScope,
      });
      expect(await CustomerApi.restore(), isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'another environment and a reinstalled app cannot reuse Keychain login',
    () async {
      for (final scope in [
        'staging|https://other.example/api',
        AppEnvironment.current.sessionScope,
      ]) {
        await SessionVault.save(token: 'private', userId: 'user', scope: scope);
        expect(await CustomerApi.restore(), isNull);
        expect(await SessionVault.read(), isNull);
      }
    },
  );

  test(
    'malformed secure credentials are discarded without leaking raw contents',
    () async {
      for (final raw in ['not json', '{"token":123}', '[]']) {
        FlutterSecureStorage.setMockInitialValues({SessionVault.key: raw});
        expect(await SessionVault.read(), isNull);
        expect(await SessionVault.storage.read(key: SessionVault.key), isNull);
      }
    },
  );
}
