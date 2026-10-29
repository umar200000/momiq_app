import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'package:momiq_app/features/care/presentation/booking_videos_page.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'conversation_test.dart' show ChatDraft;

class VideoApi extends CustomerApi {
  VideoApi() : super('TEST', 'sitter');
  bool allowed = true, open = true;
  String today = '2026-10-28';
  Completer<void>? gate;
  List<VideoJson> items = [];
  List<VideoJson> followups = [];
  @override
  Future<VideoJson> request(
    String method,
    String path, [
    VideoJson? body,
  ]) async {
    if (gate != null) await gate!.future;
    return {
      'day': today,
      'canUpload': allowed,
      'serviceAvailable': true,
      'items': items,
      'followups': followups,
      'policy': {
        'today': today,
        'slots': [
          {'slot': 'morning', 'open': open},
          {'slot': 'evening', 'open': false},
        ],
      },
      'pets': [
        {'id': 'cat', 'name': 'TEST cat'},
      ],
    };
  }
}

class FakeUpload extends VideoUpload {
  bool fail = false, cancelled = false;
  Completer<void>? gate;
  final paths = <String>[], contents = <Uint8List>[];
  @override
  void cancel() {
    cancelled = true;
    gate?.complete();
    gate = null;
  }

  @override
  Future<VideoJson> send(
    CustomerApi api,
    String path,
    Uint8List bytes,
    void Function(double) progress,
  ) async {
    paths.add(path);
    contents.add(bytes);
    progress(.5);
    if (gate != null) await gate!.future;
    if (fail || cancelled) throw StateError('TEST response lost');
    final query = Uri.parse(path).queryParameters;
    return {
      'id': 'a' * 32,
      'bookingId': Uri.parse(path).path.split('/')[2],
      'requestId': query['requestId'],
      'durationMs': 10000,
      'bytes': 1000,
      'width': 128,
      'height': 96,
      'created': '2026-10-29T00:00:00Z',
      'petId': query['petId'],
      'day': query['day'],
      'slot': query['slot'],
    };
  }
}

class ExplanationApi extends VideoApi {
  bool loseResponse = true;
  final sent = <VideoJson>[];
  @override
  Future<VideoJson> request(
    String method,
    String path, [
    VideoJson? body,
  ]) async {
    if (method == 'GET') return super.request(method, path, body);
    sent.add(Map.of(body!));
    if (loseResponse) throw StateError('TEST response lost');
    return {
      'ok': true,
      'bookingId': path.split('/')[2],
      ...body,
      'created': '2026-10-29T00:00:00Z',
    };
  }
}

