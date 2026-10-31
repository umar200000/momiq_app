import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/bookings/data/booking_contract.dart';
import 'package:momiq_app/features/bookings/data/booking_composer.dart';
import 'package:momiq_app/features/bookings/data/booking_controller.dart';
import 'booking_composer_test.dart' show ComposerApi, formFields;
import 'booking_controller_test.dart'
    show BookingApiFake, BookingMemory, DelayedInboxApi, fixture, inboxRow;

class AlteredQuoteApi extends ComposerApi {
  void Function(BookingJson)? alter;
  @override
  Future<BookingJson> request(
    String method,
    String path, [
    BookingJson? body,
  ]) async {
    final value = await super.request(method, path, body);
    if (method == 'POST') alter?.call(value);
    return value;
  }
}

class AlteredActionApi extends BookingApiFake {
  bool wrongReceipt = true;
  @override
  Future<BookingJson> request(
    String method,
    String path, [
    BookingJson? body,
  ]) async {
    final value = await super.request(method, path, body);
    if (method == 'POST' && wrongReceipt) {
      value['acknowledgement']['requestId'] = 'other';
    }
    return value;
  }
}

void main() {
  test('home visit quote must belong to the selected saved address', () async {
    final draft = {...formFields(), 'addressId': 'home'};
    final quote = await ComposerApi().request('POST', '/bookings/quotes', {
      ...draft,
      'listingId': 'abc:homeVisit',
    });
    final snapshot = quote['snapshot'];
    snapshot['listingId'] = 'abc:homeVisit';
    snapshot['price']['service'] = 'homeVisit';
    for (final invalid in [null, 'other']) {
      snapshot['addressId'] = invalid;
      expect(
        () => checkBookingQuote(quote, 'abc:homeVisit', draft),
        throwsFormatException,
      );
    }
    snapshot['addressId'] = 'home';
    checkBookingQuote(quote, 'abc:homeVisit', draft);
  });
  test(
    'wrong listing, swapped pets, interval or bill cannot be submitted',
    () async {
      final api = AlteredQuoteApi(), store = BookingMemory();
      final c = BookingComposer(api, 'sitter:boarding', storage: store);
      addTearDown(c.dispose);
      await c.load();
      await c.saveDraft(formFields());
      for (final alter in <void Function(BookingJson)>[
        (q) => q['snapshot']['listingId'] = 'other:boarding',
        (q) => q['snapshot']['pets'][0]['id'] = 'other',
        (q) => q['snapshot']['price']['service'] = 'personal',
        (q) => q['snapshot']['endsAt'] = '2030-01-02T16:00:00Z',
        (q) => q['snapshot']['price']['service_total_minor']++,
        (q) => q['snapshot']['price']['commission_minor']++,
        (q) => q['expiresAt'] = '2030-01-02T16:00:00Z',
      ]) {
        api.alter = alter;
        expect(await c.getQuote(), false);
        expect(c.error, isA<FormatException>());
        expect(store.value!['quote'], isNull);
        expect(await c.submit(), false);
      }
      expect(api.submissions, isEmpty);
    },
  );
  test(
    'unmatched creation receipt survives restart with original request and quote',
    () async {
      final api = AlteredQuoteApi(), store = BookingMemory();
      final c = BookingComposer(api, 'sitter:boarding', storage: store);
      await c.load();
      await c.saveDraft(formFields());
      expect(await c.getQuote(), true);
      api.alter = (r) => r['acknowledgement']['quoteId'] = 'other';
      expect(await c.submit(), false);
      expect(c.result, isNull);
      final original = Map.of(c.pending!);
      expect(store.value!['pending'], original);
      c.dispose();
      api.alter = null;
      final restored = BookingComposer(api, 'sitter:boarding', storage: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(await restored.submit(), true);
      expect(api.created.length, 1);
      expect(api.submissions, [original, original]);
    },
  );
  test(
    'wrong action receipt does not publish another decision or discard a retry',
    () async {
      final api = AlteredActionApi(), store = BookingMemory();
      final c = BookingController(api, fixture()['id'], storage: store);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.act('accept'), false);
      expect(c.booking!['status'], 'pending');
      expect(store.value, c.pending);
      api.wrongReceipt = false;
      expect(await c.act('accept'), true);
      expect(api.charges, 1);
      expect(c.booking!['status'], 'accepted');
    },
  );
  test(
    'one malformed item or non-advancing cursor cannot partially replace the inbox',
    () async {
      final api = DelayedInboxApi(), c = BookingInboxController(api);
      addTearDown(c.dispose);
      final initial = c.load();
      final first = inboxRow('a' * 32, 'pending');
      api.replies.last.complete({
        'items': [first],
        'nextCursor': '9',
      });
      await initial;
      for (final page in [
        {
          'items': [
            inboxRow('b' * 32, 'accepted'),
            {...first, 'endsAt': 'bad'},
          ],
          'nextCursor': '4',
        },
        {
          'items': [inboxRow('b' * 32, 'accepted')],
          'nextCursor': '9',
        },
        {
          'items': [inboxRow('b' * 32, 'accepted')],
          'nextCursor': false,
        },
      ]) {
        final more = c.load(more: true);
        api.replies.last.complete(page);
        await more;
        expect(c.error, isA<FormatException>());
        expect(c.items, [first]);
        expect(c.cursor, '9');
      }
    },
  );
}
