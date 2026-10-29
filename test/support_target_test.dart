import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'conversation_test.dart' show ChatDraft;
import 'support_test.dart' show SupportApi;

void main() {
  setUp(() => CustomerApi.active = null);
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('report form remains usable with large text in $language', (
      t,
    ) async {
      AppLanguage.current.value = language;
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = SupportApi();
      final target = {'kind': 'listing', 'id': '${'a' * 24}:boarding'};
      final c = SupportController(
        api,
        null,
        storage: ChatDraft(),
        target: target,
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SupportThreadPage(api: api, target: target, controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('sendSupport')),
        240,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        find.text(
          {'uz': 'Yuborish', 'en': 'Send', 'ru': 'Отправить'}[language]!,
        ),
        findsOneWidget,
      );
    });
  }
  test(
    'report retries preserve the original target and body after restart',
    () async {
      final api = SupportApi()..lost = true;
      final storage = ChatDraft();
      final target = {'kind': 'review', 'id': '18'};
      var c = SupportController(api, null, storage: storage, target: target);
      target['id'] = '19'; // The controller takes an immutable copy.
      await c.load();
      expect(await c.send('Original reason', null, subject: 'Report'), false);
      final original = Map.of(storage.value!);
      expect(original['target'], {'kind': 'review', 'id': '18'});
      c.dispose();
      c = SupportController(
        api,
        null,
        storage: storage,
        target: {'kind': 'listing', 'id': 'different:boarding'},
      );
      addTearDown(c.dispose);
      await c.load();
      expect(await c.send('Changed', null, subject: 'Changed'), true);
      expect(api.posts, [original, original]);
      expect(api.keys.length, 1);
    },
  );
  test('report drafts are separated by endpoint, kind and target', () {
    final api = SupportApi();
    final scopes = {
      SupportController.draftScope(api, null, null),
      SupportController.draftScope(api, null, {'kind': 'review', 'id': '1'}),
      SupportController.draftScope(api, null, {'kind': 'review', 'id': '2'}),
      SupportController.draftScope(api, null, {
        'kind': 'listing',
        'id': 'abc:boarding',
      }),
      SupportController.draftScope(api, null, {
        'kind': 'listing',
        'id': 'abc:personal',
      }),
      SupportController.draftScope(api, 'a' * 32, null),
    };
    expect(scopes.length, 6);
    expect(
      SupportController.draftScope(api, 'a' * 32, {
        'kind': 'review',
        'id': '1',
      }),
      SupportController.draftScope(api, 'a' * 32, null),
    );
  });
  testWidgets(
    'report form shows target, requires reason and sends structured identity',
    (t) async {
      final api = SupportApi();
      final target = {'kind': 'listing', 'id': 'abc:boarding'};
      final c = SupportController(
        api,
        null,
        storage: ChatDraft(),
        target: target,
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: SupportThreadPage(api: api, target: target, controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('#abc:boarding'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('sendSupport')));
      await t.tap(find.byKey(const ValueKey('sendSupport')));
      expect(api.posts, isEmpty);
      await t.enterText(
        find.byKey(const ValueKey('supportMessage')),
        'TEST misleading description',
      );
      api.lost =
          true; // Keep the retry form visible without opening a second controller.
      await t.ensureVisible(find.byKey(const ValueKey('sendSupport')));
      await t.tap(find.byKey(const ValueKey('sendSupport')));
      await t.pumpAndSettle();
      expect(api.posts.single['target'], target);
      expect(api.posts.single['topic'], 'safety');
      expect(api.posts.single['text'], 'TEST misleading description');
      expect(find.text('Ayni xabarni qayta yuborish'), findsOneWidget);
    },
  );
  testWidgets('stale report button cannot open a form under another session', (
    t,
  ) async {
    final api = SupportApi();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicContentReportButton(
            api: api,
            target: const {'kind': 'review', 'id': '8'},
          ),
        ),
      ),
    );
    CustomerApi.sessionVersion++;
    await t.tap(find.byType(TextButton));
    await t.pumpAndSettle();
    expect(find.byType(SupportThreadPage), findsNothing);
    expect(api.posts, isEmpty);
  });
}
