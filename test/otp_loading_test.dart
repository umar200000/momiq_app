import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/auth/presentation/pages/phone_page.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/core/localization/app_language.dart';

void main() {
  for (final (language, network, denied) in [
    (
      'uz',
      'Backendga ulanib bo‘lmadi. Internet ulanishini tekshiring.',
      'Telefon raqami yoki kod noto‘g‘ri.',
    ),
    (
      'en',
      'Could not reach Momiq. Check your internet connection.',
      'Incorrect phone number or code.',
    ),
    (
      'ru',
      'Не удалось подключиться к Momiq. Проверьте подключение к интернету.',
      'Неверный номер телефона или код.',
    ),
  ]) {
    testWidgets(
      '$language sign-in distinguishes a network error from an incorrect code',
      (tester) async {
        AppLanguage.current.value = language;
        addTearDown(() => AppLanguage.current.value = 'uz');
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: OtpPage(
              phone: '998000000000',
              authenticate: (_, _, _) async {
                calls++;
                if (calls == 1) {
                  throw CustomerApiException(
                    'Backendga ulanib bo‘lmadi. Internet ulanishini tekshiring.',
                  );
                }
                throw CustomerApiException('internal diagnostic', 401);
              },
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('otpInput')),
          '111111',
        );
        await tester.pump();
        await tester.pump();
        await tester.ensureVisible(find.text(network));
        expect(
          tester
              .widgetList<Semantics>(
                find.ancestor(
                  of: find.text(network),
                  matching: find.byType(Semantics),
                ),
              )
              .any((widget) => widget.properties.liveRegion == true),
          isTrue,
        );
        final button = find.byKey(const ValueKey('verifyOtp'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump();
        expect(find.text(denied), findsOneWidget);
        expect(calls, 2);
        expect(find.textContaining('internal diagnostic'), findsNothing);

        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final replaceIdentity in [false, true]) {
    testWidgets(
      'verified OTP timer ignores replacement session, identity=$replaceIdentity',
      (tester) async {
        CustomerApi.active = CustomerApi('TEST-old', 'old');
        addTearDown(() => CustomerApi.active = null);
        final response = Completer<Map<String, dynamic>>();
        await tester.pumpWidget(
          MaterialApp(
            home: OtpPage(
              phone: '998000000000',
              customer: true,
              authenticate: (_, _, _) => response.future,
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('otpInput')),
          '111111',
        );
        await tester.pump();
        response.complete({
          'profile': {'first': '', 'last': ''},
        });
        await tester.pump();
        await tester.pump();
        if (replaceIdentity) {
          CustomerApi.active = CustomerApi('TEST-new', 'new');
        } else {
          CustomerApi.sessionVersion++;
        }
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(OtpPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final customer in [true, false]) {
    testWidgets(
      'OTP shows pending request and unlocks on failure, customer=$customer',
      (tester) async {
        final response = Completer<Map<String, dynamic>>();
        var requests = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: OtpPage(
              phone: '+998 90 123 45 67',
              customer: customer,
              authenticate: (phone, code, role) {
                expect(code, '111111');
                expect(role, customer);
                requests++;
                return response.future;
              },
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('otpInput')),
          '111111',
        );
        await tester.pump();
        final verify = find.byKey(const ValueKey('verifyOtp'));
        expect(
          find.descendant(
            of: verify,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('otpInput')))
              .readOnly,
          true,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: verify,
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.pump(const Duration(seconds: 21));
        expect(
          tester
              .widget<OutlinedButton>(
                find.descendant(
                  of: find.byKey(const ValueKey('resendCode')),
                  matching: find.byType(OutlinedButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(requests, 1);
        response.completeError(Exception('Server unavailable'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.text('Kirishni tasdiqlab bo‘lmadi. Qayta urinib ko‘ring.'),
          findsOneWidget,
        );
        expect(find.textContaining('Server unavailable'), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('otpInput')))
              .readOnly,
          false,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: verify,
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
