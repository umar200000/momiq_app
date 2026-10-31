import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

void main() {
  test(
    'API redirects cannot forward a private request or acknowledge a write',
    () async {
      final destination = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => destination.close(force: true));
      var forwarded = 0;
      destination.listen((request) async {
        forwarded++;
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = request.method == 'GET' ? 302 : 303;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${destination.port}/foreign',
        );
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      final api = CustomerApi(
        'TEST',
        'owner',
        baseUrl: 'http://127.0.0.1:${origin.port}',
      );
      for (final method in ['GET', 'POST']) {
        await expectLater(
          api.request(
            method,
            '/private',
            method == 'POST' ? {'test': true} : null,
          ),
          throwsA(
            isA<CustomerApiException>().having(
              (e) => e.status,
              'redirect',
              method == 'GET' ? 302 : 303,
            ),
          ),
        );
      }
      expect(forwarded, 0);
    },
  );
}
