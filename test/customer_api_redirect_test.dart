import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

void main() {
  test(
    'stalled unauthorized JSON keeps its status after the body deadline',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final release = Completer<void>();
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await server.close(force: true);
      });
      final handling = server.first.then((request) async {
        request.response.statusCode = 401;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"error":');
        try {
          await request.response.flush();
          await release.future;
          await request.response.close();
        } on SocketException {
          // The timeout closes the client transport before the body finishes.
        }
      });
      final api = CustomerApi(
        'TEST',
        'owner',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await expectLater(
        api.request('GET', '/me'),
        throwsA(
          isA<CustomerApiException>().having(
            (error) => error.status,
            'known unauthorized status',
            401,
          ),
        ),
      );
      release.complete();
      await handling;
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  test(
    'truncated HTTP error body preserves status while a truncated success stays unconfirmed',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      var status = 401;
      server.listen((socket) {
        var replied = false;
        socket.listen((bytes) {
          if (replied) return;
          replied = true;
          socket.add(
            utf8.encode(
              'HTTP/1.1 $status TEST\r\nContent-Type: application/json\r\nContent-Length: 100\r\nConnection: close\r\n\r\n{"error":',
            ),
          );
          socket.close();
        });
      });
      final api = CustomerApi(
        'TEST',
        'owner',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      for (final responseStatus in [401, 403, 429, 503, 200]) {
        status = responseStatus;
        await expectLater(
          api.request('GET', '/me'),
          throwsA(
            isA<CustomerApiException>().having(
              (error) => error.status,
              'known error status',
              responseStatus >= 400 ? responseStatus : null,
            ),
          ),
        );
      }
    },
  );
  test(
    'profile reads and writes require the owner and matching revision',
    () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      final api = CustomerApi(
        'TEST-token',
        'owner',
        baseUrl: 'http://127.0.0.1:${http.port}',
      );
      String? owner = 'owner';
      final account = <String, dynamic>{};
      http.listen((request) async {
        await request.drain<void>();
        request.response.write(
          jsonEncode({'userId': owner, 'account': account}),
        );
        await request.response.close();
      });
      // Older servers return an owner but have no profile revision.
      expect((await api.request('GET', '/me'))['userId'], 'owner');
      expect((await api.request('PUT', '/me', {}))['account'], isEmpty);
      for (final foreign in ['another-owner', null]) {
        owner = foreign;
        await expectLater(api.request('GET', '/me'), throwsFormatException);
        await expectLater(api.request('PUT', '/me', {}), throwsFormatException);
      }
      owner = 'owner';
      const edit = {'_revision': 2};
      await expectLater(api.request('PUT', '/me', edit), throwsFormatException);
      for (final invalid in [-1, 2, 4, 3.0, '3']) {
        account['_revision'] = invalid;
        await expectLater(
          api.request('PUT', '/me', edit),
          throwsFormatException,
        );
      }
      account['_revision'] = 3;
      expect(
        (await api.request('PUT', '/me', edit))['account']['_revision'],
        3,
      );
    },
  );

  test('health, error and private image reads enforce wire limits', () async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => http.close(force: true));
    final api = CustomerApi('', '', baseUrl: 'http://127.0.0.1:${http.port}');
    const path = '/support/ticket/messages/1/image';
    var body = '{"ok":true}', status = 200, declaredLength = true;
    http.listen((req) async {
      final bytes = utf8.encode(body);
      req.response.statusCode = status;
      if (declaredLength) req.response.contentLength = bytes.length;
      try {
        req.response.add(bytes);
        await req.response.close();
      } on SocketException {
        // The client can reject the response before the server finishes.
      }
    });
    expect((await api.request('GET', '/health'))['ok'], isTrue);
    body = jsonEncode({'image': 'A' * (4 * 1024 * 1024)});
    expect((await api.request('GET', path))['image'].length, 4 * 1024 * 1024);
    for (final fixedLength in [true, false]) {
      declaredLength = fixedLength;
      body = jsonEncode({'image': 'A' * (4 * 1024 * 1024 + 1024)});
      await expectLater(api.request('GET', path), throwsFormatException);
      body = jsonEncode({'error': 'X' * (64 * 1024)});
      await expectLater(api.request('GET', '/health'), throwsFormatException);
      status = 403;
      await expectLater(
        api.request('GET', '/me'),
        throwsA(
          isA<CustomerApiException>()
              .having((e) => e.status, 'status', 403)
              .having((e) => e.message, 'message', 'Server xatosi'),
        ),
      );
      status = 200;
      expect((await api.request('GET', '/sitters'))['error'], isNotEmpty);
    }
    status = 403;
    body = '{"error":"denied"}';
    await expectLater(
      api.request('GET', '/me'),
      throwsA(
        isA<CustomerApiException>().having((e) => e.status, 'status', 403),
      ),
    );
  });
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
