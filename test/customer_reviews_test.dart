import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
import 'package:momiq_app/features/customer/presentation/customer_reviews.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

class PublicReviewApi extends CustomerApi {
  PublicReviewApi() : super('', '');
  bool offline = false;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    paths.add(path);
    if (offline) throw StateError('Offline');
    Map<String, dynamic> item(String id) => {
      'id': id,
      'name': 'TEST customer',
      'stars': 5,
      'text': 'Review $id',
      'created': '2026-10-28T05:00:00Z',
      'testOnly': true,
    };
    return {
      'items': path.contains('?')
          ? [item('2'), item('1')]
          : [item('3'), item('2')],
      'nextCursor': path.contains('?') ? null : '2',
      'count': 0,
      'rating': 0,
    };
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'public pages deduplicate and TEST reviews do not invent aggregate',
    (t) async {
      final store = CustomerStore();
      await store.load();
      addTearDown(store.dispose);
      final api = PublicReviewApi();
      await t.pumpWidget(
        MaterialApp(
          home: CustomerSitterReviewsPage(
            store: store,
            sitter: {'id': 'sitter:boarding', 'name': 'TEST sitter'},
            api: api,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(api.paths.single, '/sitters/sitter%3Aboarding/reviews');
      expect(find.text('Haqiqiy sharhlar hali yo‘q.'), findsOneWidget);
      expect(find.text('TEST — reytingga qo‘shilmaydi'), findsNWidgets(2));
      await t.ensureVisible(find.text('Yana'));
      await t.tap(find.text('Yana'));
      await t.pumpAndSettle();
      expect(api.paths.last, endsWith('?before=2'));
      expect(find.byKey(const ValueKey('serverReview-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('serverReview-1')), findsOneWidget);
      expect(find.text('Yana'), findsNothing);
      expect(
        customerReviewSummary(store, {'reviews': 2, 'rating': 4.5}),
        '4.5 (2)',
      );
    },
  );
  testWidgets(
    'failed public fetch is not presented as an empty successful list',
    (t) async {
      final store = CustomerStore();
      await store.load();
      addTearDown(store.dispose);
      final api = PublicReviewApi()..offline = true;
      await t.pumpWidget(
        MaterialApp(
          home: CustomerSitterReviewsPage(
            store: store,
            sitter: {'id': 'sitter:boarding', 'name': 'TEST sitter'},
            api: api,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reviewLoadError')), findsOneWidget);
      expect(find.text('Hali sharh yo‘q'), findsNothing);
      api.offline = false;
      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reviewLoadError')), findsNothing);
      expect(find.byKey(const ValueKey('serverReview-3')), findsOneWidget);
    },
  );
  testWidgets('no invented review or rating when no reviews exist', (
    tester,
  ) async {
    final store = CustomerStore();
    await store.load();
    addTearDown(store.dispose);
    final sitter = <String, dynamic>{'id': 'actual', 'name': 'Account'};
    expect(customerReviewSummary(store, sitter), 'Hali sharh yo‘q');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerReviewsSection(store: store, sitter: sitter),
        ),
      ),
    );
    expect(find.text('Hali sharh yo‘q'), findsOneWidget);
    expect(find.text('Madina Karimova'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
