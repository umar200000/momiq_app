import 'package:flutter/foundation.dart';
import '../../chat/data/conversation_controller.dart' show chatRequestId;
import '../../customer/data/customer_api.dart';
import '../../wallet/data/wallet_draft_storage.dart';

typedef CareJson = Map<String, dynamic>;

class BookingCareController extends ChangeNotifier {
  BookingCareController(this.api, this.bookingId, {WalletDraftStorage? storage})
    : storage =
          storage ??
          EncryptedWalletDraftStorage(
            owner: api.userId,
            scope: '${api.baseUrl}/booking/$bookingId/care-v1',
          );
  final CustomerApi api;
  final String bookingId;
  final WalletDraftStorage storage;
  final _session = CustomerApi.sessionVersion;
  CareJson? data, pending;
  Object? error;
  bool busy = false, _dead = false, _restored = false;
  final history = <CareJson>[];
  String? historyCursor;
  bool historyLoaded = false;
  bool get live => !_dead && _session == CustomerApi.sessionVersion;
  String get path => '/bookings/$bookingId/care';
  void changed() {
    if (live) notifyListeners();
  }

  void check() {
    if (!live) throw StateError('Session expired');
  }

  Future<void> load({String? day}) async {
    if (!live || busy) return;
    busy = true;
    error = null;
    changed();
    try {
      if (!_restored) {
        pending = await storage.read();
        check();
        if (pending != null &&
            (pending!['requestId'] is! String || pending!['payload'] is! Map)) {
          throw const FormatException('Invalid saved care request');
        }
        _restored = true;
      }
      final result = await api.request(
        'GET',
        '$path${day == null ? '' : '?day=${Uri.encodeQueryComponent(day)}'}',
      );
      check();
      data = result;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> save(CareJson values) async {
    if (!live || busy || data == null || !_restored) return false;
    busy = true;
    error = null;
    changed();
    try {
      pending ??= {...values, 'requestId': chatRequestId()};
      await storage.write(pending!);
      check();
      await api.request('POST', path, pending);
      check();
      await storage.clear();
      check();
      pending = null;
      final result = await api.request('GET', '$path?day=${data!['day']}');
      check();
      data = result;
      history.clear();
      historyLoaded = false;
      historyCursor = null;
      return true;
    } catch (e) {
      if (live) error = e;
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> discard() async {
    if (!live || busy) return;
    busy = true;
    error = null;
    changed();
    try {
      await storage.clear();
      check();
      pending = null;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
    await load(day: data?['day']);
  }

  Future<void> loadHistory() async {
    if (!live || busy || (historyLoaded && historyCursor == null)) return;
    busy = true;
    error = null;
    changed();
    try {
      final result = await api.request(
        'GET',
        '$path/history${historyCursor == null ? '' : '?before=$historyCursor'}',
      );
      check();
      final ids = history.map((e) => e['id']).toSet();
      history.addAll(
        (result['items'] as List)
            .map((e) => CareJson.from(e))
            .where((e) => ids.add(e['id'])),
      );
      historyCursor = result['nextCursor'];
      historyLoaded = true;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }
}
