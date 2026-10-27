import 'feed_fixture.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/widgets/momiq_shimmer.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/data/customer_feed_repository.dart';
import 'package:momiq_app/features/customer/data/customer_location_service.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_page.dart';

class FakeLocation extends CustomerLocationService {
  CustomerLocationStatus value = CustomerLocationStatus.denied;
  int requested = 0, located = 0, settings = 0, appSettings = 0;
  bool grant = true;
  Completer<CustomerCoordinates>? pendingLocation;
  @override
  Future<CustomerLocationStatus> status() async => value;
  @override
  Future<void> requestPermission() async {
    requested++;
    if (grant) value = CustomerLocationStatus.ready;
  }

  @override
  Future<void> openLocationSettings() async {
    settings++;
  }

  @override
  Future<void> openAppSettings() async {
    appSettings++;
  }

  @override
  Future<CustomerCoordinates> locate() async {
    located++;
    if (pendingLocation != null) return pendingLocation!.future;
    return const CustomerCoordinates(41.315, 69.285);
  }
}

class FakeFeed extends CustomerFeedRepository {
  int calls = 0;
  Completer<List<CJson>>? pending;
  bool fail = false;
  @override
  Future<List<CJson>> fetchSitters({CustomerCoordinates? location}) async {
    calls++;
    if (fail) throw StateError('Offline');
    if (pending != null) return pending!.future;
    return const FixtureCustomerFeedRepository(
      delay: Duration.zero,
    ).fetchSitters(location: location);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(
    WidgetTester t,
    CustomerStore s,
    FakeLocation location,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: CustomerHomePage(store: s, locationService: location),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'entry explains nearby sitters; later leaves browsing available',
    (t) async {
      final feed = FakeFeed();
      final s = CustomerStore(feedRepository: feed);
      final loc = FakeLocation();
      await open(t, s, loc);
      expect(
        find.textContaining('sizga yaqin enagalar birinchi'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('skipCustomerLocation')));
      await t.pumpAndSettle();
      expect(loc.requested, 0);
      expect(loc.located, 0);
      expect(feed.calls, 1);
      expect(find.byKey(const ValueKey('customerService-0')), findsOneWidget);
    },
  );
  testWidgets(
    'declined location offer stays dismissed after restart but manual enable remains',
    (t) async {
      final loc = FakeLocation();
      await open(t, CustomerStore(feedRepository: FakeFeed()), loc);
      await t.tap(find.byKey(const ValueKey('skipCustomerLocation')));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await open(t, CustomerStore(feedRepository: FakeFeed()), loc);
      expect(find.byKey(const ValueKey('skipCustomerLocation')), findsNothing);
      expect(loc.requested, 0);
      expect(loc.located, 0);
      await t.tap(find.byKey(const ValueKey('customerLocation')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('enableCustomerLocation')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('enableCustomerLocation')));
      await t.pumpAndSettle();
      expect(loc.requested, 1);
      expect(loc.located, 1);
    },
  );
  testWidgets(
    'permission grant fetches actual coordinates and sorts mock sitters',
    (t) async {
      final feed = FakeFeed();
      final s = CustomerStore(feedRepository: feed);
      final loc = FakeLocation();
      await open(t, s, loc);
      await t.tap(find.byKey(const ValueKey('enableCustomerLocation')));
      await t.pumpAndSettle();
      expect(loc.requested, 1);
      expect(loc.located, 1);
      expect(feed.calls, 2);
      expect(s.sitters.first['id'], 'nilufar');
      expect(s.sitters.first['distance'], 0);
    },
  );
  testWidgets(
    'disabled location resumes after settings without repeated settings loop',
    (t) async {
      final s = CustomerStore(feedRepository: FakeFeed());
      final loc = FakeLocation()..value = CustomerLocationStatus.disabled;
      await open(t, s, loc);
      await t.tap(find.byKey(const ValueKey('enableCustomerLocation')));
      await t.pumpAndSettle();
      expect(loc.settings, 1);
      loc.value = CustomerLocationStatus.ready;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(loc.located, 1);
      expect(s.sitters.first['id'], 'nilufar');
    },
  );
  testWidgets(
    'permission refusal keeps browsing and permanent denial opens app settings',
    (t) async {
      final s = CustomerStore(feedRepository: FakeFeed());
      final loc = FakeLocation()..grant = false;
      await open(t, s, loc);
      await t.tap(find.byKey(const ValueKey('enableCustomerLocation')));
      await t.pumpAndSettle();
      expect(loc.located, 0);
      loc.value = CustomerLocationStatus.deniedForever;
      await t.tap(find.byKey(const ValueKey('customerLocation')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('enableCustomerLocation')));
      await t.pumpAndSettle();
      expect(loc.appSettings, 1);
    },
  );
  testWidgets('automatic location refresh keeps home content visible', (
    t,
  ) async {
    final feed = FakeFeed();
    final s = CustomerStore(feedRepository: feed);
    final point = Completer<CustomerCoordinates>();
    final loc = FakeLocation()
      ..value = CustomerLocationStatus.ready
      ..pendingLocation = point;
    await open(t, s, loc);
    expect(feed.calls, 1);
    expect(find.byType(CustomerHomeSkeleton), findsNothing);
    final response = Completer<List<CJson>>();
    feed.pending = response;
    point.complete(const CustomerCoordinates(41.315, 69.285));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(feed.calls, 2);
    expect(find.byType(CustomerHomeSkeleton), findsNothing);
    expect(find.byKey(const ValueKey('customerService-0')), findsOneWidget);
    response.complete([
      {...customerSitters.first, 'name': 'Yaqin enaga'},
    ]);
    await t.pumpAndSettle();
    expect(s.sitters.first['name'], 'Yaqin enaga');
    expect(find.byType(CustomerHomeSkeleton), findsNothing);
  });
  testWidgets(
    'pull refresh calls repository again and uses shimmer not spinner',
    (t) async {
      final feed = FakeFeed();
      final s = CustomerStore(feedRepository: feed);
      final loc = FakeLocation()..value = CustomerLocationStatus.unsupported;
      await open(t, s, loc);
      final response = Completer<List<CJson>>();
      feed.pending = response;
      await t.drag(
        find.byKey(const ValueKey('customerTab-0')),
        const Offset(0, 500),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(feed.calls, 2);
      expect(
        find.byKey(const ValueKey('customerRefreshShimmer')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      response.complete([
        {...customerSitters.first, 'name': 'Yangilangan enaga'},
      ]);
      await t.pumpAndSettle();
      expect(s.sitters.first['name'], 'Yangilangan enaga');
      expect(find.byType(CustomerHomeSkeleton), findsNothing);
    },
  );
  testWidgets('initial load uses shimmer and failure allows retry', (t) async {
    final feed = FakeFeed()..pending = Completer<List<CJson>>();
    final s = CustomerStore(feedRepository: feed);
    final loc = FakeLocation()..value = CustomerLocationStatus.unsupported;
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: CustomerHomePage(store: s, locationService: loc),
      ),
    );
    await t.pump();
    expect(
      find.byKey(const ValueKey('customerInitialShimmer')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    feed.pending!.completeError(StateError('Offline'));
    await t.pumpAndSettle();
    expect(find.text('Qayta urinish'), findsOneWidget);
    feed.pending = null;
    await t.tap(find.text('Qayta urinish'));
    await t.pumpAndSettle();
    expect(feed.calls, 2);
    expect(find.byType(CustomerHomeSkeleton), findsNothing);
  });
  test('feed refresh does not reset profile, favorites or bookings', () async {
    final s = CustomerStore(
      feedRepository: const FixtureCustomerFeedRepository(delay: Duration.zero),
    );
    await s.load();
    await s.favorite('hoji');
    await s.update((d) => (d['profile'] as Map)['first'] = 'Umar');
    final count = s.list('bookings').length;
    await s.refreshSitters(location: const CustomerCoordinates(41.315, 69.285));
    expect(s.profile['first'], 'Umar');
    expect(s.favorites, ['hoji']);
    expect(s.list('bookings').length, count);
  });
}
