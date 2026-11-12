import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/chat/data/conversation_controller.dart';
import 'package:momiq_app/features/chat/data/conversation_data.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'conversation_test.dart' show ChatApi, ChatDraft, msg;

class ControlledChat extends ChatApi {
  Completer<void>? getGate, blockGate;
  ChatJson Function(String, ChatJson)? rewrite;
  bool badReceipt = false;
  @override
  Future<ChatJson> request(String method, String path, [ChatJson? body]) async {
    if (path.endsWith('/block') && blockGate != null) await blockGate!.future;
    final response = ChatJson.from(
      jsonDecode(jsonEncode(await super.request(method, path, body))),
    );
    if (method == 'GET' && getGate != null) await getGate!.future;
    if (badReceipt && (path.endsWith('/read') || path.endsWith('/received'))) {
      return {'ok': false};
    }
    return rewrite?.call(method, response) ?? response;
  }
}

class SlowClear extends ChatDraft {
  Completer<void>? gate;
  int clears = 0;
  @override
  Future<void> clear() async {
    clears++;
    if (gate != null) await gate!.future;
    await super.clear();
  }
}

void main() {
  for (final during in [false, true]) {
    test(
      'old poll ${during ? 'during' : 'before'} block cannot restore send capability',
      () async {
        final api = ControlledChat()..items.add(msg(1));
        final c = ConversationController(api, 'a' * 32, storage: ChatDraft());
        addTearDown(c.dispose);
        await c.initialize();
        api.getGate = Completer<void>();
        Future<void>? blocking;
        if (during) {
          api.blockGate = Completer<void>();
          blocking = c.setBlocked(true);
        }
        final refreshing = c.refresh();
        await Future<void>.delayed(Duration.zero);
        if (during) {
          api.blockGate!.complete();
          await blocking;
        } else {
          await c.setBlocked(true);
        }
        expect(c.conversation!['canSend'], false);
        api.getGate!.complete();
        await refreshing;
        expect(c.conversation!['canSend'], false);
        expect(c.conversation!['blockRevision'], 1);
      },
    );
  }
  test(
    'malformed page cannot partly alter history, summary or delta cursor',
    () async {
      final api = ControlledChat()..items.add(msg(1, text: 'saved'));
      final c = ConversationController(api, 'a' * 32, storage: ChatDraft());
      addTearDown(c.dispose);
      await c.initialize();
      final previous = jsonEncode(c.messages),
          summary = jsonEncode(c.conversation);
      api.items.add(msg(2, text: 'next'));
      api.rewrite = (method, data) => {
        ...data,
        'items': [
          msg(2),
          {...msg(3), 'id': 'bad'},
        ],
        'conversation': {...data['conversation'], 'peerName': 'untrusted'},
      };
      await c.refresh();
      expect(c.error, isA<FormatException>());
      expect(jsonEncode(c.messages), previous);
      expect(jsonEncode(c.conversation), summary);
      expect(c.readCursor, '1');
      api.rewrite = null;
      await c.refresh();
      expect(c.readCursor, '2');
      expect(c.messages.last['text'], 'next');
    },
  );
  test(
    'unrelated send acknowledgement retains exact outbox for retry',
    () async {
      final api = ControlledChat(), storage = ChatDraft();
      final c = ConversationController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.initialize();
      api.rewrite = (method, data) =>
          method == 'POST' ? {...data, 'requestId': 'wrong-request'} : data;
      expect(await c.send('original', null), false);
      final saved = Map.of(storage.value!);
      expect(c.messages, isEmpty);
      expect(c.pending, saved);
      api.rewrite = null;
      expect(await c.send('replacement', null), true);
      expect(api.posts, [saved, saved]);
      expect(api.items.length, 1);
      expect(storage.value, isNull);
    },
  );
  test('false delivery/read acknowledgements remain retryable', () async {
    final api = ControlledChat()
      ..badReceipt = true
      ..items.add(msg(1));
    final c = ConversationController(api, 'a' * 32, storage: ChatDraft());
    addTearDown(c.dispose);
    await c.initialize();
    await Future<void>.delayed(Duration.zero);
    await c.readThrough('1');
    await c.refresh();
    await Future<void>.delayed(Duration.zero);
    await c.readThrough('1');
    expect(api.deliveries, ['1', '1']);
    expect(api.reads, ['1', '1']);
    api.badReceipt = false;
    await c.refresh();
    await Future<void>.delayed(Duration.zero);
    await c.readThrough('1');
    await c.refresh();
    await c.readThrough('1');
    expect(api.deliveries, ['1', '1', '1']);
    expect(api.reads, ['1', '1', '1']);
  });
  test(
    'discard and send cannot race local storage and expired discard writes nothing',
    () async {
      final api = ControlledChat()..loseResponse = true, storage = SlowClear();
      final c = ConversationController(api, 'a' * 32, storage: storage);
      addTearDown(c.dispose);
      await c.initialize();
      await c.send('original', null);
      storage.gate = Completer<void>();
      final discarding = c.discardPending();
      expect(await c.send('new', null), false);
      expect(api.posts.length, 1);
      await c.discardPending();
      expect(storage.clears, 1);
      storage.gate!.complete();
      await discarding;
      storage.value = {'text': 'protected'};
      CustomerApi.sessionVersion++;
      await expectLater(c.discardPending(), throwsStateError);
      expect(storage.value, {'text': 'protected'});
      expect(storage.clears, 1);
    },
  );
  test(
    'message and summary schema reject forged IDs, types and mixed pages',
    () {
      final api = ChatApi();
      expect(chatSummary(api.summary)['id'], 'a' * 32);
      for (final bad in [
        {...api.summary, 'id': '../admin'},
        {...api.summary, 'canSend': 'yes'},
        {...api.summary, 'blockRevision': -1},
        {...api.summary, 'peerReadThrough': '-1'},
        {...api.summary, 'unreadCount': null},
      ]) {
        expect(() => chatSummary(bad), throwsFormatException);
      }
      final valid = {
        'conversation': api.summary,
        'items': [msg(1)],
        'redactedIds': <String>[],
        'hasMore': false,
        'changeCursor': '0',
      };
      for (final bad in [
        {
          ...valid,
          'items': [msg(1), msg(1)],
        },
        {
          ...valid,
          'items': [msg(2), msg(1)],
        },
        {
          ...valid,
          'redactedIds': ['../1'],
        },
        {...valid, 'hasMore': true},
        {...valid, 'changeCursor': null},
      ]) {
        expect(() => chatPage(bad, id: 'a' * 32), throwsFormatException);
      }
      expect(() => chatPage(valid, id: 'b' * 32), throwsFormatException);
      expect(
        () => chatPage(valid, id: 'a' * 32, after: '1'),
        throwsFormatException,
      );
      expect(
        () => chatPage(valid, id: 'a' * 32, changesAfter: '1'),
        throwsFormatException,
      );
      expect(
        chatMessage({
          ...msg(1),
          'hidden': true,
          'text': 'private',
          'hasImage': true,
        })['text'],
        '',
      );
      expect(
        () => chatMessage(msg(1), requestId: 'missing'),
        throwsFormatException,
      );
    },
  );
  test(
    'inbox and report pages enforce cursors, order and exact report acknowledgements',
    () {
      final api = ChatApi(),
          report = {
            'id': '2',
            'messageId': '3',
            'reason': 'TEST',
            'status': 'open',
            'revision': 0,
            'created': '2026-10-29T00:00:00Z',
          };
      expect(
        () => chatInbox({
          'items': [api.summary, api.summary],
          'nextCursor': null,
        }),
        throwsFormatException,
      );
      expect(
        () => chatInbox({
          'items': [api.summary],
          'nextCursor': '2:1',
        }, before: '1:1'),
        throwsFormatException,
      );
      expect(
        () => chatReportPage({
          'items': [report, report],
          'nextCursor': null,
        }),
        throwsFormatException,
      );
      expect(
        () => chatReportPage({
          'items': [report],
          'nextCursor': '1',
        }),
        throwsFormatException,
      );
      expect(
        () => chatReport(report, messageId: '4', reason: 'TEST'),
        throwsFormatException,
      );
      expect(
        () => chatReport(report, messageId: '3', reason: 'changed'),
        throwsFormatException,
      );
      expect(
        chatReportPage({
          'items': [report],
          'nextCursor': '2',
        })['items'],
        [report],
      );
    },
  );
}
