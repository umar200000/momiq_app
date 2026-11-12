import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/data/customer_location_service.dart';
import 'package:momiq_app/features/customer/presentation/customer_home_page.dart';
import 'customer_refresh_location_test.dart' show FakeFeed, FakeLocation;
import 'settings_session_boundary_test.dart' show SettingsApi;
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/role_selection/presentation/pages/role_selection_page.dart';
import 'package:momiq_app/features/customer/data/customer_feed_repository.dart';
import 'package:momiq_app/features/auth/presentation/session_destination.dart';

class HomeApi extends SettingsApi {
  int logouts = 0;
  Completer<void>? logoutGate;
  bool rejectLogout = false;
  @override
  Future<CJson> request(String method, String path, [CJson? body]) async {
    if (path.startsWith('/auth/logout')) {
      logouts++;
      await logoutGate?.future;
      if (rejectLogout) throw const FormatException('PRIVATE logout error');
      return {'ok': true};
    }
    return super.request(method, path, body);
  }
}

class WaitingLocation extends FakeLocation {
  Completer<CustomerLocationStatus>? gate;
  @override
  Future<CustomerLocationStatus> status() async =>
      gate == null ? value : gate!.future;
}

Future<CustomerStore> homeStore(HomeApi api, {FakeFeed? feed}) async {
  final store = CustomerStore(feedRepository: feed ?? FakeFeed())..api = api;
  addTearDown(store.dispose);
  await store.load();
  return store;
}

Future<void> openHome(
  WidgetTester t,
  CustomerStore store, {
  FakeLocation? location,
}) async {
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: CustomerHomePage(
        store: store,
        locationService:
            location ??
            (FakeLocation()..value = CustomerLocationStatus.unsupported),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> logoutDialog(WidgetTester t, {bool all = false}) async {
  await t.tap(find.byKey(const ValueKey('customerNav-3')));
  await t.pumpAndSettle();
  final action = find.widgetWithText(
    FilledButton,
    all ? 'Barcha qurilmalardan chiqish' : 'Chiqish',
  );
  await t.scrollUntilVisible(
    action,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(action);
  await t.tap(action);
  await t.pumpAndSettle();
}

void cover(WidgetTester t) {
  unawaited(
    t
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('NEXT PAGE')),
          ),
        ),
  );
}

