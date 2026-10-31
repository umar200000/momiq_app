import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/bookings/data/booking_composer.dart';
import 'package:momiq_app/features/bookings/data/booking_controller.dart';
import 'package:momiq_app/features/bookings/presentation/bookings_page.dart';
import 'package:momiq_app/features/bookings/presentation/booking_request_page.dart';
import 'booking_controller_test.dart'
    show BookingMemory, BookingApiFake, fixture, inboxRow;

class SourceApi extends CustomerApi {
  SourceApi(this.label) : super('TEST', 'owner');
  final String label;
  Completer<void>? gate;
  bool fail = false;
  final calls = <String>[];
  @override
  Future<BookingJson> request(
    String method,
    String path, [
    BookingJson? body,
  ]) async {
    calls.add('$method $path');
    if (gate != null) await gate!.future;
    if (fail) throw StateError('TEST obsolete response');
    if (path == '/bookings/policy') {
      return {'version': 'elapsed-24h-v1', 'source': label};
    }
    if (path == '/bookings' && method == 'POST') {
      final booking = fixture();
      return {
        ...booking,
        'myRole': 'customer',
        'acknowledgement': {
          'action': 'request',
          'bookingId': booking['id'],
          ...body!,
        },
      };
    }
    if (path == '/bookings' || path.contains('/conversations/')) {
      return {
        'items': [
          {...inboxRow('a' * 32, 'pending'), 'peerName': label},
        ],
        'nextCursor': null,
      };
    }
    return {
      ...fixture(),
      'id': path.split('/')[2],
      'snapshot': {...fixture()['snapshot'], 'customerName': label},
    };
  }
}

dynamic flowController(String kind, SourceApi api, String id) => switch (kind) {
  'detail' => BookingController(api, id, storage: BookingMemory()),
  'compose' => BookingComposer(api, id, storage: BookingMemory()),
  _ => null,
};
Widget flowPage(String kind, SourceApi api, String id, dynamic controller) {
  if (kind == 'detail') {
    return BookingDetailPage(api: api, id: id, controller: controller);
  }
  if (kind == 'inbox') {
    return Scaffold(
      body: SingleChildScrollView(
        child: BookingInbox(api: api, conversationId: id),
      ),
    );
  }
  final store = EmptyStore()..api = api;
  addTearDown(store.dispose);
  return BookingRequestPage(
    store: store,
    sitter: {
      'id': id,
      'name': api.label,
      'service': 0,
      'pets': ['Mushuk'],
    },
    composer: controller,
  );
}

class EmptyStore extends CustomerStore {
  @override
  List<CJson> list(String key) => [];
}

