import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/wallet/presentation/wallet_page.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/wallet/data/wallet_snapshot.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'wallet_test.dart' show MemoryDraft, WalletApi, png;

class SnapshotApi extends WalletApi {
  String? failure;
  bool broken = true;
  bool repeatedPage = true;
  bool pagination = false;
  final cursors = <String>[];
  Map<String, dynamic> row(int id) => {
    'id': id.toRadixString(16).padLeft(32, '0'),
    'amountMinor': 100,
    'status': 'pending',
    'revision': 0,
    'created': '2026-11-07T00:00:00Z',
    'reviewReason': null,
  };
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/wallet' && failure != null) {
      throw CustomerApiException(failure!);
    }
    if (pagination && path.startsWith('/wallet/topups')) {
      if (!path.contains('?')) {
        return {
          'topups': [for (var i = 20; i > 0; i--) row(i)],
          'nextCursor': row(1)['id'],
        };
      }
      cursors.add(path);
      return {
        'topups': [row(repeatedPage ? 1 : 0)],
        'nextCursor': null,
      };
    }
    final data = await super.request(method, path, body);
    if (path == '/wallet' && broken) data['balanceMinor'] = 'unknown';
    return data;
  }
}

void main() {
  testWidgets(
    'corrupt saved payment remains untouched and cannot become a new payment',
    (t) async {
      for (final bad in ['config', 'pending flag', 'request ID']) {
        final api = WalletApi();
        final config = (await api.request('GET', '/wallet'))['config'];
        final data = <String, dynamic>{
          'formatVersion': 1,
          'amount': '1',
          'receipt': png,
          'requestId': 'TEST-stable',
          'submissionPending': true,
          'config': config,
        };
        if (bad == 'config') config['qrImage'] = 123;
        if (bad == 'pending flag') data['submissionPending'] = 'true';
        if (bad == 'request ID') data['requestId'] = '';
        final draft = MemoryDraft()..data = data;
        await t.pumpWidget(
          MaterialApp(
            home: WalletPage(api: api, draftStorage: draft),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: bad);
        expect(
          find.byKey(const ValueKey('submitTopup')),
          findsNothing,
          reason: bad,
        );
        expect(
          find.textContaining('avtomatik o‘chirilmagan'),
          findsOneWidget,
          reason: bad,
        );
        expect(draft.data, same(data), reason: bad);
        expect(api.sent, isEmpty);
      }
    },
  );
  for (final language in ['uz', 'en', 'ru']) {
    testWidgets('wallet network errors use the selected $language language', (
      t,
    ) async {
      AppLanguage.current.value = language;
      addTearDown(() => AppLanguage.current.value = 'uz');
      for (final words in [
        [
          'Backendga ulanib bo‘lmadi. Internet ulanishini tekshiring.',
          'Could not reach Momiq. Check your internet connection.',
          'Не удалось подключиться к Momiq. Проверьте подключение к интернету.',
        ],
        [
          'Server bilan aloqa uzildi. Qayta urinib ko‘ring.',
          'The connection was interrupted. Please try again.',
          'Связь с сервером прервалась. Попробуйте ещё раз.',
        ],
        [
          'Server javob bermadi. Qayta urinib ko‘ring.',
          'The server did not respond. Please try again.',
          'Сервер не ответил. Попробуйте ещё раз.',
        ],
      ]) {
        final api = SnapshotApi()..failure = words[0];
        await t.pumpWidget(
          MaterialApp(
            home: WalletPage(api: api, draftStorage: MemoryDraft()),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.text(words[['uz', 'en', 'ru'].indexOf(language)]),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        expect(api.sent, isEmpty);
      }
    });
    testWidgets(
      'wallet error retry stays reachable at 320px and 2x with keyboard in $language',
      (t) async {
        AppLanguage.current.value = language;
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(() {
          t.view.reset();
          AppLanguage.current.value = 'uz';
        });
        final api = SnapshotApi();
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 240),
              ),
              child: child!,
            ),
            home: WalletPage(api: api, draftStorage: MemoryDraft()),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final retry = find.text(
          {'uz': 'Qayta urinish', 'en': 'Retry', 'ru': 'Повторить'}[language]!,
        );
        await t.ensureVisible(retry);
        await t.tap(retry);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(retry, findsOneWidget);
        expect(api.sent, isEmpty);
      },
    );
  }

  test(
    'financial snapshot rejects invalid money, config and ledger before publication',
    () async {
      final api = WalletApi();
      final valid = await api.request('GET', '/wallet');
      expect(walletSnapshot(valid)['balanceMinor'], 0);
      for (final patch in <Map<String, dynamic>>[
        {'balanceMinor': -1},
        {'balanceMinor': 1.5},
        {'currency': 'USD'},
        {'balanceEligible': true},
        {'minimumBalanceMinor': 1},
        {'entries': null},
        {
          'entries': [null],
        },
      ]) {
        expect(
          () => walletSnapshot({...valid, ...patch}),
          throwsFormatException,
        );
      }
      for (final patch in <Map<String, dynamic>>[
        {'version': 0},
        {'commissionBps': 10001},
        {'minimumBalanceMinor': -1},
        {'qrActive': 'true'},
        {'testOnly': null},
        {'qrImage': '!invalid'},
        {'qrImage': null},
        {'recipientName': ''},
        {'termsVersion': 'unknown'},
        {'unusedBalanceRefundable': true},
        {'paymentInstructions': []},
      ]) {
        expect(
          () => walletSnapshot({
            ...valid,
            'config': {...valid['config'], ...patch},
          }),
          throwsFormatException,
        );
      }
      final ledger = {
        'id': 'a' * 32,
        'amountMinor': 100,
        'balanceAfter': 100,
        'kind': 'topup',
        'reason': 'TEST credit',
        'created': '2026-11-07T00:00:00Z',
        'topupId': null,
      };
      expect(
        walletSnapshot({
          ...valid,
          'balanceMinor': 100,
          'entries': [ledger],
        })['entries'],
        [ledger],
      );
      for (final patch in <Map<String, dynamic>>[
        {'amountMinor': '100'},
        {'reason': null},
        {'balanceAfter': -1},
        {'id': '../other'},
        {'topupId': '../other'},
        {'created': 'not a date'},
      ]) {
        expect(
          () => walletSnapshot({
            ...valid,
            'entries': [
              {...ledger, ...patch},
            ],
          }),
          throwsFormatException,
        );
      }
      expect(
        () => walletSnapshot({
          ...valid,
          'entries': [ledger, ledger],
        }),
        throwsFormatException,
      );
    },
  );

  test('topup pages reject partial, unordered and non-advancing histories', () {
    final api = SnapshotApi();
    final first = [for (var i = 20; i > 0; i--) api.row(i)];
    final cursor = first.last['id'] as String;
    final page = walletTopupPage({'topups': first, 'nextCursor': cursor});
    expect(page['topups'], first);
    for (final malformed in <Map<String, dynamic>>[
      {
        'topups': [api.row(0), null],
      },
      {
        'topups': [api.row(0), api.row(0)],
      },
      {
        'topups': [api.row(22)],
      },
      {
        'topups': [api.row(0)],
        'nextCursor': cursor,
      },
      {'topups': [], 'nextCursor': 'f' * 32},
      {
        'topups': [
          {...api.row(0), 'status': 'credited'},
        ],
      },
      {
        'topups': [
          {...api.row(0), 'amountMinor': 0},
        ],
      },
      {
        'topups': [
          {...api.row(0), 'created': 'yesterday'},
        ],
      },
    ]) {
      expect(
        () => walletTopupPage(malformed, previous: first, cursor: cursor),
        throwsFormatException,
      );
      expect(first.length, 20);
      expect(page['nextCursor'], cursor);
    }
    expect(
      walletTopupPage(
        {
          'topups': [api.row(0)],
        },
        previous: first,
        cursor: cursor,
      )['nextCursor'],
      isNull,
    );
  });
  testWidgets(
    'malformed wallet is retryable without rendering a balance or offering payment',
    (t) async {
      final api = SnapshotApi();
      final draft = MemoryDraft();
      await t.pumpWidget(
        MaterialApp(
          home: WalletPage(api: api, draftStorage: draft),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('walletBalance')), findsNothing);
      expect(find.byKey(const ValueKey('startTopup')), findsNothing);
      expect(find.text('Qayta urinish'), findsOneWidget);
      expect(draft.data, isNull);
      api.broken = false;
      await t.tap(find.text('Qayta urinish'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('walletBalance')), findsOneWidget);
      expect(find.byKey(const ValueKey('startTopup')), findsOneWidget);
      expect(api.sent, isEmpty);
    },
  );

  testWidgets(
    'repeated topup page keeps the cursor and previous rows for a valid retry',
    (t) async {
      final api = SnapshotApi()
        ..broken = false
        ..pagination = true;
      await t.pumpWidget(
        MaterialApp(
          home: WalletPage(api: api, draftStorage: MemoryDraft()),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Yana yuklash'), 400);
      await t.tap(find.text('Yana yuklash'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Yana yuklash'), findsOneWidget);
      api.repeatedPage = false;
      await t.tap(find.text('Yana yuklash'));
      await t.pumpAndSettle();
      expect(api.cursors.length, 2);
      expect(api.cursors.last, api.cursors.first);
      expect(find.text('Yana yuklash'), findsNothing);
      expect(api.sent, isEmpty);
    },
  );
}
