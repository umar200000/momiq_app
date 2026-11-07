import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/chat/data/conversation_controller.dart';
import 'package:momiq_app/features/chat/presentation/conversation_page.dart';
import 'conversation_test.dart' show ChatApi, ChatDraft;

void main() {
  for (final change in <ChatJson>[
    {'text': 7},
    {'image': true},
    {'image': 'broken!'},
    {'image': ''},
    {'requestId': ''},
    {'requestId': 'too_short'},
    {'text': '', 'image': null},
    {'unexpected': true},
  ]) {
    test('invalid outbox stays intact and never sends: $change', () async {
      final original = {
        'text': 'TEST original',
        'image': null,
        'requestId': 'test_outbox_123456',
        ...change,
      };
      final storage = ChatDraft()..value = Map.of(original);
      final api = ChatApi();
      final c = ConversationController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.ready, false);
      expect(c.error, isA<FormatException>());
      expect(c.pending, isNull);
      expect(await c.send('Replacement', null), false);
      expect(api.posts, isEmpty);
      expect(storage.value, original);
      storage.failClear = true;
      await expectLater(c.discardPending(), throwsStateError);
      expect(storage.value, original);
      storage.failClear = false;
      await c.discardPending();
      expect(storage.value, isNull);
      expect(c.ready, true);
      expect(await c.send('New message', null), true);
      expect(api.posts.single['text'], 'New message');
    });
  }

  for (final entry in {
    'uz': ['Saqlangan xabarni o‘qib bo‘lmadi.', 'Qoralamani tozalash'],
    'en': ['The saved message could not be read.', 'Clear outbox'],
    'ru': ['Не удалось прочитать сохранённое сообщение.', 'Очистить черновик'],
  }.entries) {
    testWidgets(
      'unreadable outbox has an explicit recovery action in ${entry.key}',
      (t) async {
        AppLanguage.current.value = entry.key;
        addTearDown(() => AppLanguage.current.value = 'uz');
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final original = {
          'text': 7,
          'image': true,
          'requestId': 'test_outbox_123456',
        };
        final storage = ChatDraft()..value = Map.of(original);
        final api = ChatApi();
        final c = ConversationController(api, 'a' * 32, storage: storage);
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
            home: ConversationPage(controller: c),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining(entry.value.first), findsOneWidget);
        expect(storage.value, original);
        final clear = find.text(entry.value.last);
        await t.ensureVisible(clear);
        await t.tap(clear);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(storage.value, original);
        final confirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        );
        await t.ensureVisible(confirm);
        await t.tap(confirm);
        await t.pumpAndSettle();
        expect(c.ready, true);
        expect(storage.value, isNull);
        expect(api.posts, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
