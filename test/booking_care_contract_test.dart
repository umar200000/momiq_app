import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/care/data/booking_care_data.dart';
import 'booking_care_test.dart' show CareApi, reportValues;
import 'conversation_test.dart' show ChatDraft;

CareJson entry(int id) => {
  'id': '$id',
  'petId': 'cat',
  'kind': 'report',
  'day': '2026-10-28',
  'category': 'food',
  'revision': id,
  'actorRole': 'sitter',
  'payload': {'state': 'done', 'note': 'TEST'},
  'created': '2026-10-28T05:00:00Z',
};

class BrokenCareApi extends CareApi {
  String? broken;
  CareJson? history;
  @override
  Future<CareJson> request(String method, String path, [CareJson? body]) async {
    if (path.contains('/history') && history != null) return history!;
    final value = await super.request(method, path, body);
    if (method == 'POST') {
      if (broken == 'receipt') value['requestId'] = 'different';
      if (broken == 'pet') value['petId'] = 'other';
      if (broken == 'payload') {
        value['payload'] = {'state': 'done', 'note': 'Different'};
      }
      if (broken == 'revision') value['revision'] = 0;
    } else if (!path.contains('/history')) {
      if (broken == 'booking') value['bookingId'] = 'other';
      if (broken == 'day') value['day'] = '2026-02-30';
      if (broken == 'capability') value['canReport'] = 'true';
      if (broken == 'pet') value['pets'] = [value['pets'][0], value['pets'][0]];
    }
    return value;
  }
}

void main() {
  for (final failure in ['receipt', 'pet', 'payload', 'revision']) {
    test(
      'care $failure acknowledgement preserves original persisted request',
      () async {
        final api = BrokenCareApi(), store = ChatDraft();
        final c = BookingCareController(api, 'booking', storage: store);
        addTearDown(c.dispose);
        await c.load();
        final before = c.data;
        api.broken = failure;
        expect(await c.save(reportValues()), false);
        expect(c.data, same(before));
        final original = Map.of(c.pending!);
        expect(store.value, original);
        api.broken = null;
        expect(await c.save({}), true);
        expect(api.posts, [original, original]);
        expect(c.pending, isNull);
        expect(store.value, isNull);
      },
    );
  }
  test(
    'care malformed overview leaves original day and pets untouched',
    () async {
      final api = BrokenCareApi();
      final current = BookingCareController(
        api,
        'booking',
        storage: ChatDraft(),
      );
      addTearDown(current.dispose);
      await current.load();
      final before = current.data;
      for (final failure in ['booking', 'day', 'capability', 'pet']) {
        api.broken = failure;
        await current.load();
        expect(current.data, same(before));
        expect(current.error, isNotNull);
      }
    },
  );
  test(
    'care history validates complete page before merging or advancing cursor',
    () async {
      final api = BrokenCareApi()
        ..history = {
          'items': [for (var id = 60; id > 30; id--) entry(id)],
          'nextCursor': '31',
        };
      final c = BookingCareController(api, 'booking', storage: ChatDraft());
      addTearDown(c.dispose);
      await c.load();
      await c.loadHistory();
      expect(c.history.length, 30);
      expect(c.historyCursor, '31');
      api.history = {
        'items': [
          entry(30),
          {...entry(29), 'actorRole': 'admin'},
        ],
        'nextCursor': null,
      };
      await c.loadHistory();
      expect(c.error, isNotNull);
      expect(c.history.length, 30);
      expect(c.historyCursor, '31');
      api.history = {
        'items': [entry(30), entry(29)],
        'nextCursor': null,
      };
      await c.loadHistory();
      expect(c.error, isNull);
      expect(c.history.length, 32);
      expect(c.historyCursor, isNull);
    },
  );
  test(
    'care drafts and nested entries cannot inject unsupported identities or shapes',
    () {
      expect(
        () => careDraft({'requestId': 'x' * 32, 'payload': {}}),
        throwsFormatException,
      );
      expect(
        () => careHistory({
          'items': [entry(1), entry(1)],
          'nextCursor': null,
        }),
        throwsFormatException,
      );
      expect(
        () => careEntry({
          ...entry(1),
          'payload': {'state': 'skipped', 'note': ''},
        }),
        throwsFormatException,
      );
      expect(
        () => careHistory({
          'items': [entry(1)],
          'nextCursor': '1',
        }),
        throwsFormatException,
      );
    },
  );
}
