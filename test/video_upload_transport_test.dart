import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';

void main() {
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
