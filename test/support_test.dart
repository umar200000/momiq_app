import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'package:momiq_app/features/notifications/presentation/notifications_page.dart';
import 'conversation_test.dart' show ChatDraft;
import 'notifications_test.dart' show NoticeApi;

class SupportApi extends CustomerApi {
  SupportApi() : super('test', 'owner');
  bool lost = false, offline = false;
  Completer<void>? gate;
  final posts = <SupportJson>[], keys = <String>{}, paths = <String>[];
  final messages = <SupportJson>[];
  SupportJson get ticket => {
    'id': 'a' * 32,
    'subject': 'TEST request',
    'status': 'waiting_user',
    'revision': messages.length,
  };
  SupportJson msg(int id, {String role = 'owner'}) => {
    'id': '$id',
    'text': 'TEST message $id',
    'authorRole': role,
    'hasImage': false,
    'created': '2026-10-28',
  };
  @override
  Future<SupportJson> request(
    String method,
    String path, [
    SupportJson? body,
  ]) async {
    paths.add(path);
    if (offline) throw StateError('offline');
    if (method == 'POST') {
      posts.add(Map.of(body!));
      if (keys.add(body['requestId'])) {
        messages.add({...msg(messages.length + 1), 'text': body['text']});
      }
      if (lost) {
        lost = false;
        throw StateError('Response lost');
      }
    } else if (gate != null) {
      await gate!.future;
    }
    if (path == '/support' && method == 'GET') {
      return {
        'items': [],
        'legacyItems': [
          {'text': 'TEST archived message'},
        ],
        'nextCursor': null,
      };
    }
    final before = Uri.parse(path).queryParameters['before'];
    final selected = messages
        .where((m) => before == null || int.parse(m['id']) < int.parse(before))
        .toList();
    final items = selected
        .skip(selected.length > 20 ? selected.length - 20 : 0)
        .toList();
    return {
      'ticket': ticket,
      'items': items,
      'nextCursor': selected.length > 20 ? items.first['id'] : null,
    };
  }
}

void main() {
  test(
    'lost create response survives restart with one ticket and original booking context',
    () async {
      final api = SupportApi()..lost = true, storage = ChatDraft();
      var c = SupportController(api, null, storage: storage);
      await c.load();
      expect(
        await c.send(
          'Original',
          null,
          subject: 'Help',
          topic: 'booking',
          bookingId: 'b' * 32,
        ),
        false,
      );
      final original = Map.of(storage.value!);
      c.dispose();
      c = SupportController(api, null, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.send('Replacement', null, subject: 'Changed'), true);
      expect(api.posts, [original, original]);
      expect(api.keys.length, 1);
      expect(storage.value, isNull);
    },
  );
  test(
    'local persistence failure prevents send; clear failure retries without duplicate',
    () async {
      final api = SupportApi(), storage = ChatDraft()..failWrite = true;
      final c = SupportController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.send('Save first', null), false);
      expect(api.posts, isEmpty);
      storage.failWrite = false;
      storage.failClear = true;
      expect(await c.send('Changed', null), false);
      expect(api.messages.single['text'], 'Save first');
      storage.failClear = false;
      expect(await c.send('Changed again', null), true);
      expect(api.keys.length, 1);
    },
  );
  test(
    'late response after account switch cannot populate another session',
    () async {
      final api = SupportApi()..gate = Completer<void>();
      final c = SupportController(api, 'a' * 32, storage: ChatDraft());
      addTearDown(c.dispose);
      final loading = c.load();
      await Future<void>.delayed(Duration.zero);
      CustomerApi.sessionVersion++;
      api.gate!.complete();
      await loading;
      expect(c.data, isNull);
      expect(await c.send('late', null), false);
    },
  );
  test('older message pages retain newest messages exactly once', () async {
    final api = SupportApi();
    api.messages.addAll(List.generate(45, (i) => api.msg(i + 1)));
    final c = SupportController(api, 'a' * 32, storage: ChatDraft());
    addTearDown(c.dispose);
    await c.load();
    await c.load(more: true);
    await c.load(more: true);
    expect(
      (c.data!['items'] as List).map((m) => m['id']).toList(),
      List.generate(45, (i) => '${i + 1}'),
    );
    expect(c.data!['nextCursor'], isNull);
  });
  testWidgets(
    'support replies are labelled and reopened server history remains visible',
    (t) async {
      final api = SupportApi()
        ..messages.add({
          'id': '1',
          'text': 'TEST operator reply',
          'resolution': {
            'snapshot': {
              'kind': 'listing',
              'available': true,
              'status': 'rejected',
              'sourceRevision': 4,
              'decision': {'reason': 'TEST saved moderation reason'},
            },
          },
          'authorRole': 'support',
          'hasImage': false,
          'created': '2026-10-28',
        });
      for (var i = 0; i < 2; i++) {
        final c = SupportController(api, 'a' * 32, storage: ChatDraft());
        await t.pumpWidget(
          MaterialApp(
            home: SupportThreadPage(api: api, id: 'a' * 32, controller: c),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Momiq yordam xizmati'), findsOneWidget);
        expect(find.text('TEST operator reply'), findsOneWidget);
        expect(find.text('TEST saved moderation reason'), findsOneWidget);
        expect(find.text('Yopish paytidagi qaror'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      }
    },
  );
  testWidgets(
    'offline list is not claimed empty; legacy archive survives migration',
    (t) async {
      final api = SupportApi()..offline = true;
      await t.pumpWidget(MaterialApp(home: SupportPage(api: api)));
      await t.pumpAndSettle();
      expect(find.text('Murojaatlar hali yo‘q.'), findsNothing);
      expect(find.text(supportError()), findsOneWidget);
      api.offline = false;
      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      await t.tap(find.text('Oldingi murojaatlar arxivi'));
      await t.pumpAndSettle();
      expect(find.text('TEST archived message'), findsOneWidget);
    },
  );
  testWidgets('support notice opens only its validated authenticated ticket', (
    t,
  ) async {
    final api = NoticeApi()..kind = 'support';
    String? opened;
    await t.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          api: api,
          supportBuilder: (source, id) {
            expect(identical(source, api), true);
            opened = id;
            return const Scaffold(body: Text('TEST support destination'));
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pumpAndSettle();
    await t.tap(find.text('Sahifani ochish'));
    await t.pumpAndSettle();
    expect(opened, api.targetId);
    await t.pumpWidget(const SizedBox());
    api.targetId = '../admin';
    await t.pumpWidget(MaterialApp(home: NotificationsPage(api: api)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('notice-2')));
    await t.pumpAndSettle();
    expect(find.text('Sahifani ochish'), findsNothing);
  });
}
