import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'listings persist across stores and failed server saves do not change state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      Map<String, dynamic> saved = {'housing': 'house', 'listings': []};
      var fail = false;
      server.listen((request) async {
        expect(request.uri.path, '/api/me/listings');
        expect(request.headers.value('authorization'), 'Bearer test-token');
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'PUT') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          if (fail) {
            request.response.statusCode = 500;
            request.response.write(jsonEncode({'error': 'Unavailable'}));
            await request.response.close();
            return;
          }
          saved = body;
        }
        request.response.write(jsonEncode(saved));
        await request.response.close();
      });
      final api = CustomerApi(
        'test-token',
        'test-user',
        baseUrl: 'http://127.0.0.1:${server.port}/api',
      );
      final store = ListingStore(api: api);
      await store.load();
      expect(store.housing, HousingType.house);
      final listing = ServiceListing(
        type: ServiceType.homeVisit,
        pets: {PetType.cat},
        dailyPrice: 50000,
      );
      await store.save(listing);
      expect((saved['listings'] as List).single['price'], 50000);
      final restored = ListingStore(api: api);
      await restored.load();
      expect(restored[ServiceType.homeVisit]?.dailyPrice, 50000);
      fail = true;
      await expectLater(
        restored.setActive(ServiceType.homeVisit, false),
        throwsA(isA<CustomerApiException>()),
      );
      expect(restored[ServiceType.homeVisit]?.active, true);
    },
  );
}
