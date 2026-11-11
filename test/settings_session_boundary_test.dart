import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'customer_pet_archive_test.dart' show PetArchiveApi;

class SettingsApi extends PetArchiveApi {
  int writes = 0;
  bool broken = false;
  Completer<void>? gate;
  @override
  Future<CJson> request(String method, String path, [CJson? body]) async {
    if (method == 'PUT' && path == '/me') {
      writes++;
      await gate?.future;
      if (broken) throw const FormatException('PRIVATE response');
      account.addAll(jsonDecode(jsonEncode(body!)) as CJson);
      account['_revision'] = (account['_revision'] as int) + 1;
    }
    return super.request(method, path, body);
  }
}

Future<CustomerStore> settingsStore(SettingsApi api) async {
  final store = CustomerStore()..api = api;
  addTearDown(store.dispose);
  await store.load();
  return store;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });
  tearDown(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });

  for (final language in [false, true]) {
    testWidgets(
      'retained settings callback cannot write the replacement store, language=$language',
      (t) async {
        final oldApi = SettingsApi(), nextApi = SettingsApi();
        final old = await settingsStore(oldApi),
            next = await settingsStore(nextApi);
        final source = ValueNotifier(old);
        addTearDown(source.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<CustomerStore>(
              valueListenable: source,
              builder: (_, store, _) => CustomerSettingsPage(store: store),
            ),
          ),
        );
        await t.pumpAndSettle();
        final VoidCallback action;
        if (language) {
          action = t
              .widget<ListTile>(
                find.byKey(const ValueKey('customerLanguage-en')),
              )
              .onTap!;
        } else {
          final change = t
              .widget<SwitchListTile>(find.byType(SwitchListTile).first)
              .onChanged!;
          action = () => change(false);
        }
        source.value = next;
        await t.pumpAndSettle();
        action();
        await t.pumpAndSettle();
        expect(oldApi.writes, 0);
        expect(nextApi.writes, 0);
        expect(AppLanguage.current.value, 'uz');
        expect(next.notifications['orders'], isTrue);
      },
    );
  }

  testWidgets('session change after account commit cannot apply old language', (
    t,
  ) async {
    final api = SettingsApi();
    final store = await settingsStore(api);
    await t.pumpWidget(MaterialApp(home: CustomerSettingsPage(store: store)));
    await t.pumpAndSettle();
    var replaced = false;
    store.addListener(() {
      if (!store.busy && api.writes == 1 && !replaced) {
        replaced = true;
        CustomerApi.sessionVersion++;
      }
    });
    await t.tap(find.byKey(const ValueKey('customerLanguage-en')));
    await t.pumpAndSettle();
    expect(replaced, isTrue);
    expect(AppLanguage.current.value, 'uz');
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Hisobingizga qayta kiring.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('late settings error cannot appear above another page', (
    t,
  ) async {
    final api = SettingsApi()
      ..gate = Completer<void>()
      ..broken = true;
    final store = await settingsStore(api);
    await t.pumpWidget(MaterialApp(home: CustomerSettingsPage(store: store)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('customerLanguage-en')));
    await t.pump();
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('NEXT PAGE')),
        ),
      ),
    );
    // The covered source has a running progress indicator.
    await t.pump(const Duration(seconds: 1));
    api.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('NEXT PAGE'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(AppLanguage.current.value, 'uz');
    nav.pop();
    await t.pumpAndSettle();
    api.broken = false;
    await t.tap(find.byKey(const ValueKey('customerLanguage-en')));
    await t.pumpAndSettle();
    expect(AppLanguage.current.value, 'en');
    expect(api.writes, 2);
  });

  testWidgets('disposed settings callback cannot send an account update', (
    t,
  ) async {
    final api = SettingsApi();
    final store = await settingsStore(api);
    await t.pumpWidget(MaterialApp(home: CustomerSettingsPage(store: store)));
    await t.pumpAndSettle();
    final action = t
        .widget<ListTile>(find.byKey(const ValueKey('customerLanguage-en')))
        .onTap!;
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('NEXT PAGE'))),
    );
    action();
    await t.pumpAndSettle();
    expect(api.writes, 0);
    expect(AppLanguage.current.value, 'uz');
  });

  for (final language in ['uz', 'en', 'ru']) {
    testWidgets(
      'settings $language keeps a failed preference unchanged and manual retry saves it',
      (t) async {
        final api = SettingsApi();
        api.account['language'] = language;
        final store = await settingsStore(api);
        api.broken = true;
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: CustomerSettingsPage(store: store),
          ),
        );
        await t.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('customerNotice-orders'));
        await t.scrollUntilVisible(
          toggle,
          160,
          maxScrolls: 30,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(t.element(toggle), alignment: .5);
        await t.pumpAndSettle();
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(store.notifications['orders'], isTrue);
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        api.broken = false;
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(store.notifications['orders'], isFalse);
        expect(api.writes, 2);
        expect(t.takeException(), isNull);
      },
    );
  }
}
