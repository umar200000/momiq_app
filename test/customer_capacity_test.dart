import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('unsupported bookings never create a local success or order', () async {
    final store = CustomerStore();
    await store.load();
    addTearDown(store.dispose);
    await expectLater(
      store.book(
        sitterId: 'missing',
        from: DateTime.now(),
        to: DateTime.now(),
        address: {},
      ),
      throwsStateError,
    );
    expect(store.list('bookings'), isEmpty);
    await expectLater(store.cancel('missing', 'cancel'), throwsStateError);
  });
  test(
    'capacity uses supplied data, never a simulated future opening',
    () async {
      final store = CustomerStore();
      await store.load();
      addTearDown(store.dispose);
      final sitter = <String, dynamic>{
        'id': 'actual',
        'service': 0,
        'capacity': 3,
        'occupied': 2,
      };
      expect(store.availablePlaces(sitter), 1);
      expect(
        store.availablePlaces(
          sitter,
          from: DateTime.now().add(const Duration(days: 10)),
        ),
        1,
      );
    },
  );
}
