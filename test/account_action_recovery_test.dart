import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/auth/presentation/role_switch_tile.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/sitter_registration_page.dart';
import 'customer_pet_archive_test.dart' show PetArchiveApi;
import 'role_switch_test.dart' show RoleApi;

class BrokenRoleApi extends RoleApi {
  bool broken = true;
  @override
  Future<CJson> request(String method, String path, [CJson? body]) async {
    if (broken && path == '/me/role') {
      calls.add('$method $path');
      throw const FormatException('PRIVATE parser', 'PRIVATE response');
    }
    return super.request(method, path, body);
  }
}

class BrokenPetApi extends PetArchiveApi {
  Object? failure;
  bool failRefresh = false, commitBeforeFailure = false;
  Completer<CJson>? pending;
  int attempts = 0;
  @override
  Future<CJson> request(String method, String path, [CJson? body]) async {
    if (failRefresh && path == '/me') {
      throw const FormatException('PRIVATE account response');
    }
    if (path == '/me/pets/archive') {
      attempts++;
      if (pending != null) return pending!.future;
      if (failure != null) {
        if (commitBeforeFailure) await super.request(method, path, body);
        throw failure!;
      }
    }
    return super.request(method, path, body);
  }
}

Future<CustomerStore> petStore(BrokenPetApi api) async {
  api.account['pets'] = [
    {'id': 'pet', 'name': 'TEST cat', 'type': 'Mushuk', 'notes': ''},
  ];
  final store = CustomerStore()..api = api;
  addTearDown(store.dispose);
  await store.load();
  return store;
}

