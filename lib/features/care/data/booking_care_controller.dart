import 'package:flutter/foundation.dart';
import '../../chat/data/conversation_controller.dart' show chatRequestId;
import '../../customer/data/customer_api.dart';
import '../../wallet/data/wallet_draft_storage.dart';
import 'booking_care_data.dart';

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
  bool invalidDraft = false;
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
        try {
          final saved = await storage.read();
          check();
          pending = careDraft(saved);
          invalidDraft = false;
          _restored = true;
        } on FormatException {
          if (live) invalidDraft = true;
          rethrow;
        }
      }
      final result = await api.request(
        'GET',
        '$path${day == null ? '' : '?day=${Uri.encodeQueryComponent(day)}'}',
      );
      check();
      data = careOverview(result, bookingId, day: day);
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> save(CareJson values) async {
    if (!live || busy || data == null || !_restored) return false;
    if (pending == null &&
        (data![values['kind'] == 'instructions'
                    ? 'canEditInstructions'
                    : 'canReport'] !=
                true ||
            !(data!['pets'] as List).any((p) => p['id'] == values['petId']))) {
      return false;
    }
    busy = true;
    error = null;
    changed();
    try {
      pending ??= careDraft({...values, 'requestId': chatRequestId()});
      await storage.write(pending!);
      check();
      final response = await api.request('POST', path, pending);
      check();
      careAcknowledgement(response, bookingId, pending!);
      await storage.clear();
      check();
      pending = null;
      final result = await api.request('GET', '$path?day=${data!['day']}');
      check();
      data = careOverview(result, bookingId, day: data!['day']);
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
      invalidDraft = false;
      _restored = false;
    } catch (e) {
      if (live) error = e;
      return;
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
      final validated = careHistory(result, before: historyCursor);
      final ids = history.map((e) => e['id']).toSet();
      history.addAll(
        (validated['items'] as List)
            .map((e) => CareJson.from(e))
            .where((e) => ids.add(e['id'])),
      );
      historyCursor = validated['nextCursor'];
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
