import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';

class DelayedListingApi extends CustomerApi {
  DelayedListingApi(this.housing) : super('test-token', 'test-user');
  final String housing;
  Completer<void>? readGate, writeGate;
  int reads = 0, writes = 0;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (method == 'GET') {
      reads++;
      await readGate?.future;
    } else {
      writes++;
      await writeGate?.future;
    }
    return {'housing': housing, 'listings': [], '_revision': 1};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
    CustomerApi.sessionVersion = 0;
  });

  test(
    'reset invalidates a read without clearing the replacement in-flight load',
    () async {
      final old = DelayedListingApi('house')..readGate = Completer<void>();
      final store = ListingStore(api: old);
      addTearDown(store.dispose);
      final first = store.load();
      final rejected = expectLater(first, throwsA(isA<ListingException>()));
      await Future<void>.delayed(Duration.zero);
      store.resetSession();
      final replacement = DelayedListingApi('apartment')
        ..readGate = Completer<void>();
      store.api = replacement;
      final second = store.load();
      old.readGate!.complete();
      await rejected;
      expect(identical(store.load(), second), isTrue);
      replacement.readGate!.complete();
      await second;
      expect(store.housing, HousingType.apartment);
      expect(replacement.reads, 1);
    },
  );

  test('a stale preference read cannot bind or write a new session', () async {
    final prefs = await SharedPreferences.getInstance();
    final gate = Completer<SharedPreferences>();
    final api = DelayedListingApi('house');
    final store = ListingStore(api: api, preferences: () => gate.future);
    addTearDown(store.dispose);
    final saving = store.setHousing(HousingType.house);
    final rejected = expectLater(saving, throwsA(isA<ListingException>()));
    CustomerApi.sessionVersion++;
    gate.complete(prefs);
    await rejected;
    expect(api.reads, 0);
    expect(api.writes, 0);
    expect(store.housing, HousingType.apartment);
    await expectLater(
      store.setHousing(HousingType.house),
      throwsA(isA<ListingException>()),
    );
  });

  test('old mutation finally cannot clear replacement busy state', () async {
    final old = DelayedListingApi('house');
    final store = ListingStore(api: old);
    addTearDown(store.dispose);
    await store.load();
    old.writeGate = Completer<void>();
    final first = store.setHousing(HousingType.house);
    final rejected = expectLater(first, throwsA(isA<ListingException>()));
    await Future<void>.delayed(Duration.zero);
    store.resetSession();
    final replacement = DelayedListingApi('apartment')
      ..writeGate = Completer<void>();
    store.api = replacement;
    await store.load();
    final second = store.setHousing(HousingType.apartment);
    await Future<void>.delayed(Duration.zero);
    expect(store.busy, isTrue);
    old.writeGate!.complete();
    await rejected;
    expect(store.busy, isTrue);
    expect(store.housing, HousingType.apartment);
    replacement.writeGate!.complete();
    await second;
    expect(store.busy, isFalse);
  });

  test('disposed listing load never publishes a result', () async {
    final api = DelayedListingApi('house')..readGate = Completer<void>();
    final store = ListingStore(api: api);
    var notifications = 0;
    store.addListener(() => notifications++);
    final loading = store.load();
    final rejected = expectLater(loading, throwsA(isA<ListingException>()));
    await Future<void>.delayed(Duration.zero);
    store.dispose();
    api.readGate!.complete();
    await rejected;
    expect(notifications, 0);
  });
}
