import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'package:momiq_app/features/care/presentation/booking_videos_page.dart';
import 'booking_video_test.dart' show ExplanationApi, FakeUpload;
import 'booking_video_draft_test.dart' show draft;
import 'conversation_test.dart' show ChatDraft;

class RefreshVideoApi extends ExplanationApi {
  RefreshVideoApi() {
    loseResponse = false;
  }
  String? failure;
  final days = <String?>[];
  @override
  Future<VideoJson> request(
    String method,
    String path, [
    VideoJson? body,
  ]) async {
    if (method == 'GET') {
      days.add(Uri.parse(path).queryParameters['day']);
      if (failure == 'offline') throw StateError('TEST offline');
    }
    final result = await super.request(method, path, body);
    if (method == 'GET' && failure == 'malformed') {
      result['bookingId'] = 'other';
    }
    return result;
  }
}

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final explanation in [false, true]) {
    for (final failure in ['offline', 'malformed']) {
      test(
        'confirmed ${explanation ? 'reason' : 'video'} survives $failure refresh without new writes',
        () async {
          final video = ChatDraft()..value = {...draft(), 'day': '2026-10-27'};
          final notes = ChatDraft()
            ..value = {...draft(explanation: true), 'day': '2026-10-27'};
          final api = RefreshVideoApi(), upload = FakeUpload();
          final c = BookingVideoController(
            api,
            'booking',
            storage: video,
            explanationStorage: notes,
            transport: () => upload,
          );
          addTearDown(c.dispose);
          await c.load();
          final originalData = c.data;
          final companion = Map.of((explanation ? video : notes).value!);
          api.failure = failure;
          if (explanation) {
            await c.sendExplanation();
          } else {
            await c.send();
          }
          expect(c.savedNeedsRefresh, true);
          expect(c.draftsReady, false);
          expect(c.error, isNotNull);
          expect(c.data, same(originalData));
          expect((explanation ? notes : video).value, isNull);
          expect(explanation ? c.explanationDraft : c.pending, isNull);
          expect(api.days.last, '2026-10-27');
          expect(c.canSelect('cat', 'morning'), false);
          expect(await c.beginSelection('cat', 'morning'), isNull);
          await c.select('cat', 'morning', Uint8List(20));
          await c.explain('cat', 'evening', 'Replacement', true);
          await c.send();
          await c.sendExplanation();
          expect(upload.paths.length, explanation ? 0 : 1);
          expect(api.sent.length, explanation ? 1 : 0);
          expect((explanation ? video : notes).value, companion);
          await c.load(day: '2026-10-28');
          expect(c.savedNeedsRefresh, true);
          expect(api.days.last, '2026-10-27');
          api.failure = null;
          await c.load(day: '2026-10-28');
          expect(c.savedNeedsRefresh, false);
          expect(c.draftsReady, true);
          expect(c.error, isNull);
          expect(c.data!['day'], '2026-10-27');
          expect((explanation ? video : notes).value, companion);
          await c.load(day: '2026-10-28');
          expect(c.data!['day'], '2026-10-28');
        },
      );
    }
    test(
      'failed local cleanup keeps ${explanation ? 'reason' : 'video'} exact retry',
      () async {
        final storage = ChatDraft()
          ..value = draft(explanation: explanation)
          ..failClear = true;
        final api = RefreshVideoApi(), upload = FakeUpload();
        final c = BookingVideoController(
          api,
          'booking',
          storage: explanation ? ChatDraft() : storage,
          explanationStorage: explanation ? storage : ChatDraft(),
          transport: () => upload,
        );
        addTearDown(c.dispose);
        await c.load();
        if (explanation) {
          await c.sendExplanation();
        } else {
          await c.send();
        }
        expect(c.savedNeedsRefresh, false);
        expect(c.error, isA<StateError>());
        expect(storage.value, draft(explanation: explanation));
        storage.failClear = false;
        if (explanation) {
          await c.sendExplanation();
        } else {
          await c.send();
        }
        expect(c.savedNeedsRefresh, false);
        expect(c.error, isNull);
        if (explanation) {
          expect(api.sent, [api.sent.first, api.sent.first]);
        } else {
          expect(upload.paths, [upload.paths.first, upload.paths.first]);
        }
      },
    );
  }
  for (final entry in {
    'uz': ['Yuborilgan ma’lumot serverda saqlandi.', 'Yangilash'],
    'en': ['Your submission was saved on the server.', 'Refresh'],
    'ru': ['Отправленные данные сохранены на сервере.', 'Обновить'],
  }.entries) {
    for (final explanation in [false, true]) {
      testWidgets(
        'confirmed ${explanation ? 'reason' : 'video'} shows refresh recovery in ${entry.key}',
        (t) async {
          AppLanguage.current.value = entry.key;
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final storage = ChatDraft()..value = draft(explanation: explanation);
          final api = RefreshVideoApi(), upload = FakeUpload();
          final c = BookingVideoController(
            api,
            'booking',
            storage: explanation ? ChatDraft() : storage,
            explanationStorage: explanation ? storage : ChatDraft(),
            transport: () => upload,
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
              home: BookingVideosPage(
                api: api,
                bookingId: 'booking',
                controller: c,
              ),
            ),
          );
          await t.pumpAndSettle();
          api.failure = 'offline';
          if (explanation) {
            await c.sendExplanation();
          } else {
            await c.send();
          }
          await t.pumpAndSettle();
          expect(c.savedNeedsRefresh, true);
          await t.scrollUntilVisible(
            find.textContaining(entry.value[0]),
            160,
            maxScrolls: 40,
          );
          expect(find.textContaining(entry.value[0]), findsOneWidget);
          expect(find.text('2026-10-28 · Asia/Tashkent'), findsNothing);
          final refresh = find.text(entry.value[1]);
          await t.scrollUntilVisible(refresh, 160, maxScrolls: 40);
          await Scrollable.ensureVisible(t.element(refresh), alignment: 1);
          await t.pumpAndSettle();
          api.failure = null;
          await t.tap(refresh);
          await t.pumpAndSettle();
          expect(c.savedNeedsRefresh, false);
          expect(find.textContaining(entry.value[0]), findsNothing);
          expect(api.sent.length, explanation ? 1 : 0);
          expect(upload.paths.length, explanation ? 0 : 1);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
