import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_account.dart';
import 'package:momiq_app/features/onboarding/data/profile_photo_source.dart';
import 'settings_session_boundary_test.dart' show SettingsApi, settingsStore;

Future<CustomerStore> fixture(SettingsApi api) {
  api.account['pets'] = [
    {
      'id': 'pet',
      'name': 'TEST pet',
      'type': 'Mushuk',
      'age': '',
      'photo': base64Encode(
        File('assets/images/service_cat.png').readAsBytesSync(),
      ),
    },
  ];
  api.account['addresses'] = [
    {
      'id': 'address',
      'label': 'TEST home',
      'address': 'TEST Tashkent',
      'lat': 41.3,
      'lon': 69.2,
    },
  ];
  return settingsStore(api);
}

class PendingPhoto extends ProfilePhotoSource {
  final result = Completer<Uint8List?>();
  int calls = 0;
  @override
  Future<Uint8List?> pickProfile({ImageSource source = ImageSource.gallery}) {
    calls++;
    return result.future;
  }
}

Widget form(
  String kind,
  CustomerStore store, {
  String? id,
  ProfilePhotoSource? photos,
}) => switch (kind) {
  'pet' => CustomerPetForm(
    store: store,
    photoSource: photos,
    pet: {...store.list('pets').first, 'id': ?id},
  ),
  'address' => CustomerAddressForm(
    store: store,
    address: {...store.list('addresses').first, 'id': ?id},
  ),
  _ => CustomerProfileForm(store: store, photoSource: photos),
};

Future<void> edit(WidgetTester t, String kind) async {
  final field = switch (kind) {
    'pet' => find.byKey(const ValueKey('customerPetName')),
    'address' => find.byType(TextField).first,
    _ => find.byKey(const ValueKey('customerFirst')),
  };
  await t.ensureVisible(field);
  await t.enterText(field, 'TEST changed');
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
}

