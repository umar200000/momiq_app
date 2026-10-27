import 'dart:convert';
import 'package:momiq_app/core/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/auth/presentation/session_destination.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_page.dart';
import 'package:momiq_app/features/customer/presentation/customer_registration_page.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_home_page.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/sitter_registration_page.dart';
import 'package:momiq_app/features/role_selection/presentation/pages/role_selection_page.dart';

class SessionApi extends CustomerApi {
  SessionApi(this.account, {this.error}) : super('token', 'account-id');
  final Map<String, dynamic> account;
  final CustomerApiException? error;
  bool revoked = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/auth/logout') revoked = true;
    if (error != null) throw error!;
    return {'account': account};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final customer = <String, dynamic>{
    'profile': {'first': 'Actual', 'last': 'Person', 'photo': null},
    'sitterProfile': null,
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
  });
  tearDown(() {
    CustomerApi.active = null;
  });
  test('OTP result routes existing and new profiles for each role', () {
    expect(
      accountDestination(customer, customer: true),
      isA<CustomerHomePage>(),
    );
    expect(
      accountDestination({
        'profile': {'first': '', 'last': ''},
      }, customer: true),
      isA<CustomerRegistrationPage>(),
    );
    expect(
      accountDestination(customer, customer: false),
      isA<SitterRegistrationPage>(),
    );
    expect(
      accountDestination({...customer, 'sitterProfile': {}}, customer: false),
      isA<SitterHomePage>(),
    );
  });
  test('process restart restores token user and role', () async {
    SharedPreferences.setMockInitialValues({
      'momiq.api.token': 'saved-token',
      'momiq.api.user': 'saved-user',
      'momiq.api.role': 'sitter',
      'momiq.api.scope': AppEnvironment.current.sessionScope,
    });
    final restored = await CustomerApi.restore();
    expect(restored!.token, 'saved-token');
    expect(restored.userId, 'saved-user');
    expect(await CustomerApi.customerRole(), false);
  });
  test('launch validates saved session and opens main', () async {
    CustomerApi.active = SessionApi(customer);
    expect(await restoreDestination(), isA<CustomerHomePage>());
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString('momiq.api.account')!)['profile']['first'],
      'Actual',
    );
  });
  test('incomplete registration resumes registration after restart', () async {
    CustomerApi.active = SessionApi({
      'profile': {'first': '', 'last': ''},
    });
    expect(await restoreDestination(), isA<CustomerRegistrationPage>());
  });
  test('offline launch preserves session and uses cached main', () async {
    SharedPreferences.setMockInitialValues({
      'momiq.api.token': 'token',
      'momiq.api.account': jsonEncode(customer),
    });
    CustomerApi.active = SessionApi(
      customer,
      error: CustomerApiException('offline'),
    );
    expect(await restoreDestination(), isA<CustomerHomePage>());
    expect(CustomerApi.active, isNotNull);
  });
  test('expired session clears cache and opens role selection', () async {
    SharedPreferences.setMockInitialValues({
      'momiq.api.token': 'expired',
      'momiq.customer.v1.account-id': 'private',
    });
    CustomerApi.active = SessionApi(
      customer,
      error: CustomerApiException('expired', 401),
    );
    expect(await restoreDestination(), isA<RoleSelectionPage>());
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(CustomerApi.active, isNull);
  });
  for (final offline in [false, true]) {
    test(
      'logout revokes when online and clears private device data (offline=$offline)',
      () async {
        SharedPreferences.setMockInitialValues({
          'momiq.api.token': 'token',
          'momiq.api.user': 'account-id',
          'momiq.api.account': jsonEncode(customer),
          'momiq.customer.v1.account-id': 'private',
          'mock.profile.first': 'Actual',
          'momiq.services.v1': 'private',
          'momiq.care.today': 'private',
          'language': 'uz',
        });
        final api = SessionApi(
          customer,
          error: offline ? CustomerApiException('offline') : null,
        );
        CustomerApi.active = api;
        CustomerPetSession.current.save({
          'id': 'pet',
          'type': 'Mushuk',
          'photo': 'image',
        });
        final store = CustomerStore();
        await CustomerApi.logout();
        expect(api.revoked, isTrue);
        expect(CustomerApi.active, isNull);
        expect(CustomerPetSession.current.pets, isEmpty);
        expect((await SharedPreferences.getInstance()).getKeys(), {'language'});
        expect(await restoreDestination(), isA<RoleSelectionPage>());
        await expectLater(store.update((_) {}), throwsStateError);
        store.dispose();
      },
    );
  }
}
