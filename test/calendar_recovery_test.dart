import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/widgets/owned_dialogs.dart';
import 'package:momiq_app/features/bookings/data/booking_composer.dart';
import 'package:momiq_app/features/bookings/presentation/booking_request_page.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/wallet/presentation/wallet_page.dart';
import 'booking_composer_test.dart' show ComposerApi, formFields;
import 'booking_controller_test.dart' show BookingMemory;
import 'wallet_test.dart' show MemoryDraft, WalletApi;

class CalendarHost extends StatefulWidget {
  const CalendarHost({super.key, required this.date});
  final DateTime date;
  @override
  State<CalendarHost> createState() => CalendarHostState();
}

class CalendarHostState extends State<CalendarHost>
    with OwnedDialogs<CalendarHost> {
  DateTime? confirmed;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () async {
        final value = await showOwnedDatePicker(
          initialDate: widget.date,
          firstDate: DateTime(2026, 1, 1),
          lastDate: DateTime(2026, 12, 31),
        );
        if (mounted && value != null) setState(() => confirmed = value);
      },
      child: const Text('Open calendar'),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final dates in [
    (DateTime(1990), DateTime(2026)),
    (DateTime(2040), DateTime(2026, 12, 31)),
    (DateTime.utc(2026, 12, 31, 23), DateTime(2026, 12, 31)),
    (DateTime(2026, 6, 15, 17), DateTime(2026, 6, 15)),
  ]) {
    final (date, expected) = dates;
    for (final language in ['uz', 'en', 'ru']) {
      testWidgets(
        'calendar recovers $date in $language without changing saved date',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final key = GlobalKey<CalendarHostState>();
          await t.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [
                Locale('uz'),
                Locale('en'),
                Locale('ru'),
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: CalendarHost(key: key, date: date),
            ),
          );
          await t.tap(find.text('Open calendar'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final picker = t.widget<DatePickerDialog>(
            find.byType(DatePickerDialog),
          );
          expect(picker.initialDate, expected);
          expect(key.currentState!.confirmed, isNull);
          final context = t.element(find.byType(DatePickerDialog));
          final cancel = MaterialLocalizations.of(context).cancelButtonLabel;
          await t.tap(find.text(cancel));
          await t.pumpAndSettle();
          expect(key.currentState!.confirmed, isNull);
          expect(key.currentState!.widget.date, date);
          await t.tap(find.text('Open calendar'));
          await t.pumpAndSettle();
          final ok = MaterialLocalizations.of(
            t.element(find.byType(DatePickerDialog)),
          ).okButtonLabel;
          await t.tap(find.text(ok));
          await t.pumpAndSettle();
          expect(key.currentState!.confirmed, expected);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final paidAt in ['1990-01-01T00:00:00Z', '2040-01-01T00:00:00Z']) {
    testWidgets(
      'receipt calendar can correct saved $paidAt without sending payment',
      (t) async {
        final api = WalletApi();
        final draft = MemoryDraft()
          ..data = {
            'formatVersion': 1,
            'amount': '100',
            'paidAt': paidAt,
            'config': (await api.request('GET', '/wallet'))['config'],
          };
        await t.pumpWidget(
          MaterialApp(
            home: WalletPage(api: api, draftStorage: draft),
          ),
        );
        await t.pumpAndSettle();
        final button = find.byKey(const ValueKey('topupPaidAt'));
        await t.scrollUntilVisible(
          button,
          200,
          maxScrolls: 30,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(button);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(DateTime.parse(draft.data!['paidAt']), DateTime.parse(paidAt));
        expect(api.sent, isEmpty);
      },
    );
  }
  testWidgets(
    'saved future booking date opens for correction and cancel retains draft',
    (t) async {
      final api = ComposerApi();
      final store = CustomerStore()..api = api;
      final future = DateTime.utc(DateTime.now().year + 4, 1, 1);
      final memory = BookingMemory()
        ..value = {
          'draft': {
            ...formFields(),
            'startsAt': future.toIso8601String(),
            'endsAt': future.add(const Duration(days: 1)).toIso8601String(),
          },
          'quote': null,
          'pending': null,
        };
      final composer = BookingComposer(api, 'sitter:boarding', storage: memory);
      addTearDown(store.dispose);
      addTearDown(composer.dispose);
      await store.load();
      await t.pumpWidget(
        MaterialApp(
          home: BookingRequestPage(
            store: store,
            composer: composer,
            sitter: {
              'id': 'sitter:boarding',
              'name': 'TEST',
              'service': 0,
              'pets': ['Mushuk'],
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final next = find.byKey(const ValueKey('submitBookingStep'));
      await t.scrollUntilVisible(next, 200);
      await t.tap(next);
      await t.pumpAndSettle();
      final button = find.byKey(const ValueKey('bookingStart'));
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(DateTime.parse(memory.value!['draft']['startsAt']), future);
      expect(api.quoteCount, 0);
      expect(api.submissions, isEmpty);
    },
  );
}