Finder get save => find.widgetWithText(FilledButton, 'Saqlash');

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

  for (final kind in ['profile', 'pet', 'address']) {
    testWidgets(
      '$kind newly mounted form cannot authorize an old session store',
      (t) async {
        final api = SettingsApi();
        final store = await fixture(api);
        CustomerApi.sessionVersion++;
        await t.pumpWidget(MaterialApp(home: form(kind, store)));
        await t.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(find.textContaining('TEST'), findsNothing);
        expect(save, findsNothing);
        expect(api.writes, 0);
      },
    );

    for (final fails in [false, true]) {
      testWidgets(
        '$kind late save never pops or reports on a newer route, failure=$fails',
        (t) async {
          final api = SettingsApi();
          final store = await fixture(api);
          await t.pumpWidget(MaterialApp(home: form(kind, store)));
          await t.pumpAndSettle();
          await edit(t, kind);
          api.gate = Completer<void>();
          api.broken = fails;
          await t.tap(save);
          await t.pump();
          final nav = t.state<NavigatorState>(find.byType(Navigator).first);
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('NEXT PAGE')),
              ),
            ),
          );
          await t.pump(const Duration(seconds: 1));
          api.gate!.complete();
          await t.pumpAndSettle();
          expect(find.text('NEXT PAGE'), findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          expect(api.writes, 1);
          nav.pop();
          await t.pumpAndSettle();
          expect(find.text('TEST changed'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets('$kind old inputs cannot be saved into a replacement store', (
      t,
    ) async {
      final oldApi = SettingsApi(), nextApi = SettingsApi();
      final old = await fixture(oldApi), next = await fixture(nextApi);
      final source = ValueNotifier(old);
      addTearDown(source.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<CustomerStore>(
            valueListenable: source,
            builder: (_, store, _) => form(kind, store),
          ),
        ),
      );
      await t.pumpAndSettle();
      await edit(t, kind);
      final action = t.widget<FilledButton>(save).onPressed!;
      source.value = next;
      await t.pumpAndSettle();
      action();
      await t.pumpAndSettle();
      expect(oldApi.writes, 0);
      expect(nextApi.writes, 0);
      expect(find.byType(TextFormField), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('$kind retained save after disposal sends nothing', (t) async {
      final api = SettingsApi();
      final store = await fixture(api);
      await t.pumpWidget(MaterialApp(home: form(kind, store)));
      await t.pumpAndSettle();
      await edit(t, kind);
      final action = t.widget<FilledButton>(save).onPressed!;
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('NEXT PAGE'))),
      );
      action();
      await t.pumpAndSettle();
      expect(api.writes, 0);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      '$kind invalid session hides its form without a parent rebuild',
      (t) async {
        final api = SettingsApi();
        final store = await fixture(api);
        await t.pumpWidget(MaterialApp(home: form(kind, store)));
        await t.pumpAndSettle();
        CustomerApi.sessionVersion++;
        await t.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(save, findsNothing);
        expect(api.writes, 0);
      },
    );

    testWidgets(
      '$kind parser failure preserves input and hides private response',
      (t) async {
        final api = SettingsApi()..broken = true;
        final store = await fixture(api);
        await t.pumpWidget(MaterialApp(home: form(kind, store)));
        await t.pumpAndSettle();
        await edit(t, kind);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.text('TEST changed'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(api.writes, 1);
      },
    );
  }

  for (final kind in ['pet', 'address']) {
    testWidgets('$kind changed target cannot receive old draft fields', (
      t,
    ) async {
      final api = SettingsApi();
      final store = await fixture(api);
      final target = ValueNotifier<String?>(null);
      addTearDown(target.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String?>(
            valueListenable: target,
            builder: (_, id, _) => form(kind, store, id: id),
          ),
        ),
      );
      await t.pumpAndSettle();
      await edit(t, kind);
      final action = t.widget<FilledButton>(save).onPressed!;
      target.value = 'other';
      await t.pumpAndSettle();
      action();
      await t.pumpAndSettle();
      expect(api.writes, 0);
      expect(find.byType(TextFormField), findsNothing);
    });
  }

  for (final page in ['pets', 'settings', 'addresses']) {
    testWidgets('newly mounted account page rejects an old store, page=$page', (
      t,
    ) async {
      final api = SettingsApi();
      final store = await fixture(api);
      CustomerApi.sessionVersion++;
      await t.pumpWidget(
        MaterialApp(
          home: switch (page) {
            'pets' => CustomerPetsPage(store: store),
            'addresses' => CustomerAddressesPage(store: store),
            _ => CustomerSettingsPage(store: store),
          },
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('TEST'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byKey(const ValueKey('archivePet-pet')), findsNothing);
      expect(api.writes, 0);
    });
    testWidgets(
      '$page hides personal data on session change without parent rebuild',
      (t) async {
        final store = await fixture(SettingsApi());
        await t.pumpWidget(
          MaterialApp(
            home: switch (page) {
              'pets' => CustomerPetsPage(store: store),
              'addresses' => CustomerAddressesPage(store: store),
              _ => CustomerSettingsPage(store: store),
            },
          ),
        );
        await t.pumpAndSettle();
        CustomerApi.sessionVersion++;
        await t.pumpAndSettle();
        expect(find.textContaining('TEST'), findsNothing);
        expect(find.byType(SwitchListTile), findsNothing);
        expect(find.text('Hisobingizga qayta kiring.'), findsOneWidget);
      },
    );
  }

  for (final fails in [false, true]) {
    testWidgets(
      'address delete completion belongs to its form, failure=$fails',
      (t) async {
        final api = SettingsApi();
        final store = await fixture(api);
        await t.pumpWidget(MaterialApp(home: form('address', store)));
        await t.pumpAndSettle();
        final remove = find.widgetWithText(FilledButton, 'Manzilni o‘chirish');
        await t.ensureVisible(remove);
        await t.tap(remove);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        api.gate = Completer<void>();
        api.broken = fails;
        await t.tap(find.widgetWithText(FilledButton, 'O‘chirish'));
        await t.pump();
        final nav = t.state<NavigatorState>(find.byType(Navigator).first);
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('NEXT PAGE')),
            ),
          ),
        );
        await t.pump(const Duration(seconds: 1));
        api.gate!.complete();
        await t.pumpAndSettle();
        expect(find.text('NEXT PAGE'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(api.writes, 1);
        expect(store.list('addresses'), hasLength(fails ? 1 : 0));
      },
    );
  }

  testWidgets('address rebind cancels its outstanding delete confirmation', (
    t,
  ) async {
    final oldApi = SettingsApi(), nextApi = SettingsApi();
    final old = await fixture(oldApi), next = await fixture(nextApi);
    final source = ValueNotifier(old);
    addTearDown(source.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<CustomerStore>(
          valueListenable: source,
          builder: (_, store, _) => form('address', store),
        ),
      ),
    );
    await t.pumpAndSettle();
    final remove = find.widgetWithText(FilledButton, 'Manzilni o‘chirish');
    await t.ensureVisible(remove);
    await t.tap(remove);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    source.value = next;
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(oldApi.writes, 0);
    expect(nextApi.writes, 0);
  });

  for (final (language, remove, back) in [
    ('uz', 'Manzilni o‘chirish', 'Ortga'),
    ('en', 'Delete address', 'Back'),
    ('ru', 'Удалить адрес', 'Назад'),
  ]) {
    testWidgets(
      '$language address delete confirmation fits and cancel does not write',
      (t) async {
        final api = SettingsApi();
        final store = await fixture(api);
        AppLanguage.current.value = language;
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
            home: form('address', store),
          ),
        );
        await t.pumpAndSettle();
        final removeButton = find.widgetWithText(FilledButton, remove);
        await t.scrollUntilVisible(
          removeButton,
          180,
          maxScrolls: 30,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(t.element(removeButton), alignment: .4);
        await t.pumpAndSettle();
        await t.tap(removeButton);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(t.takeException(), isNull);
        final cancel = find.widgetWithText(TextButton, back);
        await t.ensureVisible(cancel);
        await t.tap(cancel);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(api.writes, 0);
        expect(store.list('addresses'), hasLength(1));
      },
    );
  }

  for (final kind in ['profile', 'pet']) {
    for (final picking in [false, true]) {
      testWidgets('$kind session change cancels photo work, picking=$picking', (
        t,
      ) async {
        final api = SettingsApi();
        final store = await fixture(api);
        final photos = PendingPhoto();
        await t.pumpWidget(
          MaterialApp(home: form(kind, store, photos: photos)),
        );
        await t.pumpAndSettle();
        final picker = find.byKey(
          ValueKey(
            kind == 'pet' ? 'pickCustomerPetPhoto' : 'pickCustomerProfilePhoto',
          ),
        );
        await t.ensureVisible(picker);
        await t.tap(picker);
        await t.pumpAndSettle();
        if (picking) {
          await t.tap(
            find.byKey(
              ValueKey('${kind == 'pet' ? 'pet' : 'profile'}Photo-gallery'),
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
        }
        CustomerApi.sessionVersion++;
        await t.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        photos.result.complete(
          File('assets/images/service_cat.png').readAsBytesSync(),
        );
        await t.pumpAndSettle();
        expect(photos.calls, picking ? 1 : 0);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(api.writes, 0);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('$kind photo source sheet closes with its form', (t) async {
      final api = SettingsApi();
      final store = await fixture(api);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, _) => show
                ? form(kind, store)
                : const Scaffold(body: Text('NEXT PAGE')),
          ),
        ),
      );
      await t.pumpAndSettle();
      final picker = find.byKey(
        ValueKey(
          kind == 'pet' ? 'pickCustomerPetPhoto' : 'pickCustomerProfilePhoto',
        ),
      );
      await t.ensureVisible(picker);
      await t.tap(picker);
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      visible.value = false;
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('NEXT PAGE'), findsOneWidget);
      expect(api.writes, 0);
    });
  }
}
