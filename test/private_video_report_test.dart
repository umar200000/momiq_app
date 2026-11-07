import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'package:momiq_app/features/care/presentation/booking_videos_page.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'booking_video_contract_test.dart' show video;
import 'booking_video_test.dart' show VideoApi;
import 'conversation_test.dart' show ChatDraft;
import 'support_test.dart' show SupportApi;

class ReportVideoApi extends VideoApi {
  @override
  Future<Uint8List> videoPoster(String path) async =>
      throw StateError('TEST unavailable');
}

class VideoReportReply extends SupportApi {
  bool mismatch = true;
  @override
  Future<SupportJson> request(
    String method,
    String path, [
    SupportJson? body,
  ]) async {
    final result = await super.request(method, path, body);
    if (body != null) {
      result['ticket'].addAll({
        'topic': 'safety',
        'bookingId': body['bookingId'],
      });
      result['videoReport'] = {
        'id': mismatch ? '0' * 32 : body['reportVideoId'],
        'day': '2026-10-28',
        'slot': 'morning',
      };
    }
    return result;
  }
}

void main() {
  testWidgets('report opens the specific private video and booking', (t) async {
    final api = ReportVideoApi()..items = [video()];
    final booking = 'c' * 32;
    final controller = BookingVideoController(
      api,
      booking,
      storage: ChatDraft(),
      explanationStorage: ChatDraft(),
    );
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: BookingVideosPage(
          api: api,
          bookingId: booking,
          controller: controller,
        ),
      ),
    );
    await t.pumpAndSettle();
    final button = find.byKey(ValueKey("report-video-${'a' * 32}"));
    await t.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(button);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final page = t.widget<SupportThreadPage>(find.byType(SupportThreadPage));
    expect(page.bookingId, booking);
    expect(page.target, {'kind': 'booking_video', 'id': 'a' * 32});
  });
  test('a different video acknowledgement keeps the original report', () async {
    final api = VideoReportReply(), storage = ChatDraft();
    final target = {'kind': 'booking_video', 'id': 'f' * 32};
    final controller = SupportController(
      api,
      null,
      storage: storage,
      target: target,
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(
      await controller.send(
        'TEST reason',
        null,
        topic: 'safety',
        subject: 'TEST',
        bookingId: 'b' * 32,
      ),
      false,
    );
    final original = Map.of(controller.pending!);
    expect(original['reportVideoId'], target['id']);
    expect(original.containsKey('target'), false);
    api.mismatch = false;
    expect(await controller.send('changed', null), true);
    expect(api.posts, [original, original]);
  });
}
