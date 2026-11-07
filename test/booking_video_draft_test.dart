import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'package:momiq_app/features/care/presentation/booking_videos_page.dart';
import 'booking_video_test.dart' show ExplanationApi, FakeUpload;
import 'conversation_test.dart' show ChatDraft;

VideoJson draft({bool explanation = false}) => {
  'petId': 'cat',
  'slot': 'morning',
  'day': '2026-10-28',
  'requestId': 'test_video_request_123',
  'createdAt': '2026-10-28T04:00:00Z',
  if (explanation) ...{
    'reason': 'Original reason',
    'emergency': false,
  } else
    'bytes': base64Encode(Uint8List(20)),
};

class ReadFailure extends ChatDraft {
  Object? failure;
  @override
  Future<VideoJson?> read() async {
    if (failure != null) throw failure!;
    return super.read();
  }

  @override
  Future<void> clear() async {
    await super.clear();
    failure = null;
  }
}

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final explanation in [false, true]) {
    for (final change in <VideoJson>[
      {'petId': []},
      {'petId': ''},
      {'slot': 'night'},
      {'day': '2026-02-30'},
      {'requestId': 'short'},
      {'createdAt': '2026-10-28T04:00:00'},
      {'extra': true},
      if (explanation) ...[
        {'reason': []},
        {'reason': ' '},
        {'reason': 'x' * 1001},
        {'emergency': 'true'},
      ] else ...[
        {'bytes': []},
        {'bytes': 'bad!'},
        {'bytes': base64Encode(Uint8List(11))},
        {'kind': 'selection'},
      ],
    ]) {
      test(
        'invalid ${explanation ? 'explanation' : 'video'} $change stays local',
        () async {
          final bad = {...draft(explanation: explanation), ...change};
          final broken = ChatDraft()..value = bad;
          final other = ChatDraft()..value = draft(explanation: !explanation);
          final api = ExplanationApi(), upload = FakeUpload();
          final c = BookingVideoController(
            api,
            'booking',
            storage: explanation ? other : broken,
            explanationStorage: explanation ? broken : other,
            transport: () => upload,
          );
          addTearDown(c.dispose);
          await c.load();
          expect(c.error, isA<FormatException>());
          expect((c.error as FormatException).source, isNull);
          expect(c.draftsReady, false);
          expect(c.invalidVideoDraft, !explanation);
          expect(c.invalidExplanationDraft, explanation);
          expect(explanation ? c.explanationDraft : c.pending, isNull);
          await c.send();
          await c.sendExplanation();
          await c.explain('cat', 'evening', 'Replacement', true);
          await c.select('cat', 'morning', Uint8List(20));
          expect(upload.paths, isEmpty);
          expect(api.sent, isEmpty);
          expect(broken.value, bad);
          expect(other.value, draft(explanation: !explanation));
          if (explanation) {
            await c.discardExplanation();
          } else {
            await c.discard();
          }
          expect(c.error, isNull);
          expect(c.draftsReady, true);
          expect(broken.value, isNull);
          expect(explanation ? c.pending : c.explanationDraft, other.value);
        },
      );
    }
    test(
      'cipher read failure and failed clear preserve companion ($explanation)',
      () async {
        final broken = ReadFailure()
          ..failure = const FormatException('Cipher authentication failed')
          ..failClear = true;
        final other = ChatDraft()..value = draft(explanation: !explanation);
        final c = BookingVideoController(
          ExplanationApi(),
          'booking',
          storage: explanation ? other : broken,
          explanationStorage: explanation ? broken : other,
        );
        addTearDown(c.dispose);
        await c.load();
        expect(c.invalidVideoDraft, !explanation);
        expect(c.invalidExplanationDraft, explanation);
        if (explanation) {
          await c.discardExplanation();
        } else {
          await c.discard();
        }
        expect(c.error, isA<StateError>());
        expect(c.draftsReady, false);
        expect(other.value, draft(explanation: !explanation));
        broken.failClear = false;
        if (explanation) {
          await c.discardExplanation();
        } else {
          await c.discard();
        }
        expect(c.error, isNull);
        expect(c.draftsReady, true);
        expect(explanation ? c.pending : c.explanationDraft, other.value);
      },
    );
  }
  test(
    'clearing video after unreadable explanation reloads rather than skipping it',
    () async {
      final video = ChatDraft()..value = draft();
      final notes = ReadFailure()
        ..value = draft(explanation: true)
        ..failure = StateError('Storage temporarily unavailable');
      final api = ExplanationApi(), upload = FakeUpload();
      final c = BookingVideoController(
        api,
        'booking',
        storage: video,
        explanationStorage: notes,
        transport: () => upload,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.invalidExplanationDraft, false);
      await c.send();
      expect(upload.paths, isEmpty);
      notes.failure = null;
      await c.discard();
      expect(c.explanationDraft, draft(explanation: true));
      expect(c.draftsReady, true);
      expect(api.sent, isEmpty);
    },
  );
  test('two corrupt drafts need two independent explicit clears', () async {
    final video = ChatDraft()..value = {'bad': true};
    final notes = ChatDraft()..value = {'bad': true};
    final c = BookingVideoController(
      ExplanationApi(),
      'booking',
      storage: video,
      explanationStorage: notes,
    );
    addTearDown(c.dispose);
    await c.load();
    await c.discard();
    expect(c.invalidVideoDraft, false);
    expect(c.invalidExplanationDraft, true);
    expect(c.draftsReady, false);
    expect(notes.value, {'bad': true});
    await c.discardExplanation();
    expect(c.draftsReady, true);
    expect(c.error, isNull);
  });
  for (final entry in {
    'uz': [
      'Video qoralamasini tozalash',
      'Sabab qoralamasini tozalash',
      'Tozalash',
    ],
    'en': ['Clear video draft', 'Clear explanation draft', 'Clear'],
    'ru': ['Очистить черновик видео', 'Очистить черновик причины', 'Очистить'],
  }.entries) {
    testWidgets('both recovery actions confirm on small ${entry.key} screen', (
      t,
    ) async {
      AppLanguage.current.value = entry.key;
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final video = ChatDraft()..value = {'bad': true};
      final notes = ChatDraft()..value = {'bad': true};
      final api = ExplanationApi();
      final c = BookingVideoController(
        api,
        'booking',
        storage: video,
        explanationStorage: notes,
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
      for (var i = 0; i < 2; i++) {
        final action = find.text(entry.value[i]);
        await t.scrollUntilVisible(
          action,
          180,
          maxScrolls: 40,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(t.element(action), alignment: 1);
        await t.pumpAndSettle();
        await t.tap(action);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(i == 0 ? video.value : notes.value, isNotNull);
        final confirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(entry.value[2]),
        );
        await t.ensureVisible(confirm);
        await t.tap(confirm);
        await t.pumpAndSettle();
        expect(i == 0 ? video.value : notes.value, isNull);
        if (i == 0) expect(notes.value, isNotNull);
        expect(t.takeException(), isNull);
      }
      expect(c.draftsReady, true);
      expect(api.sent, isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  }
}
