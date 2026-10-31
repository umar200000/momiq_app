import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/wallet/presentation/topup_history_page.dart';

class HistoryApi extends CustomerApi {
  HistoryApi() : super('test', 'owner');
  final calls = <String>[];
  bool receiptFails = true;
  String currentStatus = 'needs_info';
  bool correctionsFail = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add(path);
    if (path.contains('/corrections')) {
      if (correctionsFail) throw CustomerApiException('Offline');
      final more = path.contains('?');
      return {
        'items': [
          {
            'id': more
                ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'amountMinor': more ? 50 : 100,
            'reason': more ? 'TEST older correction' : 'TEST correction reason',
            'created': '2026-10-29T05:00:00Z',
          },
        ],
        'nextCursor': more ? null : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'correctedMinor': 150,
      };
    }
    if (path.endsWith('/receipt')) {
      if (receiptFails) throw CustomerApiException('Offline');
      return {
        'receipt':
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      };
    }
    final more = path.contains('?');
    return {
      'items': [
        {
          'revision': more ? 0 : 1,
          'event': more ? 'created' : 'request_info',
          'status': more ? 'pending' : currentStatus,
          'amountMinor': 1500001,
          'qrVersion': 2,
          'reason': 'TEST',
          'payerReference': 'TEST-001',
          'created': '2026-10-27T10:00:00Z',
        },
      ],
      'nextCursor': more ? null : '1',
    };
  }
}

void main() {
  testWidgets('correction history is private, lazy, retryable and paginated', (
    t,
  ) async {
    final api = HistoryApi()
      ..currentStatus = 'approved'
      ..correctionsFail = true;
    await t.pumpWidget(
      MaterialApp(
        home: TopupHistoryPage(api: api, topupId: 'test'),
      ),
    );
    await t.pumpAndSettle();
    expect(api.calls.where((p) => p.contains('/corrections')), isEmpty);
    await t.tap(find.byKey(const ValueKey('topupCorrections')));
    await t.pumpAndSettle();
    expect(find.textContaining('Tuzatishlar yuklanmadi'), findsOneWidget);
    api.correctionsFail = false;
    await t.tap(find.byKey(const ValueKey('topupCorrections')));
    await t.pumpAndSettle();
    expect(find.textContaining('TEST correction reason'), findsOneWidget);
    expect(find.textContaining('kartaga pul qaytarish emas'), findsOneWidget);
    expect(find.textContaining('1.50 UZS'), findsOneWidget);
    await t.tap(find.text('Oldingi tuzatishlar'));
    await t.pumpAndSettle();
    expect(
      api.calls,
      contains(
        '/wallet/topups/test/corrections?before=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    );
    expect(find.textContaining('TEST older correction'), findsOneWidget);
    expect(find.text('Oldingi tuzatishlar'), findsNothing);
  });
  testWidgets(
    'history paginates without bulk receipts and can retry a failed receipt',
    (t) async {
      final api = HistoryApi();
      await t.pumpWidget(
        MaterialApp(
          home: TopupHistoryPage(api: api, topupId: 'test'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('15000.01 UZS'), findsOneWidget);
      expect(api.calls.where((p) => p.endsWith('/receipt')), isEmpty);
      expect(find.byKey(const ValueKey('amendHistoryTopup')), findsOneWidget);
      await t.tap(find.text('Yana yuklash'));
      await t.pumpAndSettle();
      expect(api.calls, contains('/wallet/topups/test/history?before=1'));
      expect(find.textContaining('Yuborilgan'), findsOneWidget);
      expect(find.byKey(const ValueKey('amendHistoryTopup')), findsOneWidget);
      await t.tap(find.text('Shu bosqichdagi chek').first);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      api.receiptFails = false;
      await t.tap(find.text('Shu bosqichdagi chek').first);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Chekning v1 nusxasi'), findsOneWidget);
    },
  );
  testWidgets('approved history does not offer an amendment', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: TopupHistoryPage(
          api: HistoryApi()..currentStatus = 'approved',
          topupId: 'test',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('amendHistoryTopup')), findsNothing);
  });
}
