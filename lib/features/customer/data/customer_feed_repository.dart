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
    final parameters = {
      ...filters,
      if (startsAt != null) 'startsAt': startsAt.toUtc().toIso8601String(),
      if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
      'after': ?after,
    };
    final query = parameters.isEmpty
        ? ''
        : '?${Uri(queryParameters: parameters).query}';
    final api = await CustomerApi.restore() ?? CustomerApi('', '');
    final result = await api.request('GET', '/sitters$query');
    return CustomerFeedPage(
      (result['sitters'] as List).map((s) => CJson.from(s)).toList(),
      nextCursor: result['nextCursor'] as String?,
    );
  }
}