void main() {
  setUp(() {
    CustomerApi.active = null;
    SharedPreferences.setMockInitialValues({});
    AppLanguage.current.value = 'uz';
  });
  tearDown(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });

  for (final before in [false, true]) {
    testWidgets('home masks an expired account, before mount=$before', (
      t,
    ) async {
      final store = await homeStore(HomeApi());
      if (before) CustomerApi.sessionVersion++;
      await openHome(t, store);
      if (!before) {
        expect(find.textContaining('TEST'), findsOneWidget);
        CustomerApi.sessionVersion++;
        await t.pumpAndSettle();
      }
      expect(find.textContaining('TEST'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });
  }

  testWidgets(
    'expired home offers explicit recovery without reusing its store',
    (t) async {
      final store = await homeStore(HomeApi());
      await openHome(t, store);
      CustomerApi.sessionVersion++;
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('reopenCustomerSession')));
      await t.pumpAndSettle();
      expect(find.byType(SessionRecoveryPage), findsOneWidget);
      expect(find.byType(CustomerHomePage), findsNothing);
      expect(find.textContaining('TEST'), findsNothing);
    },
  );

  testWidgets('replacing a home store invalidates the old profile', (t) async {
    final old = await homeStore(HomeApi()), next = await homeStore(HomeApi());
    final source = ValueNotifier(old);
    addTearDown(source.dispose);
    final location = FakeLocation()..value = CustomerLocationStatus.unsupported;
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ValueListenableBuilder<CustomerStore>(
          valueListenable: source,
          builder: (_, s, _) =>
              CustomerHomePage(store: s, locationService: location),
        ),
      ),
    );
    await t.pumpAndSettle();
    source.value = next;
    await t.pumpAndSettle();
    expect(find.textContaining('TEST'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'rebinding an injected store never transfers its disposal ownership',
    (t) async {
      final store = await homeStore(HomeApi());
      final source = ValueNotifier<CustomerStore?>(store);
      addTearDown(source.dispose);
      final loc = FakeLocation()..value = CustomerLocationStatus.unsupported;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: ValueListenableBuilder<CustomerStore?>(
            valueListenable: source,
            builder: (_, s, _) =>
                CustomerHomePage(store: s, locationService: loc),
          ),
        ),
      );
      await t.pumpAndSettle();
      source.value = null;
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      expect(store.isCurrentSession, isTrue);
    },
  );

  for (final dispose in [false, true]) {
    testWidgets('late feed failure belongs to its home, dispose=$dispose', (
      t,
    ) async {
      final feed = FakeFeed();
      await openHome(t, await homeStore(HomeApi(), feed: feed));
      feed.pending = Completer<List<CJson>>();
      final refresh = t
          .widget<RefreshIndicator>(
            find.byKey(const ValueKey('customerRefresh')),
          )
          .onRefresh;
      final pending = refresh();
      await t.pump();
      if (dispose) {
        await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('NEXT PAGE'))),
        );
      } else {
        cover(t);
        await t.pump(const Duration(milliseconds: 400));
      }
      feed.pending!.completeError(StateError('PRIVATE feed failure'));
      await pending;
      await t.pumpAndSettle();
      expect(find.text('NEXT PAGE'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets(
      'location explanation closes with its source, dispose=$dispose',
      (t) async {
        final loc = FakeLocation();
        await openHome(t, await homeStore(HomeApi()), location: loc);
        expect(
          find.byKey(const ValueKey('enableCustomerLocation')),
          findsOneWidget,
        );
        if (dispose) {
          final nav = t.state<NavigatorState>(find.byType(Navigator).first);
          final home = ModalRoute.of(t.element(find.byType(CustomerHomePage)))!;
          cover(t);
          await t.pumpAndSettle();
          nav.removeRoute(home);
        } else {
          CustomerApi.sessionVersion++;
        }
        await t.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey('enableCustomerLocation'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(loc.requested, 0);
      },
    );
  }

  testWidgets('delayed location status cannot prompt over a newer route', (
    t,
  ) async {
    final loc = WaitingLocation()..gate = Completer<CustomerLocationStatus>();
    await openHome(t, await homeStore(HomeApi()), location: loc);
    cover(t);
    await t.pumpAndSettle();
    loc.gate!.complete(CustomerLocationStatus.denied);
    await t.pumpAndSettle();
    expect(find.text('NEXT PAGE'), findsOneWidget);
    expect(find.byKey(const ValueKey('enableCustomerLocation')), findsNothing);
    expect(loc.requested, 0);
  });

  for (final all in [false, true]) {
    testWidgets(
      'old logout confirmation cannot sign out a replacement account, all=$all',
      (t) async {
        final old = HomeApi(), next = HomeApi();
        CustomerApi.active = old;
        await openHome(t, await homeStore(old));
        await logoutDialog(t, all: all);
        final confirm = t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Chiqish'))
            .onPressed!;
        CustomerApi.active = next;
        CustomerApi.sessionVersion++;
        confirm();
        await t.pumpAndSettle();
        expect(next.logouts, 0);
        expect(CustomerApi.active, same(next));
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'successful single, all-device and covered-route logout preserve navigation ownership',
    (t) async {
      // Run successful cleanup cases in one widget-test zone: encrypted draft
      // serialization retains a completed tail belonging to that zone.
      for (final scenario in [(false, false), (true, false), (false, true)]) {
        await t.pumpWidget(const SizedBox());
        final api = HomeApi();
        if (scenario.$2) api.logoutGate = Completer<void>();
        CustomerApi.active = api;
        await openHome(t, await homeStore(api));
        await logoutDialog(t, all: scenario.$1);
        await t.tap(find.widgetWithText(TextButton, 'Chiqish'));
        if (scenario.$2) {
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          cover(t);
          await t.pump(const Duration(milliseconds: 400));
          api.logoutGate!.complete();
        }
        await t.pumpAndSettle();
        expect(api.logouts, 1);
        expect(CustomerApi.active, isNull);
        if (scenario.$2) {
          expect(find.text('NEXT PAGE'), findsOneWidget);
          expect(find.byType(RoleSelectionPage), findsNothing);
          t.state<NavigatorState>(find.byType(Navigator).first).pop();
          await t.pumpAndSettle();
          expect(find.textContaining('TEST'), findsNothing);
        } else {
          expect(find.byType(RoleSelectionPage), findsOneWidget);
        }
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'an in-flight old logout cannot affect a newer login or show its error',
    (t) async {
      final api = HomeApi()..logoutGate = Completer<void>();
      CustomerApi.active = api;
      await openHome(t, await homeStore(api));
      await logoutDialog(t, all: true);
      await t.tap(find.widgetWithText(TextButton, 'Chiqish'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final next = HomeApi();
      CustomerApi.active = next;
      CustomerApi.sessionVersion++;
      api.logoutGate!.complete();
      await t.pumpAndSettle();
      expect(CustomerApi.active, same(next));
      expect(next.logouts, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(RoleSelectionPage), findsNothing);
    },
  );

  testWidgets(
    'repeated or disposed logout callbacks cannot open another dialog',
    (t) async {
      final api = HomeApi();
      CustomerApi.active = api;
      await openHome(t, await homeStore(api));
      await t.tap(find.byKey(const ValueKey('customerNav-3')));
      await t.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Chiqish');
      await t.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final action = t.widget<FilledButton>(button).onPressed!;
      action();
      action();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('NEXT PAGE'))),
      );
      action();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(api.logouts, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'late coordinates behind another page do not refresh or change the home label',
    (t) async {
      final loc = FakeLocation()
        ..value = CustomerLocationStatus.ready
        ..pendingLocation = Completer<CustomerCoordinates>();
      final feed = FakeFeed();
      await openHome(t, await homeStore(HomeApi(), feed: feed), location: loc);
      cover(t);
      await t.pumpAndSettle();
      loc.pendingLocation!.complete(const CustomerCoordinates(41.315, 69.285));
      await t.pumpAndSettle();
      expect(feed.calls, 1);
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pumpAndSettle();
      expect(find.text('Yaqin enagalar'), findsNothing);
      expect(find.byKey(const ValueKey('customerLocation')), findsOneWidget);
    },
  );

  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('logout explanation can be cancelled at 2x text in $language', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final api = HomeApi();
      api.account['language'] = language;
      CustomerApi.active = api;
      await openHome(t, await homeStore(api));
      await t.tap(find.byKey(const ValueKey('customerNav-3')));
      await t.pumpAndSettle();
      final label = {
        'uz': 'Barcha qurilmalardan chiqish',
        'en': 'Log out on all devices',
        'ru': 'Выйти на всех устройствах',
      }[language]!;
      final button = find.widgetWithText(FilledButton, label);
      await t.scrollUntilVisible(
        button,
        250,
        maxScrolls: 40,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(t.element(button), alignment: .3);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final cancel = find.widgetWithText(
        TextButton,
        {'uz': 'Ortga', 'en': 'Back', 'ru': 'Назад'}[language]!,
      );
      await t.ensureVisible(cancel);
      await t.tap(cancel);
      await t.pumpAndSettle();
      expect(api.logouts, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('late logout error never reports over a newer route', (t) async {
    final api = HomeApi()
      ..logoutGate = Completer<void>()
      ..rejectLogout = true;
    CustomerApi.active = api;
    await openHome(t, await homeStore(api));
    await logoutDialog(t, all: true);
    await t.tap(find.widgetWithText(TextButton, 'Chiqish'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    cover(t);
    await t.pump(const Duration(milliseconds: 400));
    api.logoutGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('NEXT PAGE'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(CustomerApi.active, same(api));
  });
}
