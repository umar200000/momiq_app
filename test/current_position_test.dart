import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:momiq_app/features/listings/data/current_position.dart';

void main() {
  final position = Position(
    latitude: 41.3,
    longitude: 69.2,
    timestamp: DateTime.now(),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
  test(
    'uses fresh position without retry when first provider succeeds',
    () async {
      var calls = 0;
      expect(
        await resolveCurrentPosition(
          request: (_) async {
            calls++;
            return position;
          },
        ),
        same(position),
      );
      expect(calls, 1);
    },
  );
  test('Android timeout retries native location provider', () async {
    final settings = <LocationSettings>[];
    final result = await resolveCurrentPosition(
      android: true,
      request: (s) async {
        settings.add(s);
        if (settings.length == 1) throw TimeoutException('No fix');
        return position;
      },
    );
    expect(result, same(position));
    expect((settings.last as AndroidSettings).forceLocationManager, isTrue);
  });
  test('permission failure does not retry another provider', () async {
    var calls = 0;
    await expectLater(
      resolveCurrentPosition(
        request: (_) async {
          calls++;
          throw const PermissionDeniedException('Denied');
        },
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
    expect(calls, 1);
  });
  test(
    'second timeout reaches UI instead of returning stale coordinates',
    () async {
      await expectLater(
        resolveCurrentPosition(
          android: false,
          request: (_) async {
            throw TimeoutException('No fix');
          },
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}
