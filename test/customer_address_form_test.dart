import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_revision_test.dart' show RevisionApi;

class AddressApi extends RevisionApi {
  List<dynamic> saved = [];
  bool failWrite = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'PUT') {
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
