import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/core/config/app_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'live SQLite API persists client profile, pets and settings without demo data',
    () async {
      if (AppEnvironment.current.name != 'local' ||
          !{
            '127.0.0.1',
            'localhost',
            '::1',
          }.contains(Uri.parse(CustomerApi.configuredUrl).host)) {
        throw StateError(
          'This integration fixture may only write to a local API.',
        );
      }
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      await CustomerApi.login('+998 90 000 00 01', '111111');
      final api = CustomerApi.active!;
      final store = CustomerStore()..api = api;
      addTearDown(store.dispose);
      await store.load();
      final image = base64Encode(
        await File('assets/images/service_cat.png').readAsBytes(),
      );
      await store.update((d) {
        d['profile'] = {'first': 'Sinov', 'last': 'Mijoz', 'photo': null};
        d['language'] = 'uz';
        d['notifications']['chat'] = false;
      });
      await store.saveItem('pets', {
        'id': 'live-cat',
        'name': 'Momi',
        'type': 'Mushuk',
        'photo': image,
      });
      final reopened = CustomerStore()..api = api;
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.profile['first'], 'Sinov');
      expect(reopened.list('pets').any((p) => p['id'] == 'live-cat'), isTrue);
      expect(reopened.notifications['chat'], isFalse);
      expect(reopened.remote, isTrue);
      await CustomerApi.logout();
    },
    skip: !const bool.fromEnvironment('MOMIQ_INTEGRATION'),
  );
}
