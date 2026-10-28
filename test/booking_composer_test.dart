import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/bookings/data/booking_composer.dart';
import 'package:momiq_app/features/bookings/data/booking_controller.dart';
import 'package:momiq_app/features/bookings/presentation/booking_request_page.dart';
import 'package:momiq_app/features/bookings/presentation/bookings_page.dart';
import 'booking_controller_test.dart' show BookingMemory, fixture;

class ComposerApi extends CustomerApi {
  ComposerApi() : super('token', 'owner');
  final List<Map<String, dynamic>> submissions = [];
  final Set<String> created = {};
  bool loseResponse = false, failQuote = false;
  bool includeOther = false;
  int quoteCount = 0;
  Map<String, dynamic>? quotedBody;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/bookings/policy') return {'version': 'elapsed-24h-v1'};
    if (path == '/bookings/quotes') {
      quoteCount++;
      quotedBody = jsonDecode(jsonEncode(body));
      if (failQuote) throw CustomerApiException('Quote failed', 409);
      final snapshot = Map<String, dynamic>.from(fixture()['snapshot']);
      snapshot['pets'] = [
        {'id': 'owned', 'name': 'TEST cat'},
      ];
      return {
        'id': 'quote-$quoteCount',
        'snapshot': snapshot,
        'expiresAt': '2030-01-01T00:00:00Z',
      };
    }
    if (path == '/bookings' && method == 'POST') {
      submissions.add(jsonDecode(jsonEncode(body)));
      created.add(body!['requestId']);
      if (loseResponse) {
        loseResponse = false;
        throw TimeoutException('lost');
      }
      return fixture();
    }
    if (path == '/messages') return {'messages': []};
    if (path == '/me') {
      return {
        'account': {
          '_revision': 1,
          'profile': {'first': 'TEST', 'last': 'Owner', 'photo': null},
          'favorites': [],
          'addresses': [],
          'pets': [
            if (includeOther)
              {
                'id': 'other-pet',
                'type': 'Boshqa',
                'otherType': 'TEST rabbit',
                'photo': null,
              },
            {
              'id': 'owned',
              'type': 'Mushuk',
              'name': 'TEST cat',
              'photo': null,
            },
          ],
          'support': [],
          'notifications': {'orders': true, 'chat': true, 'video': true},
          'language': 'uz',
          'sitterProfile': null,
        },
      };
    }
    return fixture();
  }
}

