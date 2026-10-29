import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/auth/presentation/pages/phone_page.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

void main() {
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
        expect(find.textContaining('Server unavailable'), findsOneWidget);
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
