import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_feed_repository.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';
import 'package:momiq_app/features/customer/presentation/customer_availability.dart';

class PagedFeed extends CustomerFeedRepository {
  final calls = <Map<String, Object?>>[];
  final replies = <Future<CustomerFeedPage> Function()>[];
  @override
  Future<List<CJson>> fetchSitters({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async => [];
  @override
  Future<CustomerFeedPage> fetchPage({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
    Map<String, String> filters = const {},
    String? after,
  }) {
    calls.add({'filters': Map.of(filters), 'after': after});
    return replies.removeAt(0)();
  }
}

class DiscoveryApi extends CustomerApi {
  DiscoveryApi() : super('test', 'customer');
  String? path;
  Map<String, dynamic> response = {
    'sitters': [
      {
        'id': 'abc:boarding',
        'name': 'Test',
        'service': 0,
        'price': 10000,
        'pets': ['It'],
        'rating': 0,
        'reviews': 0,
        'capacity': 2,
      },
    ],
    'nextCursor': 'next',
  };
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    this.path = path;
    return response;
  }
}

void main() {
  test(
    'invalid second catalog page keeps existing rows and exact retry cursor',
    () async {
      final api = DiscoveryApi();
      CustomerApi.active = api;
      final store = CustomerStore(
        feedRepository: const ApiCustomerFeedRepository(),
      );
      addTearDown(store.dispose);
      await store.refreshSitters();
      final row = Map<String, dynamic>.of(store.sitters.single);
      for (final item in [
        {...row, 'service': 2},
        {...row, 'price': '0'},
        {
          ...row,
          'pets': ['other'],
        },
        {
          ...row,
          'location': {'lat': 91, 'lon': 69, 'address': 'Test'},
        },
        {
          ...row,
          'availability': {
            'schedule': {
              'days': [true],
              'start': 540,
              'end': 600,
            },
          },
        },
      ]) {
        api.response = {
          'sitters': [item],
          'nextCursor': null,
        };
        await store.loadMoreSitters();
        expect(store.feedMoreError, isNotNull);
        expect(store.sitters, [row]);
        expect(store.feedNextCursor, 'next');
      }
      api.response = {
        'sitters': [
          {...row, 'id': 'def:boarding'},
        ],
        'nextCursor': null,
      };
      await store.loadMoreSitters();
      expect(store.sitters, hasLength(2));
      expect(store.feedNextCursor, isNull);
    },
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
  });
  tearDown(() {
    CustomerApi.active = null;
  });
  testWidgets(
    'next-page failure preserves loaded results and retries same cursor without duplicates',
    (t) async {
      final feed = PagedFeed();
      feed.replies.addAll([
        () async => const CustomerFeedPage([
          {'id': 'a'},
        ], nextCursor: 'page-a'),
        () async => throw StateError('offline'),
        () async => const CustomerFeedPage([
          {'id': 'a'},
          {'id': 'b'},
        ]),
      ]);
      final store = CustomerStore(feedRepository: feed);
      addTearDown(store.dispose);
      await store.refreshSitters(filters: {'pet': 'cat'});
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: store,
              builder: (_, _) => CatalogMoreButton(store: store),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('moreSitters')));
      await t.pumpAndSettle();
      expect(find.textContaining('Keyingi sahifa yuklanmadi'), findsOneWidget);
      expect(store.sitters.map((s) => s['id']), ['a']);
      expect(store.feedError, isNull);
      await t.tap(find.byKey(const ValueKey('moreSitters')));
      await t.pumpAndSettle();
      expect(store.sitters.map((s) => s['id']), ['a', 'b']);
      expect(store.feedNextCursor, isNull);
      expect(feed.calls[1], feed.calls[2]);
      expect(feed.calls[2]['filters'], {'pet': 'cat'});
    },
  );
  test(
    'late page from old filters cannot append into refreshed catalog',
    () async {
      final late = Completer<CustomerFeedPage>();
      final feed = PagedFeed();
      feed.replies.addAll([
        () async => const CustomerFeedPage([
          {'id': 'old'},
        ], nextCursor: 'old-page'),
        () => late.future,
        () async => const CustomerFeedPage([
          {'id': 'new'},
        ]),
      ]);
      final store = CustomerStore(feedRepository: feed);
      addTearDown(store.dispose);
      await store.refreshSitters();
      final waiting = store.loadMoreSitters();
      await store.refreshSitters(filters: {'service': 'personal'});
      late.complete(
        const CustomerFeedPage([
          {'id': 'stale'},
        ], nextCursor: 'stale-page'),
      );
      await waiting;
      expect(store.sitters.map((s) => s['id']), ['new']);
      expect(store.feedNextCursor, isNull);
      expect(store.feedLoadingMore, isFalse);
    },
  );
  test(
    'API page sends filters, exact UTC dates and cursor and uses current session',
    () async {
      final api = DiscoveryApi();
      CustomerApi.active = api;
      final start = DateTime.utc(2027, 1, 4, 5);
      final page = await const ApiCustomerFeedRepository().fetchPage(
        location: const CustomerCoordinates(41.311123, 69.279712),
        startsAt: start,
        endsAt: start.add(const Duration(days: 1)),
        filters: {'favorites': '1', 'animals': '2'},
        after: 'cursor-123',
      );
      final query = Uri.parse(api.path!).queryParameters;
      expect(query['favorites'], '1');
      expect(query['lat'], '41.31');
      expect(query['lon'], '69.28');
      expect(query['region'], 'tashkent');
      expect(query['animals'], '2');
      expect(query['after'], 'cursor-123');
      expect(query['startsAt'], '2027-01-04T05:00:00.000Z');
      expect(page.nextCursor, 'next');
    },
  );
  testWidgets(
    'availability renders server remaining capacity instead of local fake bookings',
    (t) async {
      final store = CustomerStore(feedRepository: PagedFeed());
      addTearDown(store.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomerAvailability(
              store: store,
              sitter: {
                'id': 'sitter:boarding',
                'service': 0,
                'capacity': 3,
                'availabilityKnown': true,
                'freeCapacity': 1,
                'availabilityInterval': {
                  'startsAt': '2027-01-04T05:00:00Z',
                  'endsAt': '2027-01-05T05:00:00Z',
                },
              },
            ),
          ),
        ),
      );
      expect(find.text('Tanlangan vaqtda 1 ta bo‘sh joy'), findsOneWidget);
      expect(find.textContaining('04.01 10:00'), findsOneWidget);
      expect(find.textContaining('bu joyni band qilmaydi'), findsOneWidget);
    },
  );
  test(
    'manual region omits GPS and rejects invalid position before network',
    () async {
      final api = DiscoveryApi();
      CustomerApi.active = api;
      await const ApiCustomerFeedRepository().fetchPage();
      expect(Uri.parse(api.path!).queryParameters, {'region': 'tashkent'});
      api.path = null;
      await expectLater(
        const ApiCustomerFeedRepository().fetchPage(
          location: const CustomerCoordinates(double.nan, 69),
        ),
        throwsArgumentError,
      );
      expect(api.path, isNull);
    },
  );
  testWidgets(
    'distance filter is unavailable without GPS but manual browsing remains',
    (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: CustomerFilterPage(
            initial: {'min': 0, 'pet': '', 'rating': false},
          ),
        ),
      );
      final slider = t.widget<Slider>(
        find.byKey(const ValueKey('filterDistance')),
      );
      expect(slider.onChanged, isNull);
      expect(
        find.textContaining('Toshkent bo‘yicha qidiruv ochiq'),
        findsOneWidget,
      );
    },
  );
}
