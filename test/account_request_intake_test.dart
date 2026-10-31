import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
