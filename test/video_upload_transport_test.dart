import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

void main() {
  test(
    'trickled video confirmation has a total body deadline and is never acknowledged',
    () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Timer? trickle;
      addTearDown(() async {
        trickle?.cancel();
        await http.close(force: true);
      });
      http.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"padding":"');
        await request.response.flush();
        trickle = Timer.periodic(const Duration(milliseconds: 250), (_) {
          request.response.write('x');
          request.response.flush().catchError((Object _) {
            trickle?.cancel();
          });
        });
      });
      final api = CustomerApi(
        'TEST',
        'sitter',
        baseUrl: 'http://127.0.0.1:${http.port}',
      );
      await expectLater(
        VideoUpload().send(
          api,
          '/videos',
          Uint8List.fromList([1, 2, 3]),
          (_) {},
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
  test(
    'video upload preserves rejected status for malformed and oversized error bodies',
    () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      var body = '<html>TEST proxy failure</html>';
      http.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 401;
        request.response.write(body);
        try {
          await request.response.close();
        } on SocketException {
          // A rejected oversized body may close the client before all bytes arrive.
        }
      });
      final api = CustomerApi(
        'TEST',
        'sitter',
        baseUrl: 'http://127.0.0.1:${http.port}',
      );
      for (final invalid in [
        '<html>TEST proxy failure</html>',
        'null',
        '[]',
        'X' * 70000,
      ]) {
        body = invalid;
        await expectLater(
          VideoUpload().send(
            api,
            '/videos',
            Uint8List.fromList([1, 2, 3]),
            (_) {},
          ),
          throwsA(
            isA<CustomerApiException>().having(
              (error) => error.status,
              'unauthorized status',
              401,
            ),
          ),
        );
      }
    },
  );
  test(
    'binary upload authenticates sends unchanged bytes and waits for server confirmation',
    () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      final input = Uint8List.fromList(List.generate(70000, (i) => i % 251));
      final responseGate = Completer<void>();
      final received = Completer<void>();
      final handler = http.first.then((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer SECRET_TEST',
        );
        expect(request.uri.queryParameters['requestId'], 'stable');
        final output = BytesBuilder();
        await for (final chunk in request) {
          output.add(chunk);
        }
        expect(output.takeBytes(), input);
        received.complete();
        await responseGate.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'id': 'saved'}));
        await request.response.close();
      });
      final api = CustomerApi(
        'SECRET_TEST',
        'sitter',
        baseUrl: 'http://127.0.0.1:${http.port}',
      );
      double progress = 0;
      bool confirmed = false;
      final sending = VideoUpload()
          .send(api, '/videos?requestId=stable', input, (p) => progress = p)
          .then((result) {
            confirmed = true;
            return result;
          });
      await received.future;
      expect(progress, 1);
      expect(confirmed, false);
      responseGate.complete();
      expect((await sending)['id'], 'saved');
      await handler;
    },
  );
}