class HeldClear extends BookingMemory {
  Completer<void>? gate;
  @override
  Future<void> clear() async {
    if (gate != null) await gate!.future;
    await super.clear();
  }
}

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final kind in ['detail', 'compose', 'inbox']) {
    for (final fail in [false, true]) {
      testWidgets(
        '$kind ignores late previous source ${fail ? 'error' : 'success'}',
        (t) async {
          final old = SourceApi('OLD PRIVATE')
            ..gate = Completer<void>()
            ..fail = fail;
          final fresh = SourceApi('NEW SOURCE');
          final oldC = flowController(kind, old, 'a' * 32),
              freshC = flowController(kind, fresh, 'b' * 32);
          if (oldC != null) addTearDown(oldC.dispose);
          if (freshC != null) addTearDown(freshC.dispose);
          await t.pumpWidget(
            MaterialApp(home: flowPage(kind, old, 'a' * 32, oldC)),
          );
          await t.pump();
          await t.pumpWidget(
            MaterialApp(home: flowPage(kind, fresh, 'b' * 32, freshC)),
          );
          await t.pumpAndSettle();
          old.gate!.complete();
          await t.pumpAndSettle();
          expect(find.textContaining('OLD PRIVATE'), findsNothing);
          expect(find.textContaining('NEW SOURCE'), findsOneWidget);
          expect(find.textContaining('TEST obsolete'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '$kind target-only replacement cannot revive an expired session',
      (t) async {
        final api = SourceApi('PRIVATE');
        final c = flowController(kind, api, 'a' * 32);
        if (c != null) addTearDown(c.dispose);
        await t.pumpWidget(MaterialApp(home: flowPage(kind, api, 'a' * 32, c)));
        await t.pumpAndSettle();
        final count = api.calls.length;
        CustomerApi.sessionVersion++;
        final replacement = flowController(kind, api, 'b' * 32);
        if (replacement != null) addTearDown(replacement.dispose);
        await t.pumpWidget(
          MaterialApp(home: flowPage(kind, api, 'b' * 32, replacement)),
        );
        await t.pumpAndSettle();
        expect(api.calls.length, count);
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.textContaining('Sessiya o‘zgardi'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final fail in [false, true]) {
    testWidgets(
      'late booking submission ${fail ? 'error' : 'success'} cannot navigate the replacement form',
      (t) async {
        final old = SourceApi('OLD'), fresh = SourceApi('NEW');
        final memory = BookingMemory()
          ..value = {
            'draft': {},
            'quote': null,
            'pending': {'quoteId': 'TEST-quote', 'requestId': 'x' * 32},
          };
        final c = BookingComposer(old, 'a' * 32, storage: memory);
        final replacement = BookingComposer(
          fresh,
          'b' * 32,
          storage: BookingMemory(),
        );
        addTearDown(c.dispose);
        addTearDown(replacement.dispose);
        await t.pumpWidget(
          MaterialApp(home: flowPage('compose', old, 'a' * 32, c)),
        );
        await t.pumpAndSettle();
        old.gate = Completer<void>();
        old.fail = fail;
        final submit = find.byKey(const ValueKey('submitBookingStep'));
        await t.ensureVisible(submit);
        await t.tap(submit);
        await t.pump();
        await t.pumpWidget(
          MaterialApp(home: flowPage('compose', fresh, 'b' * 32, replacement)),
        );
        await t.pumpAndSettle();
        old.gate!.complete();
        await t.pumpAndSettle();
        expect(old.calls.where((v) => v == 'POST /bookings').length, 1);
        expect(find.byType(BookingDetailPage), findsNothing);
        expect(find.textContaining('NEW'), findsOneWidget);
        expect(find.textContaining('TEST obsolete'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final kind in ['detail', 'compose']) {
    testWidgets('$kind rejects a controller from a different API or target', (
      t,
    ) async {
      final api = SourceApi('TEST'), other = SourceApi('OTHER');
      for (final wrongApi in [false, true]) {
        final c = flowController(
          kind,
          wrongApi ? other : api,
          wrongApi ? 'a' * 32 : 'b' * 32,
        );
        addTearDown(c.dispose);
        await t.pumpWidget(MaterialApp(home: flowPage(kind, api, 'a' * 32, c)));
        await t.pumpAndSettle();
        expect(api.calls, isEmpty);
        expect(other.calls, isEmpty);
        expect(find.textContaining('Sessiya o‘zgardi'), findsOneWidget);
      }
    });
  }
  testWidgets(
    'obsolete cancellation dialog closes without sending or closing another page',
    (t) async {
      final old = SourceApi('OLD'), fresh = SourceApi('NEW');
      final c = BookingController(old, 'a' * 32, storage: BookingMemory());
      final replacement = BookingController(
        fresh,
        'b' * 32,
        storage: BookingMemory(),
      );
      addTearDown(c.dispose);
      addTearDown(replacement.dispose);
      await t.pumpWidget(
        MaterialApp(home: flowPage('detail', old, 'a' * 32, c)),
      );
      await t.pumpAndSettle();
      final cancel = find.byKey(const ValueKey('cancelBooking'));
      await t.scrollUntilVisible(cancel, 250);
      await t.tap(cancel);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'PRIVATE reason',
      );
      await t.pumpWidget(
        MaterialApp(home: flowPage('detail', fresh, 'b' * 32, replacement)),
      );
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('PRIVATE reason'), findsNothing);
      expect(find.text('NEW'), findsOneWidget);
      expect(old.calls.where((v) => v.startsWith('POST')), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets(
      'booking acceptance dialog scrolls at 320px and 2x in $language',
      (t) async {
        AppLanguage.current.value = language;
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final api = SourceApi('TEST');
        final current = BookingController(
          api,
          'a' * 32,
          storage: BookingMemory(),
        );
        addTearDown(current.dispose);
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: flowPage('detail', api, 'a' * 32, current),
          ),
        );
        await t.pumpAndSettle();
        final button = find.byKey(const ValueKey('acceptBooking'));
        await t.scrollUntilVisible(button, 300);
        await t.tap(button);
        await t.pumpAndSettle();
        final back = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        );
        await t.ensureVisible(back);
        await t.pumpAndSettle();
        await t.tap(back);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(api.calls.where((v) => v.startsWith('POST')), isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'retained detail navigation callback cannot open a page after logout',
    (t) async {
      final api = SourceApi('TEST');
      final c = BookingController(api, 'a' * 32, storage: BookingMemory());
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(home: flowPage('detail', api, 'a' * 32, c)),
      );
      await t.pumpAndSettle();
      final target = find.byKey(const ValueKey('bookingSupport'));
      await t.scrollUntilVisible(target, 250);
      final callback = t.widget<TextButton>(target).onPressed!;
      final count = api.calls.length;
      CustomerApi.sessionVersion++;
      callback();
      await t.pumpAndSettle();
      expect(api.calls.length, count);
      expect(find.byType(BookingDetailPage), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'covered creation form preserves newer route and reopens one confirmed booking',
    (t) async {
      final api = SourceApi('TEST');
      final memory = BookingMemory()
        ..value = {
          'draft': {},
          'quote': null,
          'pending': {'quoteId': 'TEST-quote', 'requestId': 'x' * 32},
        };
      final c = BookingComposer(api, 'a' * 32, storage: memory);
      addTearDown(c.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: flowPage('compose', api, 'a' * 32, c),
        ),
      );
      await t.pumpAndSettle();
      api.gate = Completer<void>();
      final submit = find.byKey(const ValueKey('submitBookingStep'));
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pump();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('NEWER ROUTE')),
        ),
      );
      await t.pump();
      api.gate!.complete();
      await t.pumpAndSettle();
      expect(find.text('NEWER ROUTE'), findsOneWidget);
      expect(find.byType(BookingDetailPage), findsNothing);
      expect(api.calls.where((v) => v == 'POST /bookings').length, 1);
      expect(c.pending, isNull);
      expect(await c.submit(), true);
      expect(api.calls.where((v) => v == 'POST /bookings').length, 1);
      expect(t.takeException(), isNull);
    },
  );
  test(
    'uncertain action clear blocks concurrent resend until storage confirms',
    () async {
      final api = BookingApiFake()..loseResponse = true, store = HeldClear();
      final c = BookingController(api, fixture()['id'], storage: store);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.act('accept'), false);
      store.gate = Completer<void>();
      final clear = c.discardUncertainAction();
      expect(c.loading, true);
      expect(await c.act('accept'), false);
      expect(api.posts.length, 1);
      store.gate!.complete();
      await clear;
      expect(c.pending, isNull);
      expect(store.value, isNull);
      expect(c.booking!['status'], 'accepted');
    },
  );
  test(
    'obsolete quote response does not replace or persist composer state',
    () async {
      final api = SourceApi('TEST');
      final store = BookingMemory();
      final current = BookingComposer(api, 'listing', storage: store);
      addTearDown(current.dispose);
      await current.load();
      api.gate = Completer<void>();
      final request = current.getQuote();
      await Future<void>.delayed(Duration.zero);
      CustomerApi.sessionVersion++;
      api.gate!.complete();
      expect(await request, false);
      expect(current.quote, isNull);
      expect(store.value!['quote'], isNull);
      expect(current.error, isNull);
    },
  );
}
