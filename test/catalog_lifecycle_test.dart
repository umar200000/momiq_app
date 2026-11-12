import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/data/customer_feed_repository.dart';
import 'package:momiq_app/features/customer/presentation/customer_discovery.dart';
import 'catalog_discovery_test.dart' show ReviewedCatalog;
import 'settings_session_boundary_test.dart' show SettingsApi;

class CapturedCatalog extends ReviewedCatalog {
  final requests = <Map<String, String>>[];
  @override
  Future<CustomerFeedPage> fetchPage({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
    Map<String, String> filters = const {},
    String? after,
  }) {
    requests.add(Map.of(filters));
    return super.fetchPage(
      location: location,
      startsAt: startsAt,
      endsAt: endsAt,
      filters: filters,
      after: after,
    );
  }
}

Future<CustomerStore> catalogStore(
  CapturedCatalog feed, {
  SettingsApi? api,
}) async {
  final s = CustomerStore(feedRepository: feed)..api = api;
  addTearDown(s.dispose);
  await s.load();
  return s;
}

Widget frame(Widget page) => MaterialApp(home: page);
void cover(WidgetTester t) => unawaited(
  t
      .state<NavigatorState>(find.byType(Navigator).first)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('NEXT PAGE')),
        ),
      ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
  });
  tearDown(() => CustomerApi.active = null);

  for (final disposed in [false, true]) {
    testWidgets(
      'retained filter apply belongs to its own route, disposed=$disposed',
      (t) async {
        await t.pumpWidget(
          frame(
            const CustomerFilterPage(
              initial: {'pet': '', 'min': 0, 'rating': false},
            ),
          ),
        );
        await t.pumpAndSettle();
        final action = t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Natijalarni ko‘rsatish'),
            )
            .onPressed!;
        if (disposed) {
          await t.pumpWidget(frame(const Scaffold(body: Text('NEXT PAGE'))));
        } else {
          cover(t);
          await t.pumpAndSettle();
        }
        action();
        await t.pumpAndSettle();
        expect(find.text('NEXT PAGE'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final sourceChange in [false, true]) {
    testWidgets(
      'filter draft invalidates with its source or session, source=$sourceChange',
      (t) async {
        final source = ValueNotifier<CJson>({
          'pet': '',
          'min': 0,
          'rating': false,
        });
        addTearDown(source.dispose);
        await t.pumpWidget(
          frame(
            ValueListenableBuilder<CJson>(
              valueListenable: source,
              builder: (_, initial, _) => CustomerFilterPage(initial: initial),
            ),
          ),
        );
        await t.pumpAndSettle();
        if (sourceChange) {
          source.value = {'pet': 'It', 'min': 100, 'rating': false};
        } else {
          CustomerApi.sessionVersion++;
        }
        await t.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'Natijalarni ko‘rsatish'),
          findsNothing,
        );
      },
    );
  }

  for (final before in [false, true]) {
    testWidgets(
      'saved catalog rejects an expired store, before mount=$before',
      (t) async {
        final feed = CapturedCatalog();
        final store = await catalogStore(feed);
        await store.favorite('abc:boarding');
        if (before) CustomerApi.sessionVersion++;
        await t.pumpWidget(
          frame(CustomerSearchPage(store: store, favoritesOnly: true)),
        );
        await t.pumpAndSettle();
        if (!before) {
          expect(find.text('Test E.'), findsOneWidget);
          CustomerApi.sessionVersion++;
          await t.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('customerSearch')), findsNothing);
        expect(find.text('Test E.'), findsNothing);
      },
    );
  }

  testWidgets('a pending search cannot migrate into a replacement store', (
    t,
  ) async {
    final oldFeed = CapturedCatalog(), nextFeed = CapturedCatalog();
    final old = await catalogStore(oldFeed),
        next = await catalogStore(nextFeed);
    final source = ValueNotifier(old);
    addTearDown(source.dispose);
    await t.pumpWidget(
      frame(
        ValueListenableBuilder<CustomerStore>(
          valueListenable: source,
          builder: (_, s, _) => CustomerSearchPage(store: s),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('customerSearch')),
      'PRIVATE query',
    );
    source.value = next;
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(nextFeed.requests, isEmpty);
    expect(find.text('PRIVATE query'), findsNothing);
  });

  for (final dates in [false, true]) {
    testWidgets(
      'search source replacement closes its child without carrying filters, dates=$dates',
      (t) async {
        final oldFeed = CapturedCatalog(), nextFeed = CapturedCatalog();
        final source = ValueNotifier(await catalogStore(oldFeed));
        addTearDown(source.dispose);
        final next = await catalogStore(nextFeed);
        await t.pumpWidget(
          frame(
            ValueListenableBuilder<CustomerStore>(
              valueListenable: source,
              builder: (_, s, _) => CustomerSearchPage(store: s),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          dates
              ? find.byKey(const ValueKey('searchDates'))
              : find.byTooltip('Filtrlar'),
        );
        await t.pumpAndSettle();
        source.value = next;
        await t.pumpAndSettle();
        expect(
          find.byType(
            dates ? DiscoveryDatesPage : CustomerFilterPage,
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(nextFeed.requests, isEmpty);
        expect(find.byKey(const ValueKey('customerSearch')), findsNothing);
      },
    );
    testWidgets(
      'removing the search removes its child and nested picker, dates=$dates',
      (t) async {
        await t.pumpWidget(
          frame(
            CustomerSearchPage(store: await catalogStore(CapturedCatalog())),
          ),
        );
        await t.pumpAndSettle();
        final nav = t.state<NavigatorState>(find.byType(Navigator).first);
        final parent = ModalRoute.of(
          t.element(find.byType(CustomerSearchPage)),
        )!;
        await t.tap(
          dates
              ? find.byKey(const ValueKey('searchDates'))
              : find.byTooltip('Filtrlar'),
        );
        await t.pumpAndSettle();
        if (dates) {
          await t.tap(find.byKey(const ValueKey('discoveryStart')));
          await t.pumpAndSettle();
        }
        cover(t);
        await t.pumpAndSettle();
        nav.removeRoute(parent);
        await t.pumpAndSettle();
        expect(find.text('NEXT PAGE'), findsOneWidget);
        expect(
          find.byType(
            dates ? DiscoveryDatesPage : CustomerFilterPage,
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(
          find.byType(DatePickerDialog, skipOffstage: false),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('search child closes when its account expires, dates=$dates', (
      t,
    ) async {
      final store = await catalogStore(CapturedCatalog());
      await t.pumpWidget(frame(CustomerSearchPage(store: store)));
      await t.pumpAndSettle();
      await t.tap(
        dates
            ? find.byKey(const ValueKey('searchDates'))
            : find.byTooltip('Filtrlar'),
      );
      await t.pumpAndSettle();
      CustomerApi.sessionVersion++;
      await t.pumpAndSettle();
      expect(
        find.byType(dates ? DiscoveryDatesPage : CustomerFilterPage),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('customerSearch')), findsNothing);
    });
  }

  for (final empty in [false, true]) {
    testWidgets(
      'invalid returned dates do not submit another search, empty=$empty',
      (t) async {
        final feed = CapturedCatalog();
        await t.pumpWidget(
          frame(CustomerSearchPage(store: await catalogStore(feed))),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('searchDates')));
        await t.pumpAndSettle();
        final nextDay = DateTime.now().toUtc().add(const Duration(days: 2));
        Navigator.of(t.element(find.byType(DiscoveryDatesPage))).pop(<DateTime>[
          if (!empty) ...[nextDay, nextDay.subtract(const Duration(days: 1))],
        ]);
        await t.pumpAndSettle();
        expect(feed.requests.length, 1);
        expect(find.textContaining('Kelajakdagi kelish'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'date selection is single flight and owns the following time picker',
    (t) async {
      await t.pumpWidget(frame(const DiscoveryDatesPage()));
      await t.pumpAndSettle();
      final action = t
          .widget<ListTile>(find.byKey(const ValueKey('discoveryStart')))
          .onTap!;
      action();
      action();
      await t.pumpAndSettle();
      expect(
        find.byType(DatePickerDialog, skipOffstage: false),
        findsOneWidget,
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      CustomerApi.sessionVersion++;
      await t.pumpAndSettle();
      expect(find.byType(TimePickerDialog, skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('applyDiscoveryDates')), findsNothing);
    },
  );

  testWidgets(
    'retained date callbacks after disposal neither navigate nor throw',
    (t) async {
      await t.pumpWidget(frame(const DiscoveryDatesPage()));
      await t.pumpAndSettle();
      final pick = t
          .widget<ListTile>(find.byKey(const ValueKey('discoveryStart')))
          .onTap!;
      final apply = t
          .widget<FilledButton>(
            find.byKey(const ValueKey('applyDiscoveryDates')),
          )
          .onPressed!;
      await t.pumpWidget(frame(const Scaffold(body: Text('NEXT PAGE'))));
      pick();
      apply();
      await t.pumpAndSettle();
      expect(find.text('NEXT PAGE'), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('a debounce beneath another route sends no catalog request', (
    t,
  ) async {
    final feed = CapturedCatalog();
    await t.pumpWidget(
      frame(CustomerSearchPage(store: await catalogStore(feed))),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('customerSearch')), 'TEST');
    cover(t);
    await t.pumpAndSettle();
    expect(feed.requests.length, 1);
  });

  for (final disposed in [false, true]) {
    testWidgets('date picker belongs to its page, disposed=$disposed', (
      t,
    ) async {
      await t.pumpWidget(frame(const DiscoveryDatesPage()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('discoveryStart')));
      await t.pumpAndSettle();
      if (disposed) {
        final nav = t.state<NavigatorState>(find.byType(Navigator).first);
        final route = ModalRoute.of(
          t.element(find.byType(DiscoveryDatesPage)),
        )!;
        cover(t);
        await t.pumpAndSettle();
        nav.removeRoute(route);
      } else {
        CustomerApi.sessionVersion++;
      }
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog, skipOffstage: false), findsNothing);
    });
  }

  testWidgets('a retained date apply cannot pop another route', (t) async {
    await t.pumpWidget(frame(const DiscoveryDatesPage()));
    await t.pumpAndSettle();
    final action = t
        .widget<FilledButton>(find.byKey(const ValueKey('applyDiscoveryDates')))
        .onPressed!;
    cover(t);
    await t.pumpAndSettle();
    action();
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('NEXT PAGE'), findsOneWidget);
  });

  for (final detail in [false, true]) {
    for (final disposed in [false, true]) {
      testWidgets(
        'retained favorite sends nothing after invalidation, detail=$detail disposed=$disposed',
        (t) async {
          final api = SettingsApi();
          final store = await catalogStore(CapturedCatalog(), api: api);
          await store.refreshSitters();
          final sitter = store.sitters.single;
          await t.pumpWidget(
            frame(
              detail
                  ? SitterDetailPage(store: store, sitter: sitter)
                  : Scaffold(
                      body: SitterCard(store: store, sitter: sitter),
                    ),
            ),
          );
          await t.pumpAndSettle();
          final action = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Enagani saqlash',
                ),
              )
              .onPressed!;
          if (disposed) {
            await t.pumpWidget(frame(const Scaffold(body: Text('NEXT PAGE'))));
          } else {
            CustomerApi.sessionVersion++;
          }
          action();
          await t.pumpAndSettle();
          expect(api.writes, 0);
          expect(find.byType(SnackBar), findsNothing);
          if (detail) {
            expect(find.byKey(const ValueKey('bookSitter')), findsNothing);
          }
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets('favorite error stays on its own route, detail=$detail', (
      t,
    ) async {
      final api = SettingsApi();
      final store = await catalogStore(CapturedCatalog(), api: api);
      await store.refreshSitters();
      final sitter = store.sitters.single;
      await t.pumpWidget(
        frame(
          detail
              ? SitterDetailPage(store: store, sitter: sitter)
              : Scaffold(
                  body: SitterCard(store: store, sitter: sitter),
                ),
        ),
      );
      await t.pumpAndSettle();
      api.gate = Completer<void>();
      api.broken = true;
      await t.tap(find.byTooltip('Enagani saqlash'));
      await t.pump();
      cover(t);
      await t.pump(const Duration(milliseconds: 400));
      api.gate!.complete();
      await t.pumpAndSettle();
      expect(find.text('NEXT PAGE'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(api.writes, 1);
    });
  }
  testWidgets(
    'current favorite success updates its detail and failed retry preserves the saved value',
    (t) async {
      final api = SettingsApi();
      final store = await catalogStore(CapturedCatalog(), api: api);
      await store.refreshSitters();
      await t.pumpWidget(
        frame(SitterDetailPage(store: store, sitter: store.sitters.single)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Enagani saqlash'));
      await t.pumpAndSettle();
      expect(store.favorites, contains('abc:boarding'));
      expect(find.byTooltip('Saqlanganlardan olib tashlash'), findsOneWidget);
      api.broken = true;
      await t.tap(find.byTooltip('Saqlanganlardan olib tashlash'));
      await t.pumpAndSettle();
      expect(store.favorites, contains('abc:boarding'));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(api.writes, 2);
    },
  );
}
