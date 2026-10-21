import 'customer_store.dart' show CJson;
import 'customer_api.dart';

class CustomerCoordinates {
  const CustomerCoordinates(this.latitude, this.longitude);
  final double latitude, longitude;
}

abstract class CustomerFeedRepository {
  Future<List<CJson>> fetchSitters({CustomerCoordinates? location});
}

class ApiCustomerFeedRepository implements CustomerFeedRepository {
  const ApiCustomerFeedRepository();
  @override
  Future<List<CJson>> fetchSitters({CustomerCoordinates? location}) async {
    final result = await CustomerApi('', '').request('GET', '/sitters');
    return (result['sitters'] as List).map((s) => CJson.from(s)).toList();
  }
}
