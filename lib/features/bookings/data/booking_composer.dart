import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../customer/data/customer_api.dart';
import '../../wallet/data/wallet_draft_storage.dart';
import 'booking_controller.dart';

class BookingComposer extends ChangeNotifier {
  BookingComposer(this.api, this.listingId, {WalletDraftStorage? storage})
    : storage =
          storage ??
          EncryptedWalletDraftStorage(
            owner: api.userId,
            scope: '${api.baseUrl}/booking-compose/$listingId/v1',
          );
  final CustomerApi api;
  final String listingId;
  final WalletDraftStorage storage;
  final int _session = CustomerApi.sessionVersion;
  bool _disposed = false, busy = false, ready = false;
  BookingJson draft = {}, policy = {};
  BookingJson? quote, pending, result;
  Object? error;
  bool get live => !_disposed && _session == CustomerApi.sessionVersion;
  void check() {
    if (!live) throw StateError('Sessiya tugagan');
  }

  void changed() {
    if (live) notifyListeners();
  }

  Future<void> persist() =>
      storage.write({'draft': draft, 'quote': quote, 'pending': pending});
  Future<void> load() async {
    if (!live || busy || ready) return;
    busy = true;
    error = null;
    changed();
    try {
      final saved = await storage.read();
      check();
      if (saved != null) {
        draft = BookingJson.from(saved['draft']);
        quote = saved['quote'] == null
            ? null
            : BookingJson.from(saved['quote']);
        pending = saved['pending'] == null
            ? null
            : BookingJson.from(saved['pending']);
        if (pending != null &&
            (pending!['quoteId'] is! String ||
                pending!['requestId'] is! String)) {
          throw const FormatException('Buyurtma qoralamasi noto‘g‘ri');
        }
      }
      final loadedPolicy = await api.request('GET', '/bookings/policy');
      check();
      policy = loadedPolicy;
      if (policy['version'] != 'elapsed-24h-v1') {
        throw const FormatException(
          'Sana siyosati mos emas; ilovani yangilang',
        );
      }
      ready = true;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> saveDraft(BookingJson fields) async {
    if (!live || busy || !ready || pending != null) return false;
    busy = true;
    error = null;
    changed();
    try {
      final next = BookingJson.from(jsonDecode(jsonEncode(fields)));
      if (jsonEncode(next) != jsonEncode(draft)) quote = null;
      draft = next;
      await persist();
      check();
      return true;
    } catch (e) {
      if (live) error = e;
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> getQuote() async {
    if (!live || busy || !ready || pending != null) return false;
    busy = true;
    error = null;
    changed();
    try {
      quote = null;
      await persist();
      check();
      final loadedQuote = await api.request('POST', '/bookings/quotes', {
        'listingId': listingId,
        ...draft,
      });
      check();
      quote = loadedQuote;
      await persist();
      check();
      return true;
    } catch (e) {
      if (live) error = e;
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> submit() async {
    if (!live ||
        busy ||
        !ready ||
        (quote == null && pending == null && result == null)) {
      return false;
    }
    // A covered form may still be mounted after a confirmed creation. Reopening
    // its result must never manufacture a second request for the same form.
    if (result != null && pending == null) return true;
    busy = true;
    error = null;
    changed();
    try {
      pending ??= {'quoteId': quote!['id'], 'requestId': bookingRequestId()};
      await persist();
      check();
      final response = await api.request('POST', '/bookings', pending);
      check();
      result = response;
      await storage.clear();
      check();
      pending = null;
      return true;
    } catch (e) {
      if (live) error = e;
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> clearAttempt() async {
    if (!live || busy) return;
    busy = true;
    changed();
    try {
      // Persist before unlocking edits. Clearing is not a server cancellation.
      await storage.write({'draft': draft, 'quote': null, 'pending': null});
      check();
      pending = null;
      quote = null;
      result = null;
      error = null;
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
