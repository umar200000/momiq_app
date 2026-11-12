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
      Map<String, dynamic> saved = {
        'housing': 'house',
        'listings': [],
        '_revision': 4,
      };
      var fail = false;
      var failureStatus = 500;
      server.listen((request) async {
        expect(
          request.uri.path,
          request.method == 'POST'
              ? '/api/me/listings/homeVisit/archive'
              : '/api/me/listings',
        );
        expect(request.headers.value('authorization'), 'Bearer test-token');
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'PUT' || request.method == 'POST') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          if (fail) {
            request.response.statusCode = failureStatus;
            request.response.write(
              jsonEncode({
                'error': failureStatus == 409
                    ? 'Existing care prevents housing change'
                    : 'Unavailable',
              }),
            );
            await request.response.close();
            return;
          }
          if (body['_revision'] != saved['_revision']) {
            request.response.statusCode = 409;
            request.response.write(
              jsonEncode({'error': 'Listing changed; reload'}),
            );
            await request.response.close();
            return;
          }
          if (request.method == 'POST') {
            body.addAll({
              'housing': saved['housing'],
              'listings': saved['listings'],
            });
            (body['listings'] as List).single['active'] = false;
          }
          saved = {
            ...body,
            '_revision': (body['_revision'] as int) + 1,
            'moderation': {
              'homeVisit': {
                'status': request.method == 'POST' ? 'archived' : 'pending',
                'reason': '',
                'testOnly': false,
              },
            },
          };
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
      expect(store.status(ServiceType.homeVisit), 'pending');
      expect(saved['_revision'], 5);
      final restored = ListingStore(api: api);
      await restored.load();
      expect(restored[ServiceType.homeVisit]?.dailyPrice, 50000);
      await store.setActive(ServiceType.homeVisit, false);
      await expectLater(
        restored.setActive(ServiceType.homeVisit, false),
        throwsA(
          isA<CustomerApiException>().having((e) => e.status, 'status', 409),
        ),
      );
      expect(restored[ServiceType.homeVisit]?.active, true);
      await restored.load(refresh: true);
      expect(restored[ServiceType.homeVisit]?.active, false);
      fail = false;
      await restored.archive(ServiceType.homeVisit);
      expect(restored.status(ServiceType.homeVisit), 'archived');
      expect(restored[ServiceType.homeVisit]?.dailyPrice, 50000);
      fail = true;
      failureStatus = 409;
      await expectLater(
        restored.setHousing(HousingType.apartment),
        throwsA(
          isA<CustomerApiException>().having((e) => e.status, 'status', 409),
        ),
      );
      expect(restored.housing, HousingType.house);
      expect(restored.status(ServiceType.homeVisit), 'archived');
      expect(restored[ServiceType.homeVisit]?.dailyPrice, 50000);
      failureStatus = 500;
      await expectLater(
        restored.setActive(ServiceType.homeVisit, true),
        throwsA(isA<CustomerApiException>()),
      );
      expect(restored[ServiceType.homeVisit]?.active, false);
    },
  );
}
