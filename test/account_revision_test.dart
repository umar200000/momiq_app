import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';

class RevisionApi extends CustomerApi {
  RevisionApi() : super('test', 'user');
  int version = 1;
  int writes = 0;
  Map<String, dynamic>? received;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/messages') return {'messages': []};
    if (method == 'PUT') {
      writes++;
      received = body;
      version++;
    }
    return {
      'account': {
        '_revision': version,
        'profile': {'first': 'Original', 'last': 'Name', 'photo': null},
        'favorites': [],
        'addresses': [],
        'pets': [],
        'support': [],
        'notifications': {'orders': true, 'chat': true, 'video': true},
        'language': 'uz',
        'sitterProfile': null,
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
  });
  test(
    'polling does not let an old edit form overwrite a newer account',
    () async {
      final api = RevisionApi();
      final store = CustomerStore()..api = api;
      addTearDown(store.dispose);
      await store.load();
      final formVersion = store.revision;
      api.version = 2;
      await store.refreshRemote();
      await expectLater(
        store.update(
          (d) => d['profile']['first'] = 'Stale',
          expectedRevision: formVersion,
        ),
        throwsA(isA<CustomerApiException>()),
      );
      expect(api.writes, 0);
      expect(store.profile['first'], 'Original');
      await store.update(
        (d) => d['language'] = 'en',
        expectedRevision: store.revision,
      );
      expect(api.received!['_revision'], 2);
      expect(store.revision, 3);
    },
  );
}