Future<void> mount(
  WidgetTester t,
  Widget page, {
  String language = 'uz',
}) async {
  AppLanguage.current.value = language;
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('uz'), Locale('en'), Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: page,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> openArchive(WidgetTester t) async {
  final action = find.byKey(const ValueKey('archivePet-pet'));
  await t.ensureVisible(action);
  await t.tap(action);
  await t.pumpAndSettle();
}

Future<void> confirm(WidgetTester t) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(FilledButton),
  );
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'momiq.api.role': 'customer'});
    CustomerApi.active = null;
  });
  tearDown(() {
    CustomerApi.active = null;
    AppLanguage.current.value = 'uz';
  });

  for (final language in ['uz', 'en', 'ru']) {
    testWidgets(
      'role $language hides technical failures and manual retry works',
      (t) async {
        final api = BrokenRoleApi();
        CustomerApi.active = api;
        final version = CustomerApi.sessionVersion;
        await mount(
          t,
          const Scaffold(body: RoleSwitchTile(customer: false)),
          language: language,
        );
        await t.tap(find.byKey(const ValueKey('switchToSitter')));
        await t.pumpAndSettle();
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(
          find.text(switch (language) {
            'uz' => 'Rejimni almashtirib bo‘lmadi. Qayta urinib ko‘ring.',
            'en' => 'Could not switch modes. Please retry.',
            _ => 'Не удалось сменить режим. Повторите попытку.',
          }),
          findsOneWidget,
        );
        expect(CustomerApi.sessionVersion, version);
        expect(await CustomerApi.customerRole(), isTrue);
        api.broken = false;
        await t.tap(find.byKey(const ValueKey('switchToSitter')));
        await t.pumpAndSettle();
        expect(find.byType(SitterRegistrationPage), findsOneWidget);
        expect(api.calls.where((p) => p == 'POST /me/role'), hasLength(2));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('pet $language archive and restore work at large text', (
      t,
    ) async {
      final api = BrokenPetApi();
      final store = await petStore(api);
      await mount(t, CustomerPetsPage(store: store), language: language);
      await openArchive(t);
      expect(t.takeException(), isNull);
      await confirm(t);
      expect(store.archivedPets.single['id'], 'pet');
      final group = find.byKey(const ValueKey('archivedPets'));
      await t.ensureVisible(group);
      await t.tap(group);
      await t.pumpAndSettle();
      final restore = find.byKey(const ValueKey('restorePet-pet'));
      await t.ensureVisible(restore);
      await Scrollable.ensureVisible(t.element(restore), alignment: 0.5);
      await t.pumpAndSettle();
      await t.tap(restore);
      await t.pumpAndSettle();
      await confirm(t);
      expect(store.list('pets').single['id'], 'pet');
      expect(api.attempts, 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('pet $language failure preserves pet and hides private response', (
      t,
    ) async {
      final api = BrokenPetApi()
        ..failure = const FormatException('PRIVATE parser', 'PRIVATE response');
      final store = await petStore(api);
      await mount(t, CustomerPetsPage(store: store), language: language);
      await openArchive(t);
      await confirm(t);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(
        find.text(switch (language) {
          'uz' => 'Amal tasdiqlanmadi. Hayvon holatini yangilab tekshiring.',
          'en' =>
            'The action was not confirmed. Refresh to check the pet’s status.',
          _ =>
            'Действие не подтверждено. Обновите данные и проверьте статус питомца.',
        }),
        findsOneWidget,
      );
      expect(store.list('pets').single['id'], 'pet');
      expect(store.busy, isFalse);
      expect(api.attempts, 1);
      final archive = find.byKey(const ValueKey('archivePet-pet'));
      await t.scrollUntilVisible(
        archive,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.widget<TextButton>(archive).onPressed, isNull);
      final refresh = find.byKey(const ValueKey('refreshPetStatus'));
      await t.ensureVisible(refresh);
      await Scrollable.ensureVisible(t.element(refresh), alignment: 0.5);
      await t.pumpAndSettle();
      api.failure = null;
      await t.tap(refresh);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('refreshPetStatus')), findsNothing);
      await openArchive(t);
      await confirm(t);
      expect(store.archivedPets.single['id'], 'pet');
      expect(api.attempts, 2);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'lost archive response recovers authoritative state without a duplicate write',
    (t) async {
      final api = BrokenPetApi()
        ..failure = const FormatException('PRIVATE response')
        ..commitBeforeFailure = true;
      final store = await petStore(api);
      await mount(t, CustomerPetsPage(store: store));
      await openArchive(t);
      await confirm(t);
      expect(api.account['pets'].single['archived'], isTrue);
      expect(store.list('pets').single['id'], 'pet');
      final refresh = find.byKey(const ValueKey('refreshPetStatus'));
      await t.ensureVisible(refresh);
      await Scrollable.ensureVisible(t.element(refresh), alignment: 0.5);
      await t.pumpAndSettle();
      api.failRefresh = true;
      await t.tap(refresh);
      await t.pumpAndSettle();
      expect(refresh, findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(store.list('pets').single['id'], 'pet');
      expect(api.attempts, 1);
      api.failRefresh = false;
      await t.tap(refresh);
      await t.pumpAndSettle();
      expect(refresh, findsNothing);
      expect(store.list('pets'), isEmpty);
      expect(store.archivedPets.single['id'], 'pet');
      expect(api.attempts, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'changing stores dismisses the old confirmation without either write',
    (t) async {
      final oldApi = BrokenPetApi(), nextApi = BrokenPetApi();
      final old = await petStore(oldApi), next = await petStore(nextApi);
      final source = ValueNotifier(old);
      addTearDown(source.dispose);
      await mount(
        t,
        ValueListenableBuilder<CustomerStore>(
          valueListenable: source,
          builder: (_, store, _) => CustomerPetsPage(store: store),
        ),
      );
      await openArchive(t);
      source.value = next;
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(oldApi.attempts, 0);
      expect(nextApi.attempts, 0);
      await openArchive(t);
      await confirm(t);
      expect(oldApi.attempts, 0);
      expect(nextApi.attempts, 1);
    },
  );

  testWidgets(
    'retained repeated archive action creates one cancellable confirmation',
    (t) async {
      final api = BrokenPetApi();
      final store = await petStore(api);
      await mount(t, CustomerPetsPage(store: store));
      final action = t
          .widget<TextButton>(find.byKey(const ValueKey('archivePet-pet')))
          .onPressed!;
      action();
      action();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final back = find.widgetWithText(TextButton, 'Ortga');
      await t.ensureVisible(back);
      await t.tap(back);
      await t.pumpAndSettle();
      expect(api.attempts, 0);
      expect(store.list('pets').single['id'], 'pet');
      await openArchive(t);
      await confirm(t);
      expect(api.attempts, 1);
    },
  );

  testWidgets('removing pet page dismisses its confirmation without a write', (
    t,
  ) async {
    final api = BrokenPetApi();
    final store = await petStore(api);
    final page = ValueNotifier(true);
    addTearDown(page.dispose);
    await mount(
      t,
      ValueListenableBuilder<bool>(
        valueListenable: page,
        builder: (_, show, _) => show
            ? CustomerPetsPage(store: store)
            : const Scaffold(body: Text('NEXT PAGE')),
      ),
    );
    await openArchive(t);
    page.value = false;
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.attempts, 0);
    expect(find.text('NEXT PAGE'), findsOneWidget);
  });

  testWidgets(
    'session replaced while confirming cannot archive or show a stale error',
    (t) async {
      final api = BrokenPetApi();
      CustomerApi.active = api;
      final store = await petStore(api);
      await mount(t, CustomerPetsPage(store: store));
      await openArchive(t);
      CustomerApi.sessionVersion++;
      CustomerApi.active = BrokenPetApi();
      await confirm(t);
      expect(api.attempts, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(store.list('pets').single['id'], 'pet');
    },
  );

  testWidgets('late archive failure is not shown on a newer route', (t) async {
    final api = BrokenPetApi()..pending = Completer<CJson>();
    final store = await petStore(api);
    await mount(t, CustomerPetsPage(store: store));
    await openArchive(t);
    await confirm(t);
    final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('NEXT PAGE')),
        ),
      ),
    );
    await t.pumpAndSettle();
    api.pending!.completeError(const FormatException('PRIVATE response'));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('NEXT PAGE'), findsOneWidget);
    expect(api.attempts, 1);
    navigator.pop();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('refreshPetStatus')), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
  });
}
