import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/chat/data/conversation_controller.dart';
import 'package:momiq_app/features/chat/presentation/conversation_page.dart';
import 'package:momiq_app/features/chat/presentation/chat_reports.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'conversation_test.dart' show ChatApi, ChatDraft, msg;
import 'support_binding_test.dart' show BindingApi;
import 'package:momiq_app/features/support/support_controller.dart';

class SourceApi extends ChatApi {
  SourceApi(this.label);
  final String label;
  Completer<void>? gate;
  String? delayedMethod;
  bool fail = false;
  final calls = <String>[];
  @override
  ChatJson get summary => {...super.summary, 'peerName': label};
  @override
  Future<ChatJson> request(String method, String path, [ChatJson? body]) async {
    calls.add('$method $path');
    final wait = method == delayedMethod ? gate : null;
    if (wait != null) await wait.future;
    if (fail) throw StateError('TEST response lost');
    if (method == 'POST' && path == '/conversations') return summary;
    if (path.contains('/reports')) {
      final report = {
        'id': '1',
        'messageId': body?['messageId'] ?? '1',
        'reason': body?['reason'] ?? '$label report',
        'status': 'open',
        'revision': 0,
        'created': '2026-10-29T00:00:00Z',
      };
      return method == 'GET'
          ? {
              'items': [report],
              'nextCursor': null,
            }
          : report;
    }
    return super.request(method, path, body);
  }
}

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final fail in [false, true]) {
    testWidgets(
      'inbox rebind ignores obsolete ${fail ? 'error' : 'success'} and keeps new loading',
      (t) async {
        final old = SourceApi('old')
          ..delayedMethod = 'GET'
          ..gate = Completer<void>()
          ..fail = fail;
        final next = SourceApi('new')
          ..delayedMethod = 'GET'
          ..gate = Completer<void>();
        Future<void> show(SourceApi api) => t.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConversationInbox(api: api)),
          ),
        );
        await show(old);
        await show(next);
        old.gate!.complete();
        await t.pump();
        expect(find.text('old'), findsNothing);
        expect(find.text(chatFailure()), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        next.gate!.complete();
        await t.pumpAndSettle();
        expect(find.text('new'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'late conversation create cannot initialize or display replaced source',
    (t) async {
      final old = SourceApi('old')
        ..delayedMethod = 'POST'
        ..gate = Completer<void>();
      await t.pumpWidget(
        MaterialApp(
          home: ConversationPage(api: old, listingId: 'test:boarding'),
        ),
      );
      await t.pump();
      final next = SourceApi('new');
      final nextC = ConversationController(
        next,
        'b' * 32,
        storage: ChatDraft(),
      );
      addTearDown(nextC.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ConversationPage(
            api: next,
            conversationId: 'b' * 32,
            controller: nextC,
          ),
        ),
      );
      await t.pumpAndSettle();
      old.gate!.complete();
      await t.pumpAndSettle();
      expect(old.calls, ['POST /conversations']);
      expect(find.text('new'), findsWidgets);
      expect(find.text('old'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'owned report dialog closes on source replacement without sending',
    (t) async {
      final old = SourceApi('old')..items.add(msg(1));
      final oldC = ConversationController(old, 'a' * 32, storage: ChatDraft());
      final next = SourceApi('new'),
          nextC = ConversationController(
            SourceApi('new'),
            'b' * 32,
            storage: ChatDraft(),
          );
      addTearDown(oldC.dispose);
      addTearDown(nextC.dispose);
      final page = ValueNotifier<Widget>(
        ConversationPage(api: old, controller: oldC),
      );
      addTearDown(page.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<Widget>(
            valueListenable: page,
            builder: (_, child, unused) => child,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Shikoyat'));
      await t.pumpAndSettle();
      expect(find.byType(ChatReportDialog), findsOneWidget);
      page.value = ConversationPage(api: nextC.api, controller: nextC);
      await t.pumpAndSettle();
      expect(find.byType(ChatReportDialog), findsNothing);
      expect(find.text('new'), findsWidgets);
      expect(old.calls.where((p) => p.contains('/reports')), isEmpty);
      expect(next.calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('late send does not clear new conversation editor', (t) async {
    final old = SourceApi('old')..postGate = Completer<void>();
    final first = ConversationController(old, 'a' * 32, storage: ChatDraft());
    final next = SourceApi('new');
    final second = ConversationController(next, 'b' * 32, storage: ChatDraft());
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Future<void> show(ConversationController c) => t.pumpWidget(
      MaterialApp(
        home: ConversationPage(api: c.api, controller: c),
      ),
    );
    await show(first);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('conversationText')),
      'old text',
    );
    await t.tap(find.byKey(const ValueKey('conversationSend')));
    await t.pump();
    await show(second);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('conversationText')),
      'new text',
    );
    old.postGate!.complete();
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('conversationText')))
          .controller!
          .text,
      'new text',
    );
    expect(next.posts, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  for (final support in [false, true]) {
    testWidgets(
      '${support ? 'support' : 'chat'} target-only change cannot revive invalidated session',
      (t) async {
        final api = support ? BindingApi('old') : SourceApi('old');
        final supportControllers = {
          for (final id in ['a' * 32, 'b' * 32])
            id: SupportController(api, id, storage: ChatDraft()),
        };
        for (final c in supportControllers.values) {
          addTearDown(c.dispose);
        }
        Future<void> show(String id) => t.pumpWidget(
          MaterialApp(
            home: support
                ? SupportThreadPage(
                    api: api,
                    id: id,
                    controller: supportControllers[id],
                  )
                : ChatReportsPage(api: api, conversationId: id),
          ),
        );
        await show('a' * 32);
        await t.pumpAndSettle();
        CustomerApi.sessionVersion++;
        await show('b' * 32);
        await t.pumpAndSettle();
        expect(
          find.textContaining(
            support ? 'Sessiya o‘zgardi. Yordam' : 'Sessiya o‘zgardi. Suhbat',
          ),
          findsOneWidget,
        );
        if (api is SourceApi) {
          expect(api.calls.every((p) => !p.contains('b' * 32)), true);
        }
        if (api is BindingApi) {
          expect(api.calls.every((p) => !p.contains('b' * 32)), true);
        }
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'late report success removes only its own route, never a newer page',
    (t) async {
      final api = SourceApi('old')
        ..delayedMethod = 'POST'
        ..gate = Completer<void>();
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ChatReportDialog(
                    api: api,
                    conversationId: 'a' * 32,
                    messageId: '1',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('chatReportReason')),
        'TEST reason',
      );
      await t.tap(find.byKey(const ValueKey('chatReportSubmit')));
      await t.pump();
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('new page')),
          ),
        ),
      );
      await t.pumpAndSettle();
      api.gate!.complete();
      await t.pumpAndSettle();
      expect(find.text('new page'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.byType(ChatReportDialog), findsNothing);
    },
  );
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets(
      'report dialog supports 320px 2x text and labelled controls in $language',
      (t) async {
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
            home: Scaffold(
              body: ChatReportDialog(
                api: SourceApi('test'),
                conversationId: 'a' * 32,
                messageId: '1',
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('chatReportReason')));
        expect(
          t
              .widget<TextField>(find.byKey(const ValueKey('chatReportReason')))
              .decoration!
              .labelText,
          isNotEmpty,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