void main() {
  test(
    'explanation response loss survives restart with exact identity and no video draft change',
    () async {
      final api = ExplanationApi(), video = ChatDraft(), notes = ChatDraft();
      var c = BookingVideoController(
        api,
        'booking',
        storage: video,
        explanationStorage: notes,
      );
      await c.load();
      await c.select('cat', 'morning', Uint8List(20));
      final originalVideo = Map.of(video.value!);
      await c.explain('cat', 'evening', 'TEST emergency', true);
      expect(c.explanationDraft, isNotNull);
      expect(c.error, isNotNull);
      c.dispose();
      api.loseResponse = false;
      c = BookingVideoController(
        api,
        'booking',
        storage: video,
        explanationStorage: notes,
      );
      addTearDown(c.dispose);
      await c.load();
      await c.sendExplanation();
      expect(api.sent.length, 2);
      expect(api.sent.first, api.sent.last);
      expect(notes.value, isNull);
      expect(c.explanationDraft, isNull);
      expect(video.value, originalVideo);
    },
  );
  testWidgets(
    'missing video shows sitter explanation and support without treating it as delivered',
    (t) async {
      final api = VideoApi()..allowed = false;
      api.followups = [
        {
          'slot': 'morning',
          'canExplain': false,
          'missingPetIds': ['cat'],
          'explanations': [
            {
              'petId': 'cat',
              'reason': 'TEST emergency',
              'emergency': true,
              'created': '2026-10-28',
            },
          ],
        },
      ];
      final c = BookingVideoController(
        api,
        'booking',
        storage: ChatDraft(),
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingVideosPage(
            api: api,
            bookingId: 'booking',
            controller: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Enaga favqulodda holat bildirdi'),
        150,
      );
      expect(find.text('Enaga favqulodda holat bildirdi'), findsOneWidget);
      expect(find.text('Video hali yuborilmagan'), findsNWidgets(2));
      expect(find.text('Serverda saqlangan'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  test(
    'interrupted picker restores only target and never uploads lost global media',
    () async {
      final api = VideoApi(), storage = ChatDraft(), upload = FakeUpload();
      var c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
        transport: () => upload,
      );
      await c.load();
      final id = await c.beginSelection('cat', 'morning');
      expect(id, isNotNull);
      expect(storage.value!['bytes'], isNull);
      c.dispose();
      c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
        transport: () => upload,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.selectionInterrupted, true);
      await c.send();
      expect(upload.paths, isEmpty);
      await c.cancelSelection('another-picker');
      expect(c.pending, isNotNull);
      await c.discard();
      expect(c.canSelect('cat', 'morning'), true);
    },
  );
  test(
    'picker target survives date refresh and cancellation cannot erase saved bytes',
    () async {
      final api = VideoApi(), storage = ChatDraft();
      final c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await c.load();
      final id = await c.beginSelection('cat', 'morning');
      api.today = '2026-10-29';
      await c.load();
      await c.select('another-pet', 'morning', Uint8List(20), selectionId: id);
      expect(c.selectionInterrupted, true);
      await c.select('cat', 'morning', Uint8List(20), selectionId: id);
      expect(c.pending!['day'], '2026-10-28');
      expect(c.pending!['requestId'], id);
      expect(c.selectionInterrupted, false);
      await c.cancelSelection(id!);
      expect(storage.value!['bytes'], isNotNull);
    },
  );
  test(
    'picker requires durable intent and old session cannot store its result',
    () async {
      final api = VideoApi(), storage = ChatDraft()..failWrite = true;
      final c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(await c.beginSelection('cat', 'morning'), isNull);
      expect(c.error, isNotNull);
      storage.failWrite = false;
      final id = await c.beginSelection('cat', 'morning');
      CustomerApi.sessionVersion++;
      await c.select('cat', 'morning', Uint8List(20), selectionId: id);
      await c.cancelSelection(id!);
      expect(storage.value!['kind'], 'selection');
      expect(storage.value!['bytes'], isNull);
    },
  );
  testWidgets(
    'interrupted selection offers clear and reselect without a send button',
    (t) async {
      final api = VideoApi(), storage = ChatDraft();
      final c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await c.load();
      await c.beginSelection('cat', 'morning');
      await t.pumpWidget(
        MaterialApp(
          home: BookingVideosPage(
            api: api,
            bookingId: 'booking',
            controller: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Video tanlash yakunlanmagan'),
        findsOneWidget,
      );
      expect(find.text('Yuborish / qayta urinish'), findsNothing);
      expect(find.text('Qoralamani tozalash'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'expired video keeps history without loading thumbnail or enabling playback',
    (t) async {
      final api = VideoApi()..allowed = false;
      api.items = [
        {
          'id': 'expired',
          'petId': 'cat',
          'slot': 'morning',
          'durationMs': 10000,
          'available': false,
        },
      ];
      final c = BookingVideoController(
        api,
        'booking',
        storage: ChatDraft(),
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingVideosPage(
            api: api,
            bookingId: 'booking',
            controller: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Saqlash muddati tugagan'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsNothing);
      expect(find.byType(Image), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  test(
    'restart retries exact encrypted draft bytes and request after window closes',
    () async {
      final api = VideoApi(),
          storage = ChatDraft(),
          upload = FakeUpload()..fail = true;
      var c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
        transport: () => upload,
      );
      await c.load();
      await c.select('cat', 'morning', Uint8List.fromList(List.filled(20, 7)));
      expect(storage.value, isNotNull);
      await c.send();
      expect(c.pending, isNotNull);
      final first = upload.paths.single;
      c.dispose();
      api.open = false;
      upload.fail = false;
      c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
        transport: () => upload,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.canSelect('cat', 'morning'), false);
      await c.send();
      expect(upload.paths.last, first);
      expect(upload.contents.last, upload.contents.first);
      expect(c.pending, isNull);
      expect(storage.value, isNull);
    },
  );
  test(
    'cancel retains unconfirmed draft and late session response cannot clear it',
    () async {
      final api = VideoApi(),
          storage = ChatDraft(),
          upload = FakeUpload()..gate = Completer<void>();
      final c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
        transport: () => upload,
      );
      addTearDown(c.dispose);
      await c.load();
      await c.select('cat', 'morning', Uint8List(20));
      final sending = c.send();
      await Future<void>.delayed(Duration.zero);
      c.cancel();
      await sending;
      expect(c.pending, isNotNull);
      expect(c.error, isNotNull);
      expect(storage.value, isNotNull);
      upload.cancelled = false;
      upload.gate = Completer<void>();
      final second = c.send();
      await Future<void>.delayed(Duration.zero);
      CustomerApi.sessionVersion++;
      upload.gate!.complete();
      upload.gate = null;
      await second;
      expect(storage.value, isNotNull);
      expect(c.live, false);
    },
  );
  test(
    'server windows and permission gate selection and empty media is rejected',
    () async {
      final api = VideoApi(), storage = ChatDraft();
      final c = BookingVideoController(
        api,
        'booking',
        storage: storage,
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.canSelect('cat', 'morning'), true);
      expect(c.canSelect('cat', 'evening'), false);
      await c.select('cat', 'morning', Uint8List(0));
      expect(storage.value, isNull);
      expect(c.error, isNotNull);
      api.allowed = false;
      await c.load();
      await c.select('cat', 'morning', Uint8List(20));
      expect(c.pending, isNull);
    },
  );
  testWidgets(
    'read-only booking displays both missing videos and server-date refresh',
    (t) async {
      final api = VideoApi()..allowed = false;
      final c = BookingVideoController(
        api,
        'booking',
        storage: ChatDraft(),
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingVideosPage(
            api: api,
            bookingId: 'booking',
            controller: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('07:00'), findsOneWidget);
      expect(find.text('TEST cat'), findsOneWidget);
      final buttons = t
          .widgetList<IconButton>(find.byType(IconButton))
          .where(
            (b) =>
                b.icon is Icon &&
                (b.icon as Icon).icon == Icons.add_a_photo_outlined,
          );
      expect(buttons.length, 2);
      expect(buttons.every((b) => b.onPressed == null), true);
      api.today = '2026-10-29';
      await t.pump(const Duration(seconds: 60));
      await t.pumpAndSettle();
      expect(c.data!['day'], '2026-10-29');
      await t.pumpWidget(const SizedBox());
    },
  );
}
