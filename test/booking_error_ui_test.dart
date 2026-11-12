import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/bookings/data/booking_controller.dart';
import 'booking_primary_source_test.dart' show SourceApi, flowPage;
import 'booking_controller_test.dart' show BookingMemory;

class BrokenBookingApi extends SourceApi {
  BrokenBookingApi() : super('TEST sitter');
  bool brokenInbox = false;
  int chatAttempts = 0;
  @override
  Future<BookingJson> request(
    String method,
    String path, [
    BookingJson? body,
  ]) async {
    if (path.endsWith('/conversation')) {
      chatAttempts++;
      throw const FormatException('PRIVATE parser detail', 'PRIVATE response');
    }
    if ((path == '/bookings' || path.contains('/conversations/')) &&
        brokenInbox) {
      throw const FormatException('PRIVATE parser detail', 'PRIVATE response');
    }
    return super.request(method, path, body);
  }
}

void main() {
  tearDown(() => AppLanguage.current.value = 'uz');
  for (final language in ['uz', 'en', 'ru']) {
    final inboxError = switch (language) {
      'uz' => 'Buyurtmalarni yuklab bo‘lmadi. Qayta urinib ko‘ring.',
      'en' => 'Could not load bookings. Please retry.',
      _ => 'Не удалось загрузить заказы. Повторите попытку.',
    };
    final chatError = switch (language) {
      'uz' => 'Buyurtma suhbatini ochib bo‘lmadi. Qayta urinib ko‘ring.',
      'en' => 'Could not open the booking chat. Please retry.',
      _ => 'Не удалось открыть переписку по заказу. Повторите попытку.',
    };
    Future<void> mount(WidgetTester t, Widget page) async {
      AppLanguage.current.value = language;
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('uz'), Locale('en'), Locale('ru')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: page,
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets(
      'inbox $language error hides private payload and refresh recovers',
      (t) async {
        final api = BrokenBookingApi()..brokenInbox = true;
        await mount(t, flowPage('inbox', api, '', null));
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.text(inboxError), findsOneWidget);
        api.brokenInbox = false;
        final refresh = find.widgetWithIcon(TextButton, Icons.refresh);
        await t.ensureVisible(refresh);
        await t.tap(refresh);
        await t.pumpAndSettle();
        expect(find.text(inboxError), findsNothing);
        expect(find.byKey(ValueKey('booking-${'a' * 32}')), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'booking chat $language error hides private payload and allows retry',
      (t) async {
        final api = BrokenBookingApi();
        final c = BookingController(api, 'a' * 32, storage: BookingMemory());
        addTearDown(c.dispose);
        await mount(t, flowPage('detail', api, 'a' * 32, c));
        final chat = find.byKey(const ValueKey('bookingConversation'));
        await t.scrollUntilVisible(
          chat,
          200,
          maxScrolls: 40,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(t.element(chat), alignment: 0.5);
        await t.pumpAndSettle();
        await t.tap(chat);
        await t.pumpAndSettle();
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.text(chatError), findsOneWidget);
        expect(api.chatAttempts, 1);
        await t.pump(const Duration(seconds: 5));
        await t.pumpAndSettle();
        await t.ensureVisible(chat);
        await t.tap(chat);
        await t.pumpAndSettle();
        expect(api.chatAttempts, 2);
        expect(t.takeException(), isNull);
      },
    );
  }
}
