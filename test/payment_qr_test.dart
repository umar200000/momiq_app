import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:momiq_app/features/wallet/presentation/payment_qr.dart';
import 'package:momiq_app/features/wallet/data/receipt_image.dart';
import 'wallet_test.dart' show png;

void main() {
  testWidgets(
    'changing the recipient closes its enlarged QR and ignores a late save',
    (t) async {
      final gate = Completer<void>();
      Widget page(int version) => MaterialApp(
        home: Scaffold(
          body: PaymentQr(
            bytes: base64Decode(png),
            version: version,
            recipient: 'TEST recipient $version',
            testOnly: true,
            saveImage: (_, _) => gate.future,
          ),
        ),
      );
      await t.pumpWidget(page(1));
      await t.tap(find.byKey(const ValueKey('savePaymentQr')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('enlargePaymentQr')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      expect(find.text('Paynet Xolis · QR v1'), findsOneWidget);
      await t.pumpWidget(page(2));
      await t.pumpAndSettle();
      gate.complete();
      await t.pumpAndSettle();
      expect(find.text('Paynet Xolis · QR v1'), findsNothing);
      expect(find.byKey(const ValueKey('qrSaveResult')), findsNothing);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const ValueKey('savePaymentQr')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'save waits for the gallery, prevents double tap and retains QR version',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentQr(
              bytes: base64Decode(png),
              version: 3,
              recipient: 'TEST recipient',
              testOnly: true,
              saveImage: (bytes, name) {
                calls++;
                expect(name, 'TEST-Momiq-QR-v3');
                expect(bytes, base64Decode(png));
                return gate.future;
              },
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('savePaymentQr'));
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      expect(find.byKey(const ValueKey('qrSaveResult')), findsNothing);
      expect(calls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('QR galereyaga saqlandi.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    },
  );

  testWidgets('permission denial does not report saved and can retry', (
    tester,
  ) async {
    var denied = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentQr(
            bytes: base64Decode(png),
            version: 3,
            recipient: 'TEST recipient',
            testOnly: true,
            saveImage: (_, _) async {
              if (denied) {
                throw GalException(
                  type: GalExceptionType.accessDenied,
                  platformException: PlatformException(code: 'ACCESS_DENIED'),
                  stackTrace: StackTrace.current,
                );
              }
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('savePaymentQr')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ruxsati berilmadi.'), findsOneWidget);
    expect(find.textContaining('QR galereyaga saqlandi.'), findsNothing);
    denied = false;
    await tester.tap(find.byKey(const ValueKey('savePaymentQr')));
    await tester.pumpAndSettle();
    expect(find.textContaining('QR galereyaga saqlandi.'), findsOneWidget);
  });

  testWidgets('enlarged QR preserves recipient, test warning and pinch zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaymentQr(
            bytes: base64Decode(png),
            version: 3,
            recipient: 'TEST recipient',
            testOnly: true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('enlargePaymentQr')));
    await tester.pumpAndSettle();
    expect(find.text('Paynet Xolis · QR v3'), findsOneWidget);
    expect(find.text('TEST recipient'), findsOneWidget);
    expect(find.text('TEST — haqiqiy to‘lov qilmang'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  test(
    'invalid and oversized evidence is rejected before draft storage',
    () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List(3 * 1024 * 1024 + 1),
        Uint8List.fromList('not an image'.codeUnits),
        Uint8List.fromList([137, 80, 78, 71, 0, 0, 0, 0]),
      ]) {
        await expectLater(validateReceiptImage(bytes), throwsA(anything));
      }
      await validateReceiptImage(base64Decode(png));
    },
  );
}
