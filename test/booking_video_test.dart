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
      'items': [],
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
      'id': 'saved',
      'petId': query['petId'],
      'day': query['day'],
      'slot': query['slot'],
    };
  }
}

void main() {
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
      final c = BookingVideoController(api, 'booking', storage: storage);
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
      final c = BookingVideoController(api, 'booking', storage: ChatDraft());
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
