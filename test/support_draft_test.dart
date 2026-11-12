import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'conversation_test.dart' show ChatDraft;
import 'support_test.dart' show SupportApi;

Map<String, dynamic> draft() => {
  'text': 'Original message',
  'image': null,
  'revision': 0,
  'action': 'reply',
  'requestId': 'test_request_123456',
  'subject': 'Original subject',
  'topic': 'general',
  'bookingId': null,
};

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  test(
    'failed clear shows the storage error and keeps a valid retry intact',
    () async {
      final original = draft();
      final storage = ChatDraft()
        ..value = Map.of(original)
        ..failClear = true;
      final api = SupportApi();
      final c = SupportController(api, null, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      await c.discard();
      expect(c.error, isA<StateError>());
      expect(c.pending, original);
      expect(storage.value, original);
      expect(api.posts, isEmpty);
      storage.failClear = false;
      expect(await c.send('Replacement', null, subject: 'Changed'), true);
      expect(api.posts, [original]);
    },
  );
  test(
    'failed explicit clear retains invalid draft and blocks sending',
    () async {
      final original = {...draft(), 'text': 17};
      final storage = ChatDraft()
        ..value = Map.of(original)
        ..failClear = true;
      final api = SupportApi();
      final c = SupportController(api, null, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      await c.discard();
      expect(c.invalidDraft, true);
      expect(storage.value, original);
      expect(await c.send('Replacement', null, subject: 'New'), false);
      expect(api.posts, isEmpty);
      storage.failClear = false;
      await c.discard();
      expect(c.invalidDraft, false);
      expect(c.error, isNull);
    },
  );

  for (final entry in {
    'uz': [
      'Saqlangan xabarni o‘qib bo‘lmadi.',
      'Qayta yuborish qoralamasini tozalash',
    ],
    'en': ['The saved message could not be read.', 'Clear retry draft'],
    'ru': [
      'Не удалось прочитать сохранённое сообщение.',
      'Очистить черновик повтора',
    ],
  }.entries) {
    testWidgets(
      'invalid draft recovery is usable in ${entry.key} on a small screen',
      (t) async {
        AppLanguage.current.value = entry.key;
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final storage = ChatDraft()..value = {...draft(), 'text': []};
        final api = SupportApi();
        final c = SupportController(api, null, storage: storage);
        addTearDown(c.dispose);
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 240),
              ),
              child: child!,
            ),
            home: SupportThreadPage(api: api, controller: c),
          ),
        );
        await t.pumpAndSettle();
        expect(find.textContaining(entry.value.first), findsOneWidget);
        final clear = find.text(entry.value.last);
        await t.scrollUntilVisible(
          clear,
          180,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 40,
        );
        await t.pumpAndSettle();
        await Scrollable.ensureVisible(t.element(clear), alignment: 1);
        await t.pumpAndSettle();
        await t.tap(clear);
        await t.pumpAndSettle();
        expect(storage.value, isNull);
        expect(api.posts, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final change in <Map<String, dynamic>>[
    {'text': 17},
    {'subject': []},
    {'image': true},
    {'image': 'not valid base64!'},
    {'image': ''},
    {'revision': '0'},
    {'revision': -1},
    {'requestId': ''},
    {'action': 'resolve'},
    {'topic': []},
    {'target': 'broken'},
    {
      'target': {'kind': 'listing', 'id': 1},
    },
    {'confirmAccountRequest': 'true'},
    {'appealRevision': '1'},
  ]) {
    test('corrupt support draft is retained without POST: $change', () async {
      final original = {...draft(), ...change};
      final storage = ChatDraft()..value = Map.of(original);
      final api = SupportApi();
      final c = SupportController(api, null, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(c.error, isA<FormatException>());
      expect(await c.send('Replacement', null, subject: 'Replacement'), false);
      expect(api.posts, isEmpty);
      expect(storage.value, original);
      await c.discard();
      expect(storage.value, isNull);
      expect(await c.send('New message', null, subject: 'New subject'), true);
      expect(api.posts.single['text'], 'New message');
    });
  }

  testWidgets('corrupt restored fields cannot crash the support editor', (
    t,
  ) async {
    final original = {...draft(), 'text': 17};
    final storage = ChatDraft()..value = Map.of(original);
    final api = SupportApi();
    final c = SupportController(api, null, storage: storage);
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: SupportThreadPage(api: api, controller: c),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(api.posts, isEmpty);
    expect(storage.value, original);
    final clear = find.text('Qayta yuborish qoralamasini tozalash');
    await t.ensureVisible(clear);
    await t.tap(clear);
    await t.pumpAndSettle();
    expect(storage.value, isNull);
    expect(c.error, isNull);
    expect(t.takeException(), isNull);
  });
}
