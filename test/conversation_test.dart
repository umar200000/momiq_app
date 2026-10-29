import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/chat/data/conversation_controller.dart';
import 'package:momiq_app/features/chat/presentation/conversation_page.dart';
import 'package:momiq_app/features/chat/presentation/chat_reports.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';

class ChatDraft extends WalletDraftStorage {
  ChatJson? value;
  bool failWrite = false, failClear = false;
  @override
  Future<ChatJson?> read() async => value == null ? null : Map.of(value!);
  @override
  Future<void> write(ChatJson data) async {
    if (failWrite) throw StateError('Disk unavailable');
    value = Map.of(data);
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('Disk unavailable');
    value = null;
  }
}

ChatJson msg(
  int id, {
  bool mine = false,
  String? request,
  String text = 'hello',
}) => {
  'id': '$id',
  'mine': mine,
  'senderRole': mine ? 'customer' : 'sitter',
  'text': text,
  'hasImage': false,
  'created': '2026-10-28T10:00:00Z',
  'requestId': request,
};

class ChatApi extends CustomerApi {
  ChatApi() : super('test', 'customer');
  final items = <ChatJson>[];
  final posts = <ChatJson>[];
  final paths = <String>[];
  final reads = <String>[];
  final deliveries = <String>[];
  bool failDelivery = false;
  String identity = 'a' * 32;
  String peerDelivered = '0', peerRead = '0';
  bool loseResponse = false;
  bool paginated = false;
  bool blocked = false;
  int blockRevision = 0;
  final redactions = <String>[];
  Completer<void>? postGate;
  ChatJson get summary => {
    'id': identity,
    'peerName': 'TEST sitter',
    'service': 'boarding',
    'myRole': 'customer',
    'canSend': !blocked,
    'blockedByMe': blocked,
    'blockRevision': blockRevision,
    'unreadCount': 1,
    'peerReadThrough': peerRead,
    'peerDeliveredThrough': peerDelivered,
    'lastMessage': items.lastOrNull,
  };
  @override
  Future<ChatJson> request(String method, String path, [ChatJson? body]) async {
    paths.add('$method $path');
    if (path.startsWith('/conversations/')) identity = path.split('/')[2];
    if (path.endsWith('/received')) {
      deliveries.add(body!['throughId']);
      if (failDelivery) throw StateError('receipt unavailable');
      return {'ok': true};
    }
    if (path.endsWith('/block')) {
      blocked = body!['blocked'];
      blockRevision++;
      return summary;
    }
    if (path.endsWith('/read')) {
      reads.add(body!['throughId']);
      return {'ok': true};
    }
    if (method == 'POST') {
      posts.add(Map.of(body!));
      if (postGate != null) await postGate!.future;
      var item = items
          .where((m) => m['requestId'] == body['requestId'])
          .firstOrNull;
      item ??= msg(
        items.isEmpty ? 1 : int.parse(items.last['id']) + 1,
        mine: true,
        request: body['requestId'],
        text: body['text'],
      );
      if (!items.any((m) => m['id'] == item!['id'])) items.add(item);
      if (loseResponse) {
        loseResponse = false;
        throw CustomerApiException('Lost response');
      }
      return Map.of(item);
    }
    if (path.startsWith('/conversations?') || path == '/conversations') {
      return {
        'items': [summary],
        'nextCursor': null,
      };
    }
    final query = Uri.parse(path).queryParameters;
    final selected = items
        .where(
          (m) => query.containsKey('after')
              ? int.parse(m['id']) > int.parse(query['after']!)
              : query.containsKey('before')
              ? int.parse(m['id']) < int.parse(query['before']!)
              : true,
        )
        .toList();
    final page = !paginated || selected.length <= 30
        ? selected
        : query.containsKey('after')
        ? selected.take(30).toList()
        : selected.skip(selected.length - 30).toList();
    return {
      'items': page,
      'hasMore': paginated && selected.length > 30,
      'conversation': summary,
      'redactedIds': query.containsKey('changesAfter')
          ? redactions
          : <String>[],
      'changeCursor': redactions.isEmpty ? '0' : '1',
    };
  }
}

class ReportApi extends CustomerApi {
  ReportApi() : super('test', 'customer');
  final posts = <ChatJson>[];
  @override
  Future<ChatJson> request(String method, String path, [ChatJson? body]) async {
    posts.add(Map.of(body!));
    if (posts.length == 1) throw CustomerApiException('Lost response');
    return {
      'id': '1',
      'messageId': body['messageId'],
      'status': 'open',
      'revision': 0,
      'reason': body['reason'],
      'created': '2026-10-29T00:00:00Z',
      'reviewReason': null,
    };
  }
}

