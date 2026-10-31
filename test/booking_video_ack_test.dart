import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'booking_video_test.dart' show VideoApi, FakeUpload, ExplanationApi;
import 'conversation_test.dart' show ChatDraft;

class WrongUpload extends FakeUpload {
  String? broken;
  @override
  Future<VideoJson> send(
    CustomerApi api,
    String path,
    Uint8List bytes,
    void Function(double) progress,
  ) async {
    final result = await super.send(api, path, bytes, progress);
    switch (broken) {
      case 'source':
        result['bookingId'] = 'different';
      case 'request':
        result['requestId'] = 'different';
      case 'id':
        result['id'] = 'not-an-id';
      case 'duration':
        result['durationMs'] = 1;
      case 'pixels':
        result['width'] = 1920;
        result['height'] = 1920;
    }
    return result;
  }
}

class WrongExplanation extends ExplanationApi {
  String? broken;
  @override
  Future<VideoJson> request(
    String method,
    String path, [
    VideoJson? body,
  ]) async {
    final result = await super.request(method, path, body);
    if (method == 'POST') {
      switch (broken) {
        case 'source':
          result['bookingId'] = 'different';
        case 'request':
          result['requestId'] = 'different';
        case 'reason':
          result['reason'] = 'different';
      }
    }
    return result;
  }
}

void main() {
  for (final failure in ['source', 'request', 'id', 'duration', 'pixels']) {
    test(
      'video $failure acknowledgement retains exact bytes and request for retry',
      () async {
        final api = VideoApi(),
            upload = WrongUpload()..broken = failure,
            storage = ChatDraft();
        final c = BookingVideoController(
          api,
          'booking',
          storage: storage,
          explanationStorage: ChatDraft(),
          transport: () => upload,
        );
        addTearDown(c.dispose);
        await c.load();
        await c.select(
          'cat',
          'morning',
          Uint8List.fromList(List.filled(16, 1)),
        );
        final original = Map.of(c.pending!);
        await c.send();
        expect(c.error, isNotNull);
        expect(c.pending, original);
        expect(storage.value, original);
        upload.broken = null;
        await c.send();
        expect(c.pending, isNull);
        expect(storage.value, isNull);
        expect(upload.paths.length, 2);
        expect(upload.paths.first, upload.paths.last);
        expect(upload.contents.first, upload.contents.last);
      },
    );
  }
  for (final failure in ['source', 'request', 'reason']) {
    test(
      'missing-video explanation $failure acknowledgement cannot clear evidence',
      () async {
        final api = WrongExplanation()
              ..loseResponse = false
              ..broken = failure,
            storage = ChatDraft();
        final c = BookingVideoController(
          api,
          'booking',
          storage: ChatDraft(),
          explanationStorage: storage,
        );
        addTearDown(c.dispose);
        await c.load();
        await c.explain('cat', 'morning', 'TEST original reason', true);
        final original = Map.of(c.explanationDraft!);
        expect(c.error, isNotNull);
        expect(storage.value, original);
        api.broken = null;
        await c.sendExplanation();
        expect(c.explanationDraft, isNull);
        expect(storage.value, isNull);
        expect(api.sent.length, 2);
        expect(api.sent.first, api.sent.last);
      },
    );
  }
}
