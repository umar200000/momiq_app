import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_revision_test.dart' show RevisionApi;

class AddressApi extends RevisionApi {
  List<dynamic> saved = [];
  bool failWrite = false;
  CustomerApiException? rejection;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'PUT') {
      if (rejection != null) throw rejection!;
      if (failWrite) throw CustomerApiException('TEST failed save', 503);
      saved = List.of(body!['addresses'] as List);
    }
    final reply = await super.request(method, path, body);
    if (reply['account'] != null) {
      reply['account']['addresses'] = List.of(saved);
    }
    return reply;
  }
}

void main() {
  testWidgets(
    'saved address text stays literal and a rejected edit remains open',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final previous = AppLanguage.current.value;
      addTearDown(() => AppLanguage.current.value = previous);
      final api = AddressApi()
        ..saved = [
          {
            'id': 'test',
            'label': 'Saqlash',
            'address': 'Ortga',
            'lat': 41.3,
            'lon': 69.2,
          },
        ]
        ..rejection = CustomerApiException(
          'Manzil Toshkent shahri va Toshkent viloyatidan tashqarida',
          400,
        );
      final store = CustomerStore()..api = api;
      addTearDown(store.dispose);
      await store.load();
      AppLanguage.current.value = 'en';
      await t.pumpWidget(
        MaterialApp(home: CustomerAddressesPage(store: store)),
      );
      expect(find.text('Saqlash'), findsOneWidget);
      expect(find.text('Ortga'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'TEST gate');
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();
      expect(
        find.text('This address is outside Tashkent city and Tashkent region.'),
        findsOneWidget,
      );
      expect(find.text('TEST gate'), findsOneWidget);
      expect(store.list('addresses').single['apartment'], isNull);
    },
  );

  for (final (language, save, pick, label, home, message) in [
    (
      'uz',
      'Saqlash',
      'Xaritadan tanlash',
      'Manzil nomi',
      'Uyim',
      'Manzil va uning nomini kiriting.',
    ),
    (
      'en',
      'Save',
      'Choose on map',
      'Address label',
      'Home',
      'Enter an address and a label.',
    ),
    (
      'ru',
      'Сохранить',
      'Выбрать на карте',
      'Название адреса',
      'Дом',
      'Укажите адрес и его название.',
    ),
  ]) {
    testWidgets('address form and missing-address feedback in $language', (
      t,
    ) async {
      final previous = AppLanguage.current.value;
      AppLanguage.current.value = language;
      addTearDown(() => AppLanguage.current.value = previous);
      final store = CustomerStore();
      addTearDown(store.dispose);
      await t.pumpWidget(MaterialApp(home: CustomerAddressForm(store: store)));
      expect(find.widgetWithText(FilledButton, pick), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(find.text(home), findsOneWidget);
      await t.tap(find.text(save));
      await t.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets(
    'address create, update and confirmed deletion preserve state after failed save',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final api = AddressApi();
      final store = CustomerStore()..api = api;
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CustomerAddressForm(
                      store: store,
                      address: store.list('addresses').firstOrNull,
                    ),
                  ),
                ),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String label) async {
        final item = find.text(label);
        await t.ensureVisible(item.last);
        await t.tap(item.last);
        // Confirmation keeps the underlying form busy until the dialog returns.
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      }

      await tap('Open form');
      await tap('Xaritadan tanlash');
      await tap('Manzilni qo‘lda kiritish');
      await t.enterText(
        find.byKey(const ValueKey('manualAddress')),
        'TEST Chirchiq',
      );
      await t.enterText(
        find.byKey(const ValueKey('manualCoordinates')),
        '100, 500',
      );
      await tap('Tanlash');
      expect(
        find.text('Manzil, kenglik va uzunlikni tekshiring.'),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const ValueKey('manualCoordinates')),
        '41.4689, 69.5822',
      );
      await tap('Tanlash');
      await t.enterText(find.byType(TextField).last, 'TEST gate');
      await tap('Saqlash');
      final id = api.saved.single['id'];
      expect(api.saved.single['apartment'], 'TEST gate');
      expect(api.saved.single['address'], 'TEST Chirchiq');
      await tap('Open form');
      await t.enterText(find.byType(TextField).last, 'TEST updated gate');
      await tap('Saqlash');
      expect(api.saved.single['id'], id);
      expect(api.saved.single['apartment'], 'TEST updated gate');
      await tap('Open form');
      await tap('Manzilni o‘chirish');
      await tap('Ortga');
      expect(api.writes, 2);
      api.failWrite = true;
      await tap('Manzilni o‘chirish');
      await tap('O‘chirish');
      expect(api.saved.single['id'], id);
      expect(find.byType(CustomerAddressForm), findsOneWidget);
      api.failWrite = false;
      await tap('Manzilni o‘chirish');
      await tap('O‘chirish');
      expect(api.writes, 3);
      expect(store.list('addresses'), isEmpty);
      expect(find.byType(CustomerAddressForm), findsNothing);
    },
  );
}
