import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'support/pet_fixtures.dart';

class PetArchiveApi extends CustomerApi {
  PetArchiveApi() : super('test-token', 'test-owner');
  int calls = 0;
  bool fail = false;
  final Map<String, dynamic> account = {
    '_revision': 1,
    'profile': {'first': 'TEST', 'last': 'Owner', 'photo': null},
    'favorites': [],
    'addresses': [],
    'pets': [],
    'support': [],
    'notifications': {'orders': true, 'chat': true, 'video': true},
    'language': 'uz',
    'sitterProfile': null,
  };
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/messages') return {'messages': []};
    if (path == '/me/pets/archive') {
      calls++;
      if (fail || body!['_revision'] != account['_revision']) {
        throw CustomerApiException('Conflict', 409);
      }
      final pet = Map<String, dynamic>.from((account['pets'] as List).single);
      pet['archived'] = body['archived'];
      account['pets'] = [pet];
      account['_revision'] = (account['_revision'] as int) + 1;
    }
    return {'account': jsonDecode(jsonEncode(account))};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
  });

  test(
    'archive persists remotely across stores; restore keeps pet metadata',
    () async {
      final api = PetArchiveApi();
      api.account['pets'] = [
        {'id': 'pet', 'name': 'TEST cat', 'type': 'Mushuk', 'notes': 'care'},
      ];
      final store = CustomerStore()..api = api;
      addTearDown(store.dispose);
      await store.load();
      await store.archivePet('pet', true, expectedRevision: store.revision);
      expect(store.list('pets'), isEmpty);
      expect(store.archivedPets.single['notes'], 'care');
      final reopened = CustomerStore()..api = api;
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.list('pets'), isEmpty);
      expect(reopened.archivedPets.single['name'], 'TEST cat');
      await reopened.archivePet(
        'pet',
        false,
        expectedRevision: reopened.revision,
      );
      expect(reopened.list('pets').single['id'], 'pet');
      expect(reopened.archivedPets, isEmpty);
    },
  );

  test(
    'failed archive does not hide pet; stale form sends no mutation',
    () async {
      final api = PetArchiveApi();
      api.account['pets'] = [
        {'id': 'pet', 'type': 'Mushuk'},
      ];
      final store = CustomerStore()..api = api;
      addTearDown(store.dispose);
      await store.load();
      api.fail = true;
      await expectLater(
        store.archivePet('pet', true, expectedRevision: 1),
        throwsA(isA<CustomerApiException>()),
      );
      expect(store.list('pets'), hasLength(1));
      expect(store.archivedPets, isEmpty);
      expect(store.busy, isFalse);
      await expectLater(
        store.archivePet('pet', true, expectedRevision: 0),
        throwsA(isA<CustomerApiException>()),
      );
      expect(api.calls, 1);
    },
  );

  testWidgets('archive confirmation, restore and booking selection exclusion', (
    tester,
  ) async {
    final store = CustomerStore(petSession: CustomerPetSession());
    addTearDown(store.dispose);
    await store.load();
    await seedTestPets(store);
    final pet = store.list('pets').first;
    await tester.pumpWidget(MaterialApp(home: CustomerPetsPage(store: store)));
    final archive = find.byKey(ValueKey('archivePet-${pet['id']}'));
    await tester.ensureVisible(archive);
    await tester.tap(archive);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Arxivlash'));
    await tester.pumpAndSettle();
    expect(store.list('pets'), hasLength(1));
    expect(store.archivedPets.single['id'], pet['id']);
    final group = find.byKey(const ValueKey('archivedPets'));
    await tester.ensureVisible(group);
    await tester.tap(group);
    await tester.pumpAndSettle();
    final restore = find.byKey(ValueKey('restorePet-${pet['id']}'));
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tiklash'));
    await tester.pumpAndSettle();
    expect(store.list('pets'), hasLength(2));
    await store.archivePet(pet['id'], true);
    await tester.pumpWidget(
      MaterialApp(home: CustomerPetsPage(store: store, select: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('archivedPets')), findsNothing);
    expect(find.byKey(ValueKey('archivePet-${pet['id']}')), findsNothing);
  });
}
