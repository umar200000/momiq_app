import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/care/presentation/booking_care_page.dart';
import 'booking_care_test.dart' show CareApi, reportValues;
import 'conversation_test.dart' show ChatDraft;

class RefreshCareApi extends CareApi {
  bool failOverview = false, malformed = false;
  @override
  Future<CareJson> request(String method, String path, [CareJson? body]) async {
    if (method == 'GET' && !path.contains('/history') && failOverview) {
      if (malformed) return {};
      throw StateError('TEST overview unavailable');
    }
    final result = await super.request(method, path, body);
    if (method == 'POST') failOverview = true;
    return result;
  }
}

void main() {
  test(
    'failed local cleanup retains the original request for an exact retry',
    () async {
      final api = RefreshCareApi();
      final storage = ChatDraft()..failClear = true;
      final c = BookingCareController(api, 'booking', storage: storage);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.save(reportValues()), false);
      final original = Map<String, dynamic>.of(storage.value!);
      expect(c.pending, original);
      expect(c.savedNeedsRefresh, false);
      storage.failClear = false;
      expect(await c.save({}), true);
      expect(c.savedNeedsRefresh, true);
      expect(api.posts, [original, original]);
      expect(api.saved, hasLength(1));
      expect(storage.value, isNull);
    },
  );
  for (final malformed in [false, true]) {
    test(
      'confirmed report survives ${malformed ? 'malformed' : 'offline'} overview without a new POST',
      () async {
        final api = RefreshCareApi()..malformed = malformed;
        final storage = ChatDraft();
        final c = BookingCareController(api, 'booking', storage: storage);
        addTearDown(c.dispose);
        await c.load();
        await c.loadHistory();
        expect(c.historyLoaded, true);
        expect(await c.save(reportValues()), true);
        expect(c.pending, isNull);
        expect(storage.value, isNull);
        expect(c.historyLoaded, false);
        expect(c.error, isNotNull);
        await c.loadHistory();
        expect(await c.save(reportValues()), false);
        expect(api.posts, hasLength(1));
        api.failOverview = false;
        await c.load();
        expect(c.error, isNull);
        expect(c.data!['pets'][0]['reports'][0]['revision'], 1);
        expect(api.posts, hasLength(1));
      },
    );
  }

  for (final entry in {
    'uz': ['Yozuv saqlandi.', 'Yangilash'],
    'en': ['The entry was saved.', 'Refresh'],
    'ru': ['Запись сохранена.', 'Обновить'],
  }.entries) {
    testWidgets(
      'confirmed save with failed refresh has an accurate message in ${entry.key}',
      (t) async {
        AppLanguage.current.value = entry.key;
        addTearDown(() => AppLanguage.current.value = 'uz');
        final api = RefreshCareApi();
        final c = BookingCareController(api, 'booking', storage: ChatDraft());
        addTearDown(c.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: BookingCarePage(
              api: api,
              bookingId: 'booking',
              controller: c,
            ),
          ),
        );
        await t.pumpAndSettle();
        await c.save(reportValues());
        await t.pumpAndSettle();
        expect(find.textContaining(entry.value.first), findsOneWidget);
        expect(find.byKey(const ValueKey('careRetry')), findsNothing);
        final report = find.byKey(const ValueKey('careReport-cat-food'));
        await t.scrollUntilVisible(
          report,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(t.widget<IconButton>(report).onPressed, isNull);
        api.failOverview = false;
        await t.tap(find.byTooltip(entry.value.last));
        await t.pumpAndSettle();
        expect(find.textContaining(entry.value.first), findsNothing);
        expect(api.posts, hasLength(1));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
