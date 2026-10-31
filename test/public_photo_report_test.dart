import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'conversation_test.dart' show ChatDraft;
import 'support_test.dart' show SupportApi;

class ReportApi extends SupportApi {
  bool wrong = true;
  @override
  Future<SupportJson> request(
    String method,
    String path, [
    SupportJson? body,
  ]) async {
    final response = await super.request(method, path, body);
    final target = body?['target'];
    if (target != null) {
      response['target'] = {
        'kind': 'listing',
        'id': target['id'],
        'purpose': 'report',
        'snapshot': {
          'media': {
            'slot': target['media'],
            'sha256': wrong ? 'b' * 64 : target['sha256'],
          },
        },
      };
    }
    return response;
  }
}

void main() {
  testWidgets(
    'report binds the exact visible portrait bytes to the new support form',
    (t) async {
      final api = ReportApi();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PublicContentReportButton(
              api: api,
              target: {
                'kind': 'listing',
                'id': 'abc:boarding',
                'media': 'portrait',
              },
              publicPhoto: 'YWJj',
            ),
          ),
        ),
      );
      await t.tap(find.byType(TextButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final page = t.widget<SupportThreadPage>(find.byType(SupportThreadPage));
      expect(page.target, {
        'kind': 'listing',
        'id': 'abc:boarding',
        'media': 'portrait',
        'sha256':
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      });
    },
  );
  test(
    'different photographs have independent drafts and a mismatched receipt stays retryable',
    () async {
      final api = ReportApi(), storage = ChatDraft();
      final source = {
        'kind': 'listing',
        'id': 'abc:boarding',
        'media': 'home:0',
        'sha256': 'a' * 64,
      };
      expect(
        {
          for (final target in [
            source,
            {...source, 'media': 'home:1'},
            {...source, 'sha256': 'b' * 64},
          ])
            SupportController.draftScope(api, null, target),
        }.length,
        3,
      );
      final c = SupportController(api, null, storage: storage, target: source);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.send('Reason', null, subject: 'Photo'), false);
      final original = Map.of(c.pending!);
      expect(storage.value, original);
      api.wrong = false;
      expect(await c.send('Changed', null, subject: 'Other'), true);
      expect(api.posts, [original, original]);
      expect(storage.value, isNull);
    },
  );
}
