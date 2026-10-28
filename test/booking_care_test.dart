import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/care/presentation/booking_care_page.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'conversation_test.dart' show ChatDraft;

class CareApi extends CustomerApi {
  CareApi() : super('test', 'sitter');
  bool loseResponse = false, failLoad = false;
  Completer<void>? gate;
  String role = 'sitter', status = 'active', today = '2026-10-28';
  final posts = <CareJson>[], saved = <String>{};
  CareJson? report;
  @override
  Future<CareJson> request(String method, String path, [CareJson? body]) async {
    if (method == 'POST') {
      posts.add(Map.of(body!));
      saved.add(body['requestId']);
      report = {
        'id': '1',
        'petId': 'cat',
        'kind': 'report',
        'day': body['day'],
        'category': body['category'],
        'revision': 1,
        'payload': body['payload'],
        'created': '2026-10-28T05:00:00Z',
      };
      if (loseResponse) {
        loseResponse = false;
        throw StateError('Response lost');
      }
      return report!;
    }
    if (gate != null) await gate!.future;
    if (failLoad) throw StateError('Offline');
    if (path.contains('/history')) {
      return {
        'items': report == null ? [] : [report],
        'nextCursor': null,
      };
    }
    final day = Uri.parse(path).queryParameters['day'] ?? today;
    return {
      'myRole': role,
      'status': status,
      'today': today,
      'day': day,
      'originalInstructions': 'TEST care',
      'canEditInstructions': role == 'customer' && status == 'active',
      'canReport': role == 'sitter' && status == 'active' && day == today,
      'pets': [
        {
          'id': 'cat',
          'name': 'TEST pet',
          'originalNotes': '',
          'originalMedication': '',
          'instructions': null,
          'reports': report == null ? [] : [report],
        },
      ],
    };
  }
}

CareJson reportValues() => {
  'petId': 'cat',
  'kind': 'report',
  'day': '2026-10-28',
  'category': 'food',
  'revision': 0,
  'payload': {'state': 'done', 'note': 'TEST only'},
};

void main() {
  testWidgets(
    'customer instruction form requires a reason and keeps each category',
    (t) async {
      final api = CareApi()..role = 'customer';
      final c = BookingCareController(api, 'booking', storage: ChatDraft());
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingCarePage(api: api, bookingId: 'booking', controller: c),
        ),
      );
      await t.pumpAndSettle();
      final button = find.byKey(const ValueKey('careInstructions-cat'));
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('careEditorSave')));
      await t.pumpAndSettle();
      expect(api.posts, isEmpty);
      final food = find.byKey(const ValueKey('careField-food'));
      await t.ensureVisible(food);
      await t.enterText(food, '08:00 TEST food');
      final reason = find.byKey(const ValueKey('careField-reason'));
      await t.ensureVisible(reason);
      await t.enterText(reason, 'TEST agreed care');
      await t.tap(find.byKey(const ValueKey('careEditorSave')));
      await t.pumpAndSettle();
      expect(api.posts.single['kind'], 'instructions');
      expect(api.posts.single['payload']['food'], '08:00 TEST food');
      expect(api.posts.single['payload']['medicine'], '');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'server midnight refresh switches today without trusting device clock',
    (t) async {
      final api = CareApi();
      final c = BookingCareController(api, 'booking', storage: ChatDraft());
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingCarePage(api: api, bookingId: 'booking', controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(c.data!['day'], '2026-10-28');
      api.today = '2026-10-29';
      await t.pump(const Duration(seconds: 60));
      await t.pumpAndSettle();
      expect(c.data!['day'], '2026-10-29');
      await c.load(day: '2026-10-28');
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 60));
      await t.pumpAndSettle();
      expect(c.data!['day'], '2026-10-28');
      expect(c.data!['canReport'], false);
      await t.pumpWidget(const SizedBox());
    },
  );

  test(
    'lost report response survives restart with exact idempotent content',
    () async {
      final api = CareApi()..loseResponse = true;
      final storage = ChatDraft();
      var c = BookingCareController(api, 'booking', storage: storage);
      await c.load();
      expect(await c.save(reportValues()), false);
      final first = Map.of(storage.value!);
      c.dispose();
      c = BookingCareController(api, 'booking', storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(c.pending, first);
      expect(
        await c.save({
          'payload': {'note': 'must not replace'},
        }),
        true,
      );
      expect(api.posts, [first, first]);
      expect(api.saved.length, 1);
      expect(c.pending, isNull);
      expect(storage.value, isNull);
    },
  );
  test(
    'failed local persistence blocks POST and late session response is discarded',
    () async {
      final api = CareApi(), storage = ChatDraft()..failWrite = true;
      final c = BookingCareController(api, 'booking', storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.save(reportValues()), false);
      expect(api.posts, isEmpty);
      final late = BookingCareController(api, 'booking', storage: ChatDraft());
      addTearDown(late.dispose);
      api.gate = Completer<void>();
      final loading = late.load();
      await Future<void>.delayed(Duration.zero);
      CustomerApi.sessionVersion++;
      api.gate!.complete();
      await loading;
      expect(late.data, isNull);
      expect(late.live, false);
    },
  );
  testWidgets('active sitter submits real report and history is visible', (
    t,
  ) async {
    final api = CareApi();
    final c = BookingCareController(api, 'booking', storage: ChatDraft());
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: BookingCarePage(api: api, bookingId: 'booking', controller: c),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Hali qayd yo‘q'), findsWidgets);
    final button = find.byKey(const ValueKey('careReport-cat-food'));
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('careField-note')), 'TEST fed');
    await t.tap(find.byKey(const ValueKey('careEditorSave')));
    await t.pumpAndSettle();
    expect(api.posts.single['payload']['note'], 'TEST fed');
    expect(c.pending, isNull);
    expect(c.data!['pets'][0]['reports'][0]['payload']['state'], 'done');
    await c.loadHistory();
    expect(c.history.length, 1);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('customer and completed service cannot write sitter reports', (
    t,
  ) async {
    final api = CareApi()..role = 'customer';
    final c = BookingCareController(api, 'booking', storage: ChatDraft());
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: BookingCarePage(api: api, bookingId: 'booking', controller: c),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('careReport-cat-food')), findsNothing);
    expect(find.byKey(const ValueKey('careInstructions-cat')), findsOneWidget);
    api.status = 'completed';
    await c.load();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('careInstructions-cat')), findsNothing);
    expect(find.byKey(const ValueKey('careReport-cat-food')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'failed fetch cannot masquerade as empty care or enable editing',
    (t) async {
      final api = CareApi()..failLoad = true;
      final c = BookingCareController(api, 'booking', storage: ChatDraft());
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: BookingCarePage(api: api, bookingId: 'booking', controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('careError')), findsOneWidget);
      expect(find.text('Hali qayd yo‘q'), findsNothing);
      expect(api.posts, isEmpty);
      api.failLoad = false;
      await c.load();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('careReport-cat-food')), findsOneWidget);
      api.failLoad = true;
      await c.load();
      await t.pumpAndSettle();
      expect(
        t
            .widget<IconButton>(
              find.byKey(const ValueKey('careReport-cat-food')),
            )
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
