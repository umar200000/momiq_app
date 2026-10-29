import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/media/presentation/private_api_image.dart';
import 'package:momiq_app/features/support/support_page.dart';
import 'package:momiq_app/features/bookings/presentation/bookings_page.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP8//8/AwMDEwMYAAAkBgMBXaJOiAAAAABJRU5ErkJggg==';

class ImageApi extends CustomerApi {
  ImageApi(String owner) : super('TEST', owner);
  final calls = <String>[], pending = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    expect(method, 'GET');
    calls.add(path);
    final request = Completer<Map<String, dynamic>>();
    pending.add(request);
    return request.future;
  }
}

void main() {
  setUp(() => CustomerApi.active = null);
  Future<void> show(WidgetTester t, CustomerApi api, String path) =>
      t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivateApiImage(api: api, path: path, label: 'TEST image'),
          ),
        ),
      );
  Future<void> open(WidgetTester t) async {
    await t.tap(find.byType(TextButton));
    await t.pump();
  }

  testWidgets(
    'explicit load deduplicates clicks and old path cannot replace new image',
    (t) async {
      final api = ImageApi('owner');
      await show(t, api, '/first');
      expect(api.calls, isEmpty);
      await open(t);
      await open(t);
      expect(api.calls, ['/first']);
      await show(t, api, '/second');
      await open(t);
      api.pending[0].complete({'image': pixel});
      await t.pump();
      expect(find.byType(Image), findsNothing);
      expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
      api.pending[1].complete({'image': pixel});
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(
        (t.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        base64Decode(pixel),
      );
      await show(t, api, '/third');
      expect(find.byType(Image), findsNothing);
    },
  );
  testWidgets(
    'session change suppresses old response and cannot revive old API on another path',
    (t) async {
      final api = ImageApi('old');
      await show(t, api, '/first');
      await open(t);
      CustomerApi.sessionVersion++;
      api.pending.single.complete({'image': pixel});
      await t.pump();
      expect(find.byType(Image), findsNothing);
      await show(t, api, '/second');
      expect(find.byType(TextButton), findsNothing);
      expect(api.calls.length, 1);
      final next = ImageApi('new');
      CustomerApi.active = next;
      await show(t, next, '/second');
      await open(t);
      next.pending.single.complete({'image': pixel});
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      CustomerApi.sessionVersion++;
      await show(t, next, '/second');
      expect(find.byType(Image), findsNothing);
    },
  );
  testWidgets(
    'late old source failure does not clear new loading state or show error',
    (t) async {
      final api = ImageApi('owner');
      await show(t, api, '/first');
      await open(t);
      await show(t, api, '/second');
      await open(t);
      api.pending.first.completeError(StateError('TEST secret path'));
      await t.pump();
      expect(find.textContaining('TEST secret'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      api.pending.last.complete({'image': pixel});
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'invalid base64 is a recoverable failure and disposal ignores late errors',
    (t) async {
      final api = ImageApi('owner');
      await show(t, api, '/first');
      await open(t);
      api.pending.first.complete({'image': 'NOT BASE64!'});
      await t.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('Rasm ochilmadi'), findsOneWidget);
      await open(t);
      expect(api.calls.length, 2);
      await t.pumpWidget(const SizedBox());
      api.pending.last.completeError(StateError('TEST disposed'));
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'support and animal passport wrappers bind exact authenticated paths',
    (t) async {
      final api = ImageApi('owner');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SupportImage(api: api, path: '/support/TEST/messages/1/image'),
                BookingAnimalImage(
                  api: api,
                  bookingId: 'TEST',
                  petId: 'pet/a',
                  kind: 'passport',
                ),
              ],
            ),
          ),
        ),
      );
      final images = t
          .widgetList<PrivateApiImage>(find.byType(PrivateApiImage))
          .toList();
      expect(images.map((i) => i.path), [
        '/support/TEST/messages/1/image',
        '/bookings/TEST/pets/pet%2Fa/passport',
      ]);
      expect(images.every((i) => identical(i.api, api)), true);
      expect(api.calls, isEmpty);
    },
  );
}
