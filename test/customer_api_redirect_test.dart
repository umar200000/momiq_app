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
      await expectLater(
        api.videoPoster('/bookings/${'a' * 32}/videos/${'b' * 32}/poster'),
        throwsA(
          isA<CustomerApiException>().having((e) => e.status, 'redirect', 302),
        ),
      );
      expect(forwarded, 0);
    },
  );
  test(
    'private poster requires a bounded JPEG from the authenticated media route',
    () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      final api = CustomerApi(
        'TEST',
        'owner',
        baseUrl: 'http://127.0.0.1:${http.port}',
      );
      final path = '/bookings/${'a' * 32}/videos/${'b' * 32}/poster';
      var calls = 0;
      http.listen((request) async {
        expect(request.uri.path, path);
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer TEST',
        );
        request.response.headers.contentType = ContentType('image', 'jpeg');
        calls++;
        request.response.add(switch (calls) {
          1 => [0xff, 0xd8, 0xff, 0xd9],
          2 => [1, 2, 3, 4],
          _ => List.filled(2 * 1024 * 1024 + 1, 0),
        });
        try {
          await request.response.close();
        } on SocketException {
          /* rejected oversized stream */
        }
      });
      expect(await api.videoPoster(path), [0xff, 0xd8, 0xff, 0xd9]);
      await expectLater(api.videoPoster(path), throwsFormatException);
      await expectLater(api.videoPoster(path), throwsFormatException);
      expect(() => api.videoPoster('/foreign'), throwsArgumentError);
    },
  );
}
