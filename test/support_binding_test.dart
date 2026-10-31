import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'conversation_test.dart' show ChatDraft;

class BindingApi extends CustomerApi {
  BindingApi(this.label) : super('test', label);
  final String label;
  Completer<void>? getGate, postGate;
  bool fail = false;
  final calls = <String>[];
  @override
  Future<SupportJson> request(
    String method,
    String path, [
    SupportJson? body,
  ]) async {
    calls.add('$method $path');
    await (method == 'GET' ? getGate?.future : postGate?.future);
    if (fail) throw StateError('TEST unavailable');
    final ticket = {
      'id': path.startsWith('/support/') ? path.split('/').last : 'a' * 32,
      'subject': '$label private subject',
      'status': 'open',
      'updated': '2026-10-29',
      'revision': 0,
    };
    return method == 'GET' && path == '/support'
        ? {
            'items': [ticket],
            'legacyItems': [],
            'nextCursor': null,
          }
        : {
            'ticket': ticket,
            'items': [
              {
                'id': '1',
                'text': '$label private reply',
                'authorRole': 'owner',
                'created': '2026-10-29',
              },
            ],
            'nextCursor': null,
          };
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'list rebind isolates late ${fail ? 'failure' : 'success'} and busy state',
      (t) async {
        final old = BindingApi('old')
          ..getGate = Completer<void>()
          ..fail = fail;
        final next = BindingApi('next')..getGate = Completer<void>();
        Future<void> show(BindingApi api) => t.pumpWidget(
          MaterialApp(
            home: SupportPage(key: const ValueKey('same'), api: api),
          ),
        );
        await show(old);
        await show(next);
        old.getGate!.complete();
        await t.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text(supportError()), findsNothing);
        expect(find.text('old private subject'), findsNothing);
        next.getGate!.complete();
        await t.pumpAndSettle();
        expect(find.text('next private subject'), findsOneWidget);
        expect(next.calls, ['GET /support']);
      },
    );
  }
  testWidgets(
    'new thread binding clears editor and late create cannot navigate',
    (t) async {
      final old = BindingApi('old')..postGate = Completer<void>();
      final next = BindingApi('next');
      final oldC = SupportController(old, null, storage: ChatDraft());
      final nextC = SupportController(next, null, storage: ChatDraft());
      addTearDown(oldC.dispose);
      addTearDown(nextC.dispose);
      Future<void> show(BindingApi api, SupportController c) => t.pumpWidget(
        MaterialApp(
          home: SupportThreadPage(
            key: const ValueKey('same'),
            api: api,
            controller: c,
          ),
        ),
      );
      await show(old, oldC);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('supportSubject')),
        'old draft',
      );
      await t.enterText(
        find.byKey(const ValueKey('supportMessage')),
        'old message',
      );
      final button = find.byKey(const ValueKey('sendSupport'));
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pump();
      expect(old.calls, ['POST /support']);
      await show(next, nextC);
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('supportSubject')))
            .controller!
            .text,
        isEmpty,
      );
      old.postGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('old private subject'), findsNothing);
      expect(find.byKey(const ValueKey('supportSubject')), findsOneWidget);
      expect(next.calls, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('same API different ticket replaces private history and editor', (
    t,
  ) async {
    final api = BindingApi('owner');
    final first = SupportController(api, 'a' * 32, storage: ChatDraft());
    final second = SupportController(api, 'b' * 32, storage: ChatDraft());
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Future<void> show(String id, SupportController c) => t.pumpWidget(
      MaterialApp(
        home: SupportThreadPage(api: api, id: id, controller: c),
      ),
    );
    await show('a' * 32, first);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('supportMessage')),
      'unsent first message',
    );
    api.getGate = Completer<void>();
    await show('b' * 32, second);
    await t.pump();
    expect(find.text('owner private reply'), findsNothing);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('supportMessage')))
          .controller!
          .text,
      isEmpty,
    );
    api.getGate!.complete();
    await t.pumpAndSettle();
    expect(api.calls, ['GET /support/${'a' * 32}', 'GET /support/${'b' * 32}']);
  });
  testWidgets(
    'mismatched external controller cannot load or expose private data',
    (t) async {
      final old = BindingApi('old'), next = BindingApi('next');
      final c = SupportController(old, 'a' * 32, storage: ChatDraft());
      addTearDown(c.dispose);
      await c.load();
      await t.pumpWidget(
        MaterialApp(
          home: SupportThreadPage(api: next, id: 'b' * 32, controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('old private reply'), findsNothing);
      expect(find.byKey(const ValueKey('sendSupport')), findsNothing);
      expect(old.calls, ['GET /support/${'a' * 32}']);
      expect(next.calls, isEmpty);
    },
  );
  for (final thread in [false, true]) {
    testWidgets(
      '${thread ? 'thread' : 'list'} hides private history after session invalidation and rebuild',
      (t) async {
        final api = BindingApi('owner');
        final c = SupportController(api, 'a' * 32, storage: ChatDraft());
        addTearDown(c.dispose);
        Future<void> show() => t.pumpWidget(
          MaterialApp(
            home: thread
                ? SupportThreadPage(api: api, id: 'a' * 32, controller: c)
                : SupportPage(api: api),
          ),
        );
        await show();
        await t.pumpAndSettle();
        expect(find.text('owner private subject'), findsOneWidget);
        CustomerApi.sessionVersion++;
        await show();
        await t.pumpAndSettle();
        expect(find.text('owner private subject'), findsNothing);
        expect(find.byKey(const ValueKey('sendSupport')), findsNothing);
        expect(find.byKey(const ValueKey('newSupport')), findsNothing);
        expect(
          find.text('Sessiya o‘zgardi. Yordam bo‘limini qayta oching.'),
          findsOneWidget,
        );
        expect(api.calls.length, 1);
      },
    );
  }
}
