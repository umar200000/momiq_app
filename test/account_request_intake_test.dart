import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'conversation_test.dart' show ChatDraft;
import 'support_test.dart' show SupportApi;

class AccountRequestApi extends SupportApi {
  bool wrong = true;
  @override
  Future<SupportJson> request(
    String method,
    String path, [
    SupportJson? body,
  ]) async {
    final result = await super.request(method, path, body);
    result['ticket']['topic'] = wrong ? 'general' : 'account_deletion';
    return result;
  }
}

void main() {
  for (final language in {
    'uz': ['Hisobni o‘chirish so‘rovi', 'qolgan pul qaytarilmaydi'],
    'en': ['Request account deletion', 'non-refundable'],
    'ru': ['Запрос на удаление аккаунта', 'не возвращается'],
  }.entries) {
    testWidgets('read and confirm deletion at large text in ${language.key}', (
      t,
    ) async {
      final previous = AppLanguage.current.value;
      AppLanguage.current.value = language.key;
      addTearDown(() => AppLanguage.current.value = previous);
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = AccountRequestApi();
      final controller = SupportController(api, null, storage: ChatDraft());
      addTearDown(controller.dispose);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SupportThreadPage(api: api, controller: controller),
        ),
      );
      await t.pumpAndSettle();
      final select = find.byType(DropdownButtonFormField<String>);
      await t.ensureVisible(select);
      await t.tap(select);
      await t.pumpAndSettle();
      final topic = find.text(language.value[0]).last;
      await t.ensureVisible(topic);
      await t.tap(topic);
      await t.pumpAndSettle();
      final disclosure = find.textContaining(language.value[1]);
      await t.ensureVisible(disclosure);
      await t.pumpAndSettle();
      expect(t.getSemantics(disclosure).label, contains(language.value[1]));
      final confirm = find.byKey(const ValueKey('confirmAccountRequest'));
      await t.scrollUntilVisible(
        confirm,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(confirm);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(confirm).value, true);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'deletion intake requires an explicit confirmation and restores the same request on retry',
    (t) async {
      final api = AccountRequestApi(), store = ChatDraft();
      final c = SupportController(api, null, storage: store);
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: SupportThreadPage(api: api, controller: c),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Hisobni o‘chirish so‘rovi').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('supportMessage')),
        'TEST account request',
      );
      final button = find.byKey(const ValueKey('sendSupport'));
      await t.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.widget<FilledButton>(button).onPressed, isNull);
      final confirm = find.byKey(const ValueKey('confirmAccountRequest'));
      await t.ensureVisible(confirm);
      await t.pumpAndSettle();
      expect(
        find.textContaining('enaga balansida qolgan pul qaytarilmaydi'),
        findsOneWidget,
      );
      await t.tap(confirm);
      await t.pumpAndSettle();
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pumpAndSettle();
      expect(api.posts.single['confirmAccountRequest'], true);
      expect(c.pending, isNotNull);
      expect(store.value, c.pending);
      final original = Map.of(c.pending!);
      api.wrong = false;
      expect(await c.send('different', null), true);
      expect(api.posts, [original, original]);
      expect(store.value, isNull);
    },
  );
}
