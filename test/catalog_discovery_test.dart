import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_feed_repository.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';

class ReviewedCatalog extends CustomerFeedRepository {
  bool visible = true;
  bool fail = false;
  int price = 100000;
  DateTime? requestedStart, requestedEnd;
  Completer<void>? gate;
  @override
  Future<List<CJson>> fetchSitters({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    requestedStart = startsAt;
    requestedEnd = endsAt;
    await gate?.future;
    if (fail) throw StateError('TEST network failure');
    return visible
        ? [
            {
              'id': 'abc:boarding',
              'name': 'Test E.',
              'service': 0,
              'pets': ['Mushuk'],
              'price': price,
              'capacity': 3,
              'photo': null,
              'homePhotos': [],
              'years': 1,
              'rating': 0,
              'reviews': 0,
              'about': 'TEST',
              'testOnly': true,
              'identityVerified': false,
              'availabilityKnown': false,
            },
          ]
        : [];
  }
}

void main() {
  testWidgets(
    'search validates dates, sends zoned endpoints and reset removes date filter',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final feed = ReviewedCatalog();
      final store = CustomerStore(feedRepository: feed);
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(MaterialApp(home: CustomerSearchPage(store: store)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('searchDates')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('applyDiscoveryDates')));
      await t.pumpAndSettle();
      expect(find.textContaining('Kelajakdagi kelish'), findsOneWidget);
      final start = DateTime.utc(2027, 1, 4, 5);
      final end = start.add(const Duration(days: 1));
      Navigator.of(
        t.element(find.byType(DiscoveryDatesPage)),
      ).pop([start, end]);
      await t.pumpAndSettle();
      expect(feed.requestedStart, start);
      expect(feed.requestedEnd, end);
      expect(find.textContaining('04.01.2027 10:00'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('clearSearchFilters')));
      await t.tap(find.byKey(const ValueKey('clearSearchFilters')));
      await t.pumpAndSettle();
      expect(feed.requestedStart, isNull);
      expect(feed.requestedEnd, isNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'search distinguishes loading and failed refresh, retries, and removes unavailable sitter on return',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final feed = ReviewedCatalog()
        ..gate = Completer<void>()
        ..fail = true;
      final store = CustomerStore(feedRepository: feed);
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(MaterialApp(home: CustomerSearchPage(store: store)));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Hech narsa topilmadi'), findsNothing);
      feed.gate!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('retrySearch')), findsOneWidget);
      expect(find.byType(SitterCard), findsNothing);
      feed.fail = false;
      await t.tap(find.byKey(const ValueKey('retrySearch')));
      await t.pumpAndSettle();
      expect(find.text('Test E.'), findsOneWidget);
      await t.tap(find.text('Test E.'));
      await t.pumpAndSettle();
      feed.visible = false;
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(SitterCard), findsNothing);
      expect(find.text('Hech narsa topilmadi'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'no implicit price ceiling and clearing resets query and service',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomerStore(
        feedRepository: ReviewedCatalog()..price = 700000,
      );
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(
        MaterialApp(home: CustomerSearchPage(store: store, service: 1)),
      );
      await t.pumpAndSettle();
      expect(find.byType(SitterCard), findsNothing);
      await t.enterText(
        find.byKey(const ValueKey('customerSearch')),
        'No match',
      );
      await t.tap(find.byKey(const ValueKey('clearSearchFilters')));
      await t.pumpAndSettle();
      expect(find.text('Test E.'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('customerSearch')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets(
    'filter form applies an explicit price cap and reset restores an unlimited maximum',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomerStore(
        feedRepository: ReviewedCatalog()..price = 700000,
      );
      addTearDown(store.dispose);
      await store.load();
      await t.pumpWidget(MaterialApp(home: CustomerSearchPage(store: store)));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Filtrlar'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Maksimal narx (so‘m)'),
        '500000',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.tap(find.text('Natijalarni ko‘rsatish'));
      await t.pumpAndSettle();
      expect(find.byType(SitterCard), findsNothing);
      await t.tap(find.byTooltip('Filtrlar'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Tozalash'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Tozalash'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tozalash'));
      await t.pumpAndSettle();
      await t.tap(find.text('Natijalarni ko‘rsatish'));
      await t.pumpAndSettle();
      expect(find.text('Test E.'), findsOneWidget);
    },
  );

  test(
    'a late old response does not resurrect an ineligible listing',
    () async {
      final first = Completer<List<CJson>>();
      final second = Completer<List<CJson>>();
      final store = CustomerStore(
        feedRepository: QueuedCatalog([first.future, second.future]),
      );
      addTearDown(store.dispose);
      final oldRequest = store.refreshSitters();
      final newRequest = store.refreshSitters();
      second.complete([]);
      await newRequest;
      first.complete([
        {'id': 'stale'},
      ]);
      await oldRequest;
      expect(store.sitters, isEmpty);
      expect(store.feedLoading, isFalse);
    },
  );

  test(
    'older catalog response cannot replace a newer eligibility result or its loading state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = Completer<List<CJson>>();
      final second = Completer<List<CJson>>();
      final feed = QueuedCatalog([first.future, second.future]);
      final store = CustomerStore(feedRepository: feed);
      addTearDown(store.dispose);
      final oldRequest = store.refreshSitters();
      final newRequest = store.refreshSitters();
      first.complete([
        {'id': 'stale'},
      ]);
      await oldRequest;
      expect(store.feedLoading, isTrue);
      second.complete([]);
      await newRequest;
      expect(store.sitters, isEmpty);
      expect(store.feedLoading, isFalse);
      expect(store.feedError, isNull);
    },
  );
  testWidgets(
    'missing availability never invents vacancies or enables a legacy booking path',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomerStore(feedRepository: ReviewedCatalog());
      addTearDown(store.dispose);
      await store.load();
      await store.refreshSitters();
      final sitter = Map<String, dynamic>.from(store.sitters.single)
        ..remove('availabilityKnown');
      sitter['years'] = null;
      sitter['bookingEnabled'] = true;
      await t.pumpWidget(
        MaterialApp(
          home: SitterDetailPage(store: store, sitter: sitter),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('bookSitter')))
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Mavjud sanalar hali tasdiqlanmagan'),
        findsOneWidget,
      );
      expect(find.textContaining('ta joy mavjud'), findsNothing);
      expect(find.textContaining('Oybek'), findsNothing);
      expect(find.text('Tajriba ko‘rsatilmagan'), findsOneWidget);
      expect(find.textContaining('null yillik'), findsNothing);
    },
  );
  testWidgets(
    'favorites cannot reintroduce a listing removed by server eligibility',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final feed = ReviewedCatalog();
      final store = CustomerStore(feedRepository: feed);
      addTearDown(store.dispose);
      await store.load();
      await store.refreshSitters();
      await store.favorite('abc:boarding');
      await t.pumpWidget(
        MaterialApp(
          home: CustomerSearchPage(store: store, favoritesOnly: true),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Test E.'), findsOneWidget);
      feed.visible = false;
      await store.refreshSitters();
      await t.pumpAndSettle();
      expect(store.favorites, contains('abc:boarding'));
      expect(find.text('Test E.'), findsNothing);
      feed.visible = true;
      await store.refreshSitters();
      await t.pumpAndSettle();
      expect(find.text('Test E.'), findsOneWidget);
    },
  );
  testWidgets(
    'reviewed catalog without GPS does not crash or invent availability',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = CustomerStore(feedRepository: ReviewedCatalog());
      addTearDown(store.dispose);
      await store.load();
      await store.refreshSitters();
      await tester.pumpWidget(
        MaterialApp(home: CustomerSearchPage(store: store)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Test E.'), findsOneWidget);
      expect(find.text('Masofa aniqlanmagan'), findsOneWidget);
      expect(find.text('Mavjud sanalar hali tasdiqlanmagan'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: SitterDetailPage(store: store, sitter: store.sitters.single),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('bookSitter')))
            .onPressed,
        isNull,
      );
      expect(find.text('Buyurtma berish hali ochilmagan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class QueuedCatalog extends CustomerFeedRepository {
  QueuedCatalog(this.results);
  final List<Future<List<CJson>>> results;
  @override
  Future<List<CJson>> fetchSitters({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
  }) => results.removeAt(0);
}
