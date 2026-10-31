import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'package:momiq_app/features/auth/presentation/role_switch_tile.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/sitter_registration_page.dart';

class RoleApi extends CustomerApi {
  RoleApi() : super('same-token', 'same-user');
  Completer<Map<String, dynamic>>? pending;
  bool fail = false;
  final calls = <String>[];
  final account = <String, dynamic>{
    '_revision': 4,
    'profile': {'first': 'TEST First', 'last': '', 'photo': null},
    'sitterProfile': null,
  };
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add('$method $path');
    if (fail) throw CustomerApiException('offline');
    if (path == '/me/role') {
      return pending?.future ??
          {'userId': userId, 'role': body!['role'], 'account': account};
    }
    if (path == '/me') return {'account': account};
    if (path == '/me/listings') {
      return {'housing': 'apartment', 'listings': [], '_revision': 0};
    }
    return {'messages': []};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'momiq.api.role': 'customer',
      'unrelated.draft': 'keep',
    });
    CustomerApi.active = null;
  });
  tearDown(() {
    CustomerApi.active = null;
  });
  test(
    'server-confirmed role preserves token and drafts and invalidates outgoing stores',
    () async {
      final api = RoleApi();
      CustomerApi.active = api;
      final version = CustomerApi.sessionVersion;
      final oldStore = CustomerStore();
      addTearDown(oldStore.dispose);
      final account = await CustomerApi.switchRole(customer: false);
      expect(CustomerApi.active, same(api));
      expect(api.token, 'same-token');
      expect(await CustomerApi.customerRole(), isFalse);
      expect(CustomerApi.sessionVersion, version + 1);
      expect(account['_revision'], 4);
      expect(
        (await SharedPreferences.getInstance()).getString('unrelated.draft'),
        'keep',
      );
      await expectLater(oldStore.update((_) {}), throwsStateError);
      expect(api.calls, ['POST /me/role']);
    },
  );
  test('failed role request leaves mode and session unchanged', () async {
    final api = RoleApi()..fail = true;
    CustomerApi.active = api;
    final version = CustomerApi.sessionVersion;
    await expectLater(
      CustomerApi.switchRole(customer: false),
      throwsA(isA<CustomerApiException>()),
    );
    expect(await CustomerApi.customerRole(), isTrue);
    expect(CustomerApi.sessionVersion, version);
  });
  test('late response cannot switch a replacement session', () async {
    final api = RoleApi()..pending = Completer();
    CustomerApi.active = api;
    final waiting = CustomerApi.switchRole(customer: false);
    final expectation = expectLater(waiting, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    CustomerApi.active = RoleApi();
    api.pending!.complete({
      'userId': api.userId,
      'role': 'sitter',
      'account': api.account,
    });
    await expectation;
    expect(await CustomerApi.customerRole(), isTrue);
  });
  testWidgets(
    'switch opens incomplete sitter registration and prefills saved name',
    (t) async {
      final api = RoleApi();
      CustomerApi.active = api;
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RoleSwitchTile(customer: false)),
        ),
      );
      await t.tap(find.byKey(const ValueKey('switchToSitter')));
      await t.pumpAndSettle();
      expect(find.byType(SitterRegistrationPage), findsOneWidget);
      expect(find.text('TEST First'), findsOneWidget);
      expect(api.calls.where((p) => p == 'POST /me/role').length, 1);
    },
  );
  testWidgets(
    'customer registration resumes saved partial profile instead of clearing it',
    (t) async {
      final api = RoleApi();
      CustomerApi.active = api;
      final store = CustomerStore();
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(
        MaterialApp(
          home: CustomerProfileForm(store: store, registration: true),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('TEST First'), findsOneWidget);
    },
  );
}
