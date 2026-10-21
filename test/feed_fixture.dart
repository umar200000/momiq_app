import 'package:geolocator/geolocator.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart'
    show CJson;
import 'package:momiq_app/features/customer/data/customer_feed_repository.dart';
import 'sitter_fixtures.dart';

class FixtureCustomerFeedRepository implements CustomerFeedRepository {
  const FixtureCustomerFeedRepository({
    this.delay = const Duration(milliseconds: 650),
  });
  final Duration delay;
  @override
  Future<List<CJson>> fetchSitters({CustomerCoordinates? location}) async {
    await Future<void>.delayed(delay);
    const coordinates = [
      (41.2995, 69.2726),
      (41.3150, 69.2850),
      (41.3300, 69.2400),
      (41.2800, 69.3000),
      (41.2900, 69.3400),
    ];
    final result = <CJson>[];
    for (var i = 0; i < customerSitters.length; i++) {
      final point = coordinates[i];
      result.add({
        ...customerSitters[i],
        'latitude': point.$1,
        'longitude': point.$2,
        if (location != null)
          'distance':
              Geolocator.distanceBetween(
                location.latitude,
                location.longitude,
                point.$1,
                point.$2,
              ) /
              1000,
      });
    }
    if (location != null) {
      result.sort(
        (a, b) => (a['distance'] as num).compareTo(b['distance'] as num),
      );
    }
    return result;
  }
}