void main() {
  test(
    'older pages and a burst of new messages retain every ID in order',
    () async {
      final api = ChatApi()
        ..paginated = true
        ..items.addAll(List.generate(65, (i) => msg(i + 1)));
      final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
      addTearDown(chat.dispose);
      await chat.initialize();
      expect(
        chat.messages.map((m) => m['id']),
        List.generate(30, (i) => '${i + 36}'),
      );
      expect(chat.readCursor, '65');
      await chat.refresh(older: true);
      expect(chat.more, true);
      expect(chat.readCursor, '65');
      api.items.addAll(List.generate(35, (i) => msg(i + 66)));
      await chat.refresh();
      expect(chat.readCursor, '95');
      // A local outgoing message must not skip the remaining incoming delta.
      expect(await chat.send('reply after burst', null), true);
      expect(chat.readCursor, '95');
      await chat.refresh(older: true);
      expect(chat.more, false);
      expect(chat.readCursor, '95');
      await chat.refresh();
      expect(
        chat.messages.map((m) => m['id']),
        List.generate(101, (i) => '${i + 1}'),
      );
      expect(chat.readCursor, '101');
      expect(api.reads, isEmpty);
    },
  );

  test(
    'delivery acknowledges only fetched incoming messages, retries without reading, ignores local sends',
    () async {
      final api = ChatApi()
        ..items.addAll([msg(1), msg(2, mine: true)])
        ..failDelivery = true;
      final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
      addTearDown(chat.dispose);
      await chat.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(chat.ready, isTrue);
      expect(chat.error, isNull);
      expect(api.deliveries, ['1']);
      expect(api.reads, isEmpty);
      api.failDelivery = false;
      await chat.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(api.deliveries, ['1', '1']);
      expect(api.reads, isEmpty);
      await chat.send('own message', null);
      await chat.refresh();
      expect(api.deliveries, ['1', '1']);
      api.items.add(msg(4));
      await chat.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(api.deliveries.last, '4');
      expect(api.reads, isEmpty);
      await chat.refresh();
      expect(api.deliveries.length, 3);
    },
  );
  testWidgets('outgoing bubble distinguishes delivered from read', (t) async {
    final api = ChatApi()
      ..items.add(msg(1, mine: true))
      ..peerDelivered = '1';
    final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
    await t.pumpWidget(MaterialApp(home: ConversationPage(controller: chat)));
    await t.pumpAndSettle();
    expect(find.textContaining('Yetkazildi'), findsOneWidget);
    expect(find.textContaining('O‘qilgan'), findsNothing);
    api.peerRead = '1';
    await chat.refresh();
    await t.pumpAndSettle();
    expect(find.textContaining('O‘qilgan'), findsOneWidget);
    expect(find.textContaining('Yetkazildi'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  test(
    'moderation delta removes loaded content without advancing message cursor',
    () async {
      final api = ChatApi()..items.add(msg(1, text: 'private old text'));
      final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
      await chat.initialize();
      api.redactions.add('1');
      await chat.refresh();
      expect(chat.messages.single['hidden'], true);
      expect(chat.messages.single['text'], '');
      expect(chat.messages.single['hasImage'], false);
      expect(chat.readCursor, '1');
      // A response captured before moderation cannot resurrect cached content.
      chat.merge({
        'conversation': api.summary,
        'items': [msg(1, text: 'stale text')],
        'redactedIds': <String>[],
        'changeCursor': '1',
        'hasMore': false,
      });
      expect(chat.messages.single['text'], '');
      await chat.refresh();
      expect(api.paths.last, contains('changesAfter=1'));
      chat.dispose();
    },
  );
  test(
    'block updates composer capability and explicit discard clears only outbox',
    () async {
      final api = ChatApi()..loseResponse = true;
      final storage = ChatDraft();
      final chat = ConversationController(api, 'a' * 32, storage: storage);
      await chat.initialize();
      await chat.send('already accepted', null);
      await chat.setBlocked(true);
      expect(chat.conversation!['canSend'], false);
      expect(chat.conversation!['blockedByMe'], true);
      await chat.discardPending();
      expect(storage.value, isNull);
      expect(chat.pending, isNull);
      expect(api.items.length, 1);
      await chat.setBlocked(false);
      expect(chat.conversation!['canSend'], true);
      chat.dispose();
    },
  );
  testWidgets(
    'report dialog retries the same evidence and request after lost response',
    (tester) async {
      final api = ReportApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ChatReportDialog(
                    api: api,
                    conversationId: 'a' * 32,
                    messageId: '1',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chatReportReason')),
        'TEST spam',
      );
      await tester.tap(find.byKey(const ValueKey('chatReportSubmit')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chatReportReason')))
            .enabled,
        false,
      );
      await tester.tap(find.byKey(const ValueKey('chatReportSubmit')));
      await tester.pumpAndSettle();
      expect(api.posts.length, 2);
      expect(api.posts[0], api.posts[1]);
      expect(find.byType(ChatReportDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'lost response survives restart and reuses exact persisted request',
    () async {
      final api = ChatApi()..loseResponse = true;
      final storage = ChatDraft();
      final first = ConversationController(api, 'a' * 32, storage: storage);
      await first.initialize();
      expect(await first.send('original', null), false);
      expect(api.items.length, 1);
      final request = storage.value!['requestId'];
      first.dispose();
      final restored = ConversationController(api, 'a' * 32, storage: storage);
      await restored.initialize();
      expect(restored.pending!['text'], 'original');
      expect(await restored.send('accidental replacement', null), true);
      expect(api.posts.map((p) => p['requestId']), [request, request]);
      expect(api.posts.map((p) => p['text']), ['original', 'original']);
      expect(api.items.length, 1);
      expect(restored.messages.length, 1);
      expect(storage.value, isNull);
      restored.dispose();
    },
  );
  test(
    'failed draft write prevents POST and cleanup failure keeps retry safe',
    () async {
      final api = ChatApi();
      final storage = ChatDraft()..failWrite = true;
      final chat = ConversationController(api, 'a' * 32, storage: storage);
      await chat.initialize();
      expect(await chat.send('hello', null), false);
      expect(api.posts, isEmpty);
      storage
        ..failWrite = false
        ..failClear = true;
      expect(await chat.send('ignored', null), false);
      expect(api.items.length, 1);
      storage.failClear = false;
      expect(await chat.send('ignored', null), true);
      expect(api.items.length, 1);
      chat.dispose();
    },
  );
  test(
    'local send never advances delta past unseen incoming message',
    () async {
      final api = ChatApi()..items.add(msg(8));
      final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
      await chat.initialize();
      api.items.add(msg(9, text: 'arrived during send'));
      expect(await chat.send('reply', null), true);
      expect(chat.readCursor, '8');
      await chat.refresh();
      expect(
        api.paths,
        contains(
          'GET /conversations/${'a' * 32}/messages?after=8&changesAfter=0',
        ),
      );
      expect(chat.messages.map((m) => m['id']), ['8', '9', '10']);
      expect(chat.readCursor, '10');
      chat.dispose();
    },
  );
  test('double tap sends once and expired session cannot send', () async {
    final api = ChatApi()..postGate = Completer<void>();
    final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
    await chat.initialize();
    final first = chat.send('hello', null);
    await Future<void>.delayed(Duration.zero);
    expect(await chat.send('hello', null), false);
    api.postGate!.complete();
    expect(await first, true);
    expect(api.posts.length, 1);
    CustomerApi.sessionVersion++;
    expect(await chat.send('new', null), false);
    chat.dispose();
  });
  testWidgets(
    'background and covered route do not poll; resume fetches delta',
    (tester) async {
      final api = ChatApi()..items.add(msg(1));
      final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
      await tester.pumpWidget(
        MaterialApp(home: ConversationPage(controller: chat)),
      );
      await tester.pumpAndSettle();
      expect(find.text('TEST sitter'), findsWidgets);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      final count = api.paths.length;
      await tester.pump(const Duration(seconds: 11));
      expect(api.paths.length, count);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(
        api.paths,
        contains(
          'GET /conversations/${'a' * 32}/messages?after=1&changesAfter=0',
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final covered = api.paths.length;
      await tester.pump(const Duration(seconds: 11));
      expect(api.paths.length, covered);
      await tester.pumpWidget(const SizedBox());
      chat.dispose();
    },
  );
  testWidgets('pending outbox locks composer and offers exact retry', (
    tester,
  ) async {
    final api = ChatApi()..loseResponse = true;
    final chat = ConversationController(api, 'a' * 32, storage: ChatDraft());
    await tester.pumpWidget(
      MaterialApp(home: ConversationPage(controller: chat)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('conversationText')),
      'TEST message',
    );
    await tester.tap(find.byKey(const ValueKey('conversationSend')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('conversationText')))
          .enabled,
      false,
    );
    await tester.tap(find.byKey(const ValueKey('conversationSend')));
    await tester.pumpAndSettle();
    expect(api.items.length, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('conversationText')))
          .controller!
          .text,
      '',
    );
    await tester.pumpWidget(const SizedBox());
    chat.dispose();
  });
  testWidgets('both roles use authenticated inbox and unread count', (
    tester,
  ) async {
    final api = ChatApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationInbox(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TEST sitter'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(api.paths, contains('GET /conversations'));
    await tester.pumpWidget(const SizedBox());
  });
}
