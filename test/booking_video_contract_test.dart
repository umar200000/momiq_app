import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'booking_video_test.dart' show VideoApi;
import 'conversation_test.dart' show ChatDraft;

class BrokenVideoOverviewApi extends VideoApi {
  String? broken;
  @override
  Future<VideoJson> request(
    String method,
    String path, [
    VideoJson? body,
  ]) async {
    final result = await super.request(method, path, body);
    switch (broken) {
      case 'booking':
        result['bookingId'] = 'other';
      case 'day':
        result['day'] = '2026-02-30';
      case 'policy':
        result['policy']['timezone'] = 'UTC';
      case 'clock':
        result['policy']['serverTime'] = '2027-01-01T00:00:00Z';
      case 'window':
        result['policy']['slots'][0]['open'] = false;
      case 'capability':
        result['canUpload'] = 'true';
      case 'pet':
        result['pets'] = [result['pets'][0], result['pets'][0]];
      case 'media':
        result['items'] = [
          video(),
          {...video(), 'id': 'b' * 32},
        ];
      case 'expiry':
        result['items'] = [
          {...video(), 'expiresAt': '2026-10-27T00:00:00Z'},
        ];
      case 'foreignPet':
        result['items'] = [
          {...video(), 'petId': 'other'},
        ];
      case 'followup':
        result['followups'] = [
          {
            ...followup(),
            'missingPetIds': ['other'],
          },
        ];
      case 'reason':
        result['followups'] = [
          {
            ...followup(),
            'explanations': [
              {
                'petId': 'cat',
                'reason': true,
                'emergency': true,
                'created': '2026-10-28T06:00:00Z',
              },
            ],
          },
        ];
      case 'contradiction':
        result['items'] = [video()];
        result['followups'] = [followup()];
    }
    return result;
  }
}

VideoJson video() => {
  'id': 'a' * 32,
  'petId': 'cat',
  'day': '2026-10-28',
  'slot': 'morning',
  'durationMs': 10000,
  'bytes': 1000,
  'width': 128,
  'height': 96,
  'created': '2026-10-28T02:00:00Z',
  'available': true,
  'expiresAt': null,
};
VideoJson followup() => {
  'slot': 'morning',
  'dueAt': '2026-10-28T11:00:00+05:00',
  'canExplain': false,
  'missingPetIds': ['cat'],
  'explanations': [],
};

void main() {
  for (final failure in [
    'booking',
    'day',
    'policy',
    'clock',
    'window',
    'capability',
    'pet',
    'media',
    'expiry',
    'foreignPet',
    'followup',
    'reason',
    'contradiction',
  ]) {
    test(
      'video $failure response preserves original view and upload retry',
      () async {
        final api = BrokenVideoOverviewApi(), store = ChatDraft();
        final c = BookingVideoController(
          api,
          'booking',
          storage: store,
          explanationStorage: ChatDraft(),
        );
        addTearDown(c.dispose);
        await c.load();
        expect(c.error, isNull);
        await c.select('cat', 'morning', Uint8List(20));
        final data = c.data, pending = Map.of(c.pending!);
        api.broken = failure;
        await c.load();
        expect(c.error, isA<FormatException>());
        expect(c.data, same(data));
        expect(c.pending, pending);
        expect(store.value, pending);
        api.broken = null;
        await c.load();
        expect(c.error, isNull);
      },
    );
  }
  test(
    'historical requested day uses current server policy without enabling upload',
    () async {
      final api = VideoApi()..today = '2026-10-29';
      api.items = [video()];
      final c = BookingVideoController(
        api,
        'booking',
        storage: ChatDraft(),
        explanationStorage: ChatDraft(),
      );
      addTearDown(c.dispose);
      await c.load(day: '2026-10-28');
      expect(c.error, isNull);
      expect(c.data!['day'], '2026-10-28');
      expect(c.data!['policy']['today'], '2026-10-29');
      expect(c.canSelect('cat', 'evening'), false);
    },
  );
}
