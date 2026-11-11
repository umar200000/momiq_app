import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/bookings/data/booking_composer.dart';
import 'package:momiq_app/features/bookings/data/booking_controller.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';
import 'booking_controller_test.dart' show BookingApiFake, BookingMemory;
import 'booking_composer_test.dart' show ComposerApi, formFields;
import 'booking_primary_source_test.dart' show SourceApi, flowPage;

BookingJson composeDraft() => {
  'draft': formFields(),
  'quote': null,
  'pending': null,
};
BookingJson actionDraft() => {
  'action': 'accept',
  'body': {'revision': 0, 'requestId': 'test_retry_request_123', 'reason': ''},
};

class Unreadable extends BookingMemory {
  Object? failure;
  @override
  Future<BookingJson?> read() async {
    if (failure != null) throw failure!;
    return super.read();
  }

  @override
  Future<void> clear() async {
    await super.clear();
    failure = null;
  }
}

class BookingReadFailure extends BookingApiFake {
  bool failRead = false;
  @override
  Future<BookingJson> request(
    String method,
    String path, [
    BookingJson? body,
  ]) async {
    if (method == 'GET' && failRead) throw StateError('TEST offline');
    return super.request(method, path, body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AppLanguage.current.value = 'uz');
  test(
    'clearing uncertainty cannot reopen writes before authoritative reload',
    () async {
      final api = BookingReadFailure()..loseResponse = true;
      final storage = BookingMemory();
      final c = BookingController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.act('accept'), false);
      expect(c.pending, isNotNull);
      api.failRead = true;
      await c.discardUncertainAction();
      expect(c.pending, isNull);
      expect(c.ready, false);
      expect(await c.act('cancel', reason: 'TEST'), false);
      expect(api.posts.length, 1);
      api.failRead = false;
      await c.load();
      expect(c.ready, true);
      expect(c.booking!['status'], 'accepted');
      expect(c.error, isNull);
    },
  );
  for (final bad in <BookingJson>[
    {
      'petIds': [7],
    },
    {
      'petIds': ['owned', 'owned'],
    },
    {'petIds': List.generate(31, (i) => '$i')},
    {'startsAt': []},
    {'startsAt': '2030-01-01'},
    {'endsAt': false},
    {'addressId': 8},
    {'instructions': []},
    {'instructions': 'x' * 4001},
    {'petPassports': []},
    {
      'petPassports': {'owned': 1},
    },
    {
      'petPassports': {'owned': 'PRIVATE bad base64!'},
    },
    {'unknown': true},
  ]) {
    test(
      'malformed form ${bad.keys.first} stays off UI and transport',
      () async {
        final saved = {
          ...composeDraft(),
          'draft': {...formFields(), ...bad},
        };
        final memory = BookingMemory()..value = saved;
        final api = ComposerApi();
        final c = BookingComposer(api, 'sitter:boarding', storage: memory);
        addTearDown(c.dispose);
        await c.load();
        expect(c.invalidDraft, true);
        expect(c.ready, false);
        expect(c.draft, isEmpty);
        expect(c.pending, isNull);
        expect(c.error, isA<FormatException>());
        expect((c.error as FormatException).source, isNull);
        expect(await c.saveDraft(formFields()), false);
        expect(await c.getQuote(), false);
        expect(await c.submit(), false);
        expect(memory.value, saved);
        expect(api.submissions, isEmpty);
      },
    );
  }
  for (final saved in <BookingJson>[
    {'draft': []},
    {...composeDraft(), 'pending': []},
    {
      ...composeDraft(),
      'pending': {'quoteId': 'invalid', 'requestId': 'x' * 32},
    },
    {
      ...composeDraft(),
      'pending': {'quoteId': 'a' * 32, 'requestId': 'short'},
    },
    {
      ...composeDraft(),
      'pending': {'quoteId': 'a' * 32, 'requestId': 'x' * 32, 'extra': true},
    },
    {...composeDraft(), 'quote': []},
    {...composeDraft(), 'extra': true},
  ]) {
    test('invalid compose envelope ${saved.keys} cannot be resent', () async {
      final api = ComposerApi(), memory = BookingMemory()..value = saved;
      final c = BookingComposer(api, 'sitter:boarding', storage: memory);
      addTearDown(c.dispose);
      await c.load();
      expect(c.invalidDraft, true);
      expect(await c.submit(), false);
      expect(api.submissions, isEmpty);
      expect(memory.value, saved);
    });
  }
  for (final body in <BookingJson>[
    {'revision': -1},
    {'revision': '1'},
    {'requestId': 'short'},
    {'reason': []},
    {'reason': 'x' * 1001},
    {'extra': true},
  ]) {
    test('invalid action ${body.keys} cannot reach server', () async {
      final saved = {
        ...actionDraft(),
        'body': {...actionDraft()['body'], ...body},
      };
      final memory = BookingMemory()..value = saved;
      final api = BookingApiFake();
      final c = BookingController(api, 'a' * 32, storage: memory);
      addTearDown(c.dispose);
      await c.load();
      expect(c.invalidDraft, true);
      expect(c.pending, isNull);
      expect(await c.act('accept'), false);
      expect(api.posts, isEmpty);
      expect(memory.value, saved);
    });
  }
  test(
    'discarding a stale quote preserves a valid exact pending request',
    () async {
      final pending = {'quoteId': 'a' * 32, 'requestId': 'x' * 32};
      final memory = BookingMemory()
        ..value = {
          ...composeDraft(),
          'quote': {'broken': true},
          'pending': pending,
        };
      final api = ComposerApi(),
          c = BookingComposer(api, 'sitter:boarding', storage: memory);
      addTearDown(c.dispose);
      await c.load();
      expect(c.ready, true);
      expect(c.invalidDraft, false);
      expect(c.quote, isNull);
      expect(c.pending, pending);
      expect(await c.submit(), true);
      expect(api.submissions, [pending]);
    },
  );
  for (final kind in ['compose', 'detail']) {
    dynamic controller(dynamic api, WalletDraftStorage storage) =>
        kind == 'compose'
        ? BookingComposer(api, 'a' * 32, storage: storage)
        : BookingController(api, 'a' * 32, storage: storage);
    Future<void> clear(dynamic c) async {
      if (kind == 'compose') {
        await c.discardInvalidDraft();
      } else {
        await c.discardUncertainAction();
      }
    }

    test(
      '$kind read availability failure permits retry without clearing',
      () async {
        final storage = Unreadable()..failure = StateError('TEST unavailable');
        final api = SourceApi('TEST'), c = controller(api, storage);
        addTearDown(() => c.dispose());
        await c.load();
        expect(c.invalidDraft, false);
        expect(c.ready, false);
        storage.failure = null;
        await c.load();
        expect(c.ready, true);
        expect(api.calls.where((x) => x.startsWith('POST')), isEmpty);
      },
    );
    test('$kind cipher failure and failed clear remain recoverable', () async {
      final storage = Unreadable()
        ..failure = const FormatException('TEST broken file')
        ..failClear = true;
      final api = SourceApi('TEST'), c = controller(api, storage);
      addTearDown(() => c.dispose());
      await c.load();
      expect(c.invalidDraft, true);
      if (kind == 'detail') {
        await expectLater(clear(c), throwsStateError);
      } else {
        await clear(c);
      }
      expect(c.error, isA<StateError>());
      expect(c.invalidDraft, true);
      expect(c.ready, false);
      storage.failClear = false;
      await clear(c);
      expect(c.invalidDraft, false);
      expect(c.ready, true);
      expect(c.error, isNull);
      expect(api.calls.where((x) => x.startsWith('POST')), isEmpty);
    });
    test(
      '$kind actual authenticated file recovery does not delete on read',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp(
          'momiq-primary-draft-',
        );
        addTearDown(() async {
          await EncryptedWalletDraftStorage.clearAll(
            directory: () async => root,
          );
          await root.delete(recursive: true);
        });
        final storage = EncryptedWalletDraftStorage(
          owner: 'TEST',
          scope: kind,
          directory: () async => root,
        );
        await storage.write(kind == 'compose' ? composeDraft() : actionDraft());
        final file =
            (await Directory(
                  '${root.path}/wallet_drafts',
                ).list().toList()).single
                as File;
        final bytes = await file.readAsBytes();
        bytes[20] ^= 1;
        await file.writeAsBytes(bytes);
        final api = SourceApi('TEST'), c = controller(api, storage);
        addTearDown(() => c.dispose());
        await c.load();
        expect(c.invalidDraft, true);
        expect(await file.readAsBytes(), bytes);
        await clear(c);
        expect(c.ready, true);
        expect(await file.exists(), false);
        expect(api.calls.where((x) => x.startsWith('POST')), isEmpty);
      },
    );
    for (final language in ['uz', 'en', 'ru']) {
      testWidgets('$kind explicit recovery fits small $language screen', (
        t,
      ) async {
        AppLanguage.current.value = language;
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final storage = BookingMemory()..value = {'broken': 'PRIVATE'};
        final api = SourceApi('TEST'), c = controller(api, storage);
        addTearDown(() => c.dispose());
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: flowPage(kind, api, 'a' * 32, c),
          ),
        );
        await t.pumpAndSettle();
        expect(c.invalidDraft, true);
        expect(find.textContaining('PRIVATE'), findsNothing);
        final button = find.byKey(const ValueKey('clearInvalidBookingDraft'));
        await t.scrollUntilVisible(button, 160, maxScrolls: 40);
        await Scrollable.ensureVisible(t.element(button), alignment: 1);
        await t.pumpAndSettle();
        await t.tap(button);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(storage.value, isNotNull);
        final confirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        );
        await t.ensureVisible(confirm);
        await t.tap(confirm);
        await t.pumpAndSettle();
        expect(c.ready, true);
        expect(c.invalidDraft, false);
        expect(storage.value, isNull);
        expect(api.calls.where((x) => x.startsWith('POST')), isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
