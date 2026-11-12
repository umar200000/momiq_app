import 'customer_store.dart' show CJson;
import 'customer_api.dart';

class CustomerCoordinates {
  const CustomerCoordinates(this.latitude, this.longitude);
  final double latitude, longitude;
}

abstract class CustomerFeedRepository {
  const CustomerFeedRepository();
  Future<List<CJson>> fetchSitters({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
  });
  Future<CustomerFeedPage> fetchPage({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
    Map<String, String> filters = const {},
    String? after,
  }) async => CustomerFeedPage(
    await fetchSitters(location: location, startsAt: startsAt, endsAt: endsAt),
  );
}

class CustomerFeedPage {
  const CustomerFeedPage(this.sitters, {this.nextCursor});
  final List<CJson> sitters;
  final String? nextCursor;

  static const _services = ['boarding', 'homeVisit', 'personal'];
  static final _listingId = RegExp(r'^([A-Za-z0-9_-]{1,100}):([A-Za-z]+)$');
  static bool _number(Object? value, num min, num max) =>
      value is num && value >= min && value <= max;
  static bool _listOf<T>(Object? value, int max) =>
      value is List && value.length <= max && value.every((item) => item is T);

  static CustomerFeedPage fromServer(CJson data, {String? after}) {
    final rows = data['sitters'], cursor = data['nextCursor'];
    if (rows is! List ||
        rows.length > 20 ||
        (cursor != null &&
            (cursor is! String ||
                rows.isEmpty ||
                cursor == after ||
                !RegExp(r'^[A-Za-z0-9_-]{1,512}$').hasMatch(cursor)))) {
      throw const FormatException('Invalid catalog page');
    }
    final ids = <String>{}, parsed = <CJson>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid catalog row');
      }
      final service = row['service'], id = row['id'], pets = row['pets'];
      final identity = id is String ? _listingId.firstMatch(id) : null;
      if (service is! int ||
          !_number(service, 0, _services.length - 1) ||
          identity == null ||
          identity[2] != _services[service] ||
          (row['userId'] != null && row['userId'] != identity[1]) ||
          !ids.add(id)) {
        throw const FormatException('Invalid catalog listing identity');
      }
      if (row['name'] is! String ||
          row['price'] is! int ||
          !_number(row['price'], 1, 999999999) ||
          (row['priceUnit'] != null && row['priceUnit'] != 'animal_day') ||
          pets is! List ||
          pets.isEmpty ||
          pets.length > 2 ||
          !pets.every((p) => p == 'It' || p == 'Mushuk') ||
          !_number(row['rating'], 0, 5) ||
          row['reviews'] is! int ||
          row['reviews'] < 0 ||
          (row['about'] != null && row['about'] is! String) ||
          (row['homePhotos'] != null &&
              !_listOf<String>(row['homePhotos'], 9))) {
        throw const FormatException('Invalid public listing');
      }
      final availability = row['availability'];
      if (availability != null) {
        if (availability is! Map) {
          throw const FormatException('Invalid availability');
        }
        final schedule = availability['schedule'],
            closed = availability['closedDates'];
        if (closed != null && !_listOf<String>(closed, 366)) {
          throw const FormatException('Invalid closed dates');
        }
        if (schedule != null &&
            (schedule is! Map ||
                !_listOf<bool>(schedule['days'], 7) ||
                schedule['days'].length != 7 ||
                schedule['start'] is! int ||
                schedule['end'] is! int ||
                schedule['start'] < 0 ||
                schedule['start'] >= schedule['end'] ||
                schedule['end'] >= 1440)) {
          throw const FormatException('Invalid sitter schedule');
        }
      }
      if (row['availabilityInterval'] != null &&
          row['availabilityInterval'] is! Map) {
        throw const FormatException('Invalid availability interval');
      }
      final location = row['location'];
      if (location != null &&
          (location is! Map ||
              location['address'] is! String ||
              !_number(location['lat'], -90, 90) ||
              !_number(location['lon'], -180, 180))) {
        throw const FormatException('Invalid public location');
      }
      parsed.add(row);
    }
    return CustomerFeedPage(parsed, nextCursor: cursor as String?);
  }
}

class ApiCustomerFeedRepository extends CustomerFeedRepository {
  const ApiCustomerFeedRepository();
  @override
  Future<List<CJson>> fetchSitters({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    return (await fetchPage(
      location: location,
      startsAt: startsAt,
      endsAt: endsAt,
    )).sitters;
  }

  @override
  Future<CustomerFeedPage> fetchPage({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
    Map<String, String> filters = const {},
    String? after,
  }) async {
    if ((startsAt == null) != (endsAt == null)) {
      throw ArgumentError('Both dates required');
    }
    if (location != null &&
        (!location.latitude.isFinite ||
            !location.longitude.isFinite ||
            location.latitude.abs() > 90 ||
            location.longitude.abs() > 180)) {
      throw ArgumentError('Invalid location');
    }
    final parameters = {
      ...filters,
      'region': 'tashkent',
      // Discovery uses approximate points; do not send precise GPS coordinates.
      if (location != null) 'lat': location.latitude.toStringAsFixed(2),
      if (location != null) 'lon': location.longitude.toStringAsFixed(2),
      if (startsAt != null) 'startsAt': startsAt.toUtc().toIso8601String(),
      if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
      'after': ?after,
    };
    final query = parameters.isEmpty
        ? ''
        : '?${Uri(queryParameters: parameters).query}';
    final api = await CustomerApi.restore() ?? CustomerApi('', '');
    final result = await api.request('GET', '/sitters$query');
    return CustomerFeedPage.fromServer(result, after: after);
  }
}
