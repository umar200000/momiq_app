import 'customer_store.dart' show CJson;
import 'customer_api.dart';

class CustomerCoordinates {
  const CustomerCoordinates(this.latitude, this.longitude);
  final double latitude, longitude;
}

abstract class CustomerFeedRepository {
  Future<List<CJson>> fetchSitters({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
  });
}

class ApiCustomerFeedRepository implements CustomerFeedRepository {
  const ApiCustomerFeedRepository();
  @override
  Future<List<CJson>> fetchSitters({
    CustomerCoordinates? location,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    if ((startsAt == null) != (endsAt == null)) {
      throw ArgumentError('Both dates required');
    }
    final query = startsAt == null
        ? ''
        : '?${Uri(queryParameters: {'startsAt': startsAt.toUtc().toIso8601String(), 'endsAt': endsAt!.toUtc().toIso8601String()}).query}';
    final result = await CustomerApi('', '').request('GET', '/sitters$query');
    return (result['sitters'] as List).map((s) => CJson.from(s)).toList();
  }
}
