import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/support/support_data.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'conversation_test.dart' show ChatDraft;
import 'support_test.dart' show SupportApi;

class ContractApi extends SupportApi {
  SupportJson Function(String, String, SupportJson)? transform;
  @override
  Future<SupportJson> request(
    String method,
    String path, [
    SupportJson? body,
  ]) async {
    final result = await super.request(method, path, body);
    if (method == 'GET' && path == '/support') result['items'] = [ticket];
    return transform?.call(method, path, result) ?? result;
  }
}

void main() {
  test(
    'wrong support receipt preserves the original draft for retry',
    () async {
      final api = ContractApi();
      final store = ChatDraft(),
          c = SupportController(api, null, storage: store);
      addTearDown(c.dispose);
      await c.load();
      api.transform = (method, _, data) {
        if (method == 'POST')
          data['acknowledgement']['requestId'] = 'unrelated';
        return data;
      };
      expect(await c.send('TEST request', null, subject: 'TEST'), false);
      final original = Map.of(c.pending!);
      api.transform = null;
      expect(await c.send('edited', null, subject: 'edited'), true);
      expect(api.posts, [original, original]);
      expect(store.value, isNull);
    },
  );
  test(
    'list rejects malformed rows, duplicates and unusable cursors atomically',
    () {
      final row = ContractApi().ticket;
      final valid = <String, dynamic>{
        'items': [row],
        'nextCursor': null,
      };
      expect(supportList(valid)['items'], [row]);
      for (final bad in [
        {
          ...valid,
          'items': [
            row,
            {...row, 'subject': null},
          ],
        },
        {
          ...valid,
          'items': [row, row],
        },
        {
          ...valid,
          'items': [
            {...row, 'id': '../admin'},
          ],
        },
        {
          ...valid,
          'items': [
            {...row, 'revision': -1},
          ],
        },
        {
          ...valid,
          'items': [
            {...row, 'updated': 'invalid'},
          ],
        },
        {
          ...valid,
          'items': [
            {...row, 'status': 'unknown'},
          ],
        },
        {...valid, 'nextCursor': '3&status=open'},
        {...valid, 'items': [], 'nextCursor': '1'},
        {
          ...valid,
          'legacyItems': [
            {'text': false},
          ],
        },
        {...valid, 'items': List.filled(21, row)},
      ]) {
        expect(() => supportList(bad), throwsFormatException);
      }
      expect(
        () => supportList({...valid, 'nextCursor': '9'}, before: '8'),
        throwsFormatException,
      );
    },
  );
  test(
    'thread rejects wrong identity, backwards revision and malformed messages',
    () {
      final api = ContractApi();
      final valid = <String, dynamic>{
        'ticket': api.ticket,
        'items': [api.msg(1), api.msg(2)],
        'nextCursor': null,
      };
      expect(supportThread(valid, id: 'a' * 32)['items'].length, 2);
      expect(() => supportThread(valid, id: 'b' * 32), throwsFormatException);
      expect(
        () => supportThread(valid, minimumRevision: 1),
        throwsFormatException,
      );
      for (final bad in [
        {
          ...valid,
          'items': [api.msg(1), api.msg(1)],
        },
        {
          ...valid,
          'items': [api.msg(2), api.msg(1)],
        },
        {
          ...valid,
          'items': [
            {...api.msg(1), 'text': null},
          ],
        },
        {
          ...valid,
          'items': [
            {...api.msg(1), 'authorRole': 'administrator'},
          ],
        },
        {
          ...valid,
          'items': [
            {...api.msg(1), 'hasImage': 'true'},
          ],
        },
        {
          ...valid,
          'items': [
            {...api.msg(1), 'id': '../photo'},
          ],
        },
        {...valid, 'nextCursor': '2'},
        {
          ...valid,
          'target': {'kind': 'review', 'id': 7, 'purpose': 'report'},
        },
      ]) {
        expect(() => supportThread(bad), throwsFormatException);
      }
      expect(() => supportThread(valid, before: '2'), throwsFormatException);
    },
  );
  test(
    'acknowledgement without a revision advance preserves retry draft',
    () async {
      final api = ContractApi(), storage = ChatDraft();
      final c = SupportController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      api.transform = (method, path, data) => {
        ...data,
        'ticket': {...data['ticket'], 'revision': 0},
      };
      expect(await c.send('TEST message', null), false);
      expect(storage.value, isNotNull);
      expect(c.error, isA<FormatException>());
    },
  );
  test('valid Unicode counts server code points rather than UTF-16 units', () {
    final api = ContractApi();
    final ticket = {...api.ticket, 'subject': '🐈' * 120};
    expect(
      supportList({
        'items': [ticket],
        'nextCursor': null,
      })['items'],
      [ticket],
    );
    final message = {...api.msg(1), 'text': '🐕' * 4000};
    expect(
      supportThread({
        'ticket': ticket,
        'items': [message],
        'nextCursor': null,
      })['items'],
      [message],
    );
  });
  test(
    'malformed acknowledged send keeps retry identity and last valid history',
    () async {
      final api = ContractApi(), storage = ChatDraft();
      final c = SupportController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.load();
      final previous = c.data;
      api.transform = (method, path, data) => method == 'POST'
          ? {
              ...data,
              'ticket': {...data['ticket'], 'id': 'b' * 32},
            }
          : data;
      expect(await c.send('TEST original', null), false);
      final saved = Map<String, dynamic>.of(storage.value!);
      expect(c.data, same(previous));
      expect(c.pending, saved);
      expect(c.error, isA<FormatException>());
      api.transform = null;
      expect(await c.send('Replacement should not be sent', null), true);
      expect(api.posts, [saved, saved]);
      expect(api.keys.length, 1);
      expect(storage.value, isNull);
    },
  );
  test(
    'invalid older page retains history, cursor and permits a correct retry',
    () async {
      final api = ContractApi();
      api.messages.addAll(List.generate(45, (i) => api.msg(i + 1)));
      final c = SupportController(api, 'a' * 32, storage: ChatDraft());
      addTearDown(c.dispose);
      await c.load();
      final previous = c.data;
      api.transform = (method, path, data) => {...data, 'nextCursor': '26'};
      await c.load(more: true);
      expect(c.data, same(previous));
      expect(c.error, isA<FormatException>());
      api.transform = null;
      await c.load(more: true);
      expect(c.data!['items'].length, 40);
      expect(c.data!['nextCursor'], '6');
    },
  );
  testWidgets(
    'invalid list refresh retains visible subject and retries without empty claim',
    (t) async {
      final api = ContractApi();
      await t.pumpWidget(MaterialApp(home: SupportPage(api: api)));
      await t.pumpAndSettle();
      expect(find.text('TEST request'), findsOneWidget);
      api.transform = (method, path, data) => {
        ...data,
        'items': [
          api.ticket,
          {...api.ticket, 'subject': false},
        ],
      };
      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      expect(find.text('TEST request'), findsOneWidget);
      expect(find.text(supportError()), findsOneWidget);
      expect(find.text('Murojaatlar hali yo‘q.'), findsNothing);
      expect(t.takeException(), isNull);
      api.transform = null;
      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      expect(find.text(supportError()), findsNothing);
    },
  );
  testWidgets('malformed initial thread shows retry and no enabled send', (
    t,
  ) async {
    final api = ContractApi()
      ..transform = (method, path, data) => {
        ...data,
        'items': [
          {'text': null},
        ],
      };
    final c = SupportController(api, 'a' * 32, storage: ChatDraft());
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: SupportThreadPage(api: api, id: 'a' * 32, controller: c),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text(supportError()), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('sendSupport')))
          .onPressed,
      isNull,
    );
    expect(c.data, isNull);
    expect(t.takeException(), isNull);
    api.transform = null;
    await t.tap(find.byIcon(Icons.refresh));
    await t.pumpAndSettle();
    expect(find.text(supportError()), findsNothing);
    expect(c.data, isNotNull);
  });
}