Map<String, dynamic> formFields() => {
  'petIds': ['owned'],
  'startsAt': '2030-01-01T00:00:00Z',
  'endsAt': '2030-01-01T16:00:00Z',
  'instructions': 'TEST care',
  'petPassports': <String, String>{},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'other animal remains in account but cannot be selected or restored into a new booking draft',
    (t) async {
      final api = ComposerApi()..includeOther = true;
      final store = CustomerStore()..api = api;
      final memory = BookingMemory()
        ..value = {
          'draft': {
            ...formFields(),
            'petIds': ['other-pet'],
          },
          'quote': null,
          'pending': null,
        };
      final c = BookingComposer(api, 'sitter:homeVisit', storage: memory);
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(
        MaterialApp(
          home: BookingRequestPage(
            store: store,
            sitter: {
              'id': 'sitter:homeVisit',
              'name': 'TEST',
              'service': 1,
              'pets': ['It', 'Mushuk', 'Boshqa'],
            },
            composer: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        store.list('pets').where((p) => p['type'] == 'Boshqa'),
        hasLength(1),
      );
      expect(find.byKey(const ValueKey('bookingPet-other-pet')), findsNothing);
      expect(find.byKey(const ValueKey('bookingPet-owned')), findsOneWidget);
      expect(c.draft['petIds'], isEmpty);
      expect(api.quoteCount, 0);
      expect(api.submissions, isEmpty);
    },
  );
  testWidgets(
    'current server booking flow requires a selected pet before advancing',
    (t) async {
      final api = ComposerApi();
      final store = CustomerStore()..api = api;
      final c = BookingComposer(
        api,
        'sitter:boarding',
        storage: BookingMemory(),
      );
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(
        MaterialApp(
          home: BookingRequestPage(
            store: store,
            sitter: {
              'id': 'sitter:boarding',
              'name': 'TEST',
              'service': 0,
              'pets': ['Mushuk'],
            },
            composer: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      final next = find.byKey(const ValueKey('submitBookingStep'));
      await t.scrollUntilVisible(next, 200);
      await t.tap(next);
      await t.pumpAndSettle();
      expect(find.text('Hayvonni tanlang'), findsOneWidget);
      expect(api.quoteCount, 0);
      expect(api.submissions, isEmpty);
    },
  );
  test(
    'only server quote used; exact pending request survives restart',
    () async {
      final api = ComposerApi()..loseResponse = true;
      final memory = BookingMemory();
      final first = BookingComposer(api, 'sitter:boarding', storage: memory);
      await first.load();
      expect(await first.saveDraft(formFields()), isTrue);
      expect(await first.getQuote(), isTrue);
      expect(api.quotedBody!['listingId'], 'sitter:boarding');
      expect(api.quotedBody!.containsKey('total'), isFalse);
      expect(await first.submit(), isFalse);
      expect(
        await first.saveDraft({...formFields(), 'instructions': 'changed'}),
        isFalse,
      );
      first.dispose();
      final reopened = BookingComposer(api, 'sitter:boarding', storage: memory);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(await reopened.submit(), isTrue);
      expect(api.submissions[0], api.submissions[1]);
      expect(api.created, hasLength(1));
      expect(api.quoteCount, 1);
      expect(memory.value, isNull);
    },
  );
  test(
    'draft edits invalidate quote; failed refresh cannot send old quote',
    () async {
      final api = ComposerApi();
      final c = BookingComposer(
        api,
        'sitter:boarding',
        storage: BookingMemory(),
      );
      addTearDown(c.dispose);
      await c.load();
      await c.saveDraft(formFields());
      await c.getQuote();
      await c.saveDraft({...formFields(), 'instructions': 'changed'});
      expect(c.quote, isNull);
      expect(await c.submit(), isFalse);
      expect(api.submissions, isEmpty);
      await c.getQuote();
      api.failQuote = true;
      expect(await c.getQuote(), isFalse);
      expect(c.quote, isNull);
      expect(await c.submit(), isFalse);
    },
  );
  test(
    'storage failure blocks request; clearing uncertainty never sends cancel',
    () async {
      final api = ComposerApi();
      final memory = BookingMemory();
      final c = BookingComposer(api, 'sitter:boarding', storage: memory);
      addTearDown(c.dispose);
      await c.load();
      await c.saveDraft(formFields());
      await c.getQuote();
      memory.failWrite = true;
      expect(await c.submit(), isFalse);
      expect(api.submissions, isEmpty);
      memory.failWrite = false;
      await c.clearAttempt();
      expect(c.pending, isNull);
      expect(c.quote, isNull);
      expect(c.draft['instructions'], 'TEST care');
      expect(api.submissions, isEmpty);
    },
  );
  testWidgets(
    'four steps display server total and never fake success on timeout',
    (t) async {
      final api = ComposerApi()..loseResponse = true;
      final memory = BookingMemory()
        ..value = {'draft': formFields(), 'quote': null, 'pending': null};
      final c = BookingComposer(api, 'sitter:boarding', storage: memory);
      final store = CustomerStore()..api = api;
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(
        MaterialApp(
          home: BookingRequestPage(
            store: store,
            detailBuilder: (id) => BookingDetailPage(
              api: api,
              id: id,
              controller: BookingController(api, id, storage: BookingMemory()),
            ),
            sitter: {
              'id': 'sitter:boarding',
              'service': 0,
              'pets': ['Mushuk'],
              'name': 'TEST sitter',
              'price': 1,
            },
            composer: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        final next = find.byKey(const ValueKey('submitBookingStep'));
        await t.ensureVisible(next);
        await t.tap(next);
        await t.pumpAndSettle();
      }
      expect(find.text('500000 UZS'), findsOneWidget);
      final submit = find.byKey(const ValueKey('submitBookingStep'));
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(find.byType(BookingRequestPage), findsOneWidget);
      expect(find.byKey(const ValueKey('bookingComposeError')), findsOneWidget);
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(find.byType(BookingDetailPage), findsOneWidget);
      expect(api.created, hasLength(1));
      expect(api.submissions[0], api.submissions[1]);
    },
  );
}
