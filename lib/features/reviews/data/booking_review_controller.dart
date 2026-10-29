import 'package:flutter/foundation.dart';
import '../../customer/data/customer_api.dart';
import '../../chat/data/conversation_controller.dart' show chatRequestId;
import '../../wallet/data/wallet_draft_storage.dart';
import 'booking_review_data.dart';

typedef ReviewJson = Map<String, dynamic>;

class BookingReviewController extends ChangeNotifier {
  BookingReviewController(this.api, this.id, {WalletDraftStorage? storage})
    : storage =
          storage ??
          EncryptedWalletDraftStorage(
            owner: api.userId,
            scope: '${api.baseUrl}/booking/$id/review-v1',
          );
  final CustomerApi api;
  final String id;
  final WalletDraftStorage storage;
  final _session = CustomerApi.sessionVersion;
  bool busy = false, _dead = false, _restored = false;
  ReviewJson? data, pending;
  Object? error;
  bool get live => !_dead && _session == CustomerApi.sessionVersion;
  String get path => '/bookings/$id/review';
  void changed() {
    if (live) notifyListeners();
  }

  void check() {
    if (!live) throw StateError('Session expired');
  }

  Future<void> load() async {
    if (!live || busy) return;
    busy = true;
    error = null;
    changed();
    try {
      if (!_restored) {
        final saved = await storage.read();
        check();
        pending = bookingReviewDraft(saved);
        _restored = true;
      }
      final result = await api.request('GET', path);
      check();
      data = bookingReviewData(result, id);
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> submit(int stars, String text, {String action = 'save'}) async {
    if (!live || busy || data == null || !_restored) return false;
    if (pending == null &&
        data![switch (action) {
              'save' => 'canCreate',
              'withdraw' => 'canWithdraw',
              'restore' => 'canRestore',
              _ => 'unsupported',
            }] !=
            true) {
      return false;
    }
    busy = true;
    error = null;
    changed();
    try {
      pending ??= bookingReviewDraft({
        'stars': stars,
        'text': text,
        'revision': data!['review']?['revision'] ?? 0,
        'action': action,
        'requestId': chatRequestId(),
      });
      await storage.write(pending!);
      check();
      final result = await api.request('POST', path, pending);
      check();
      final validated = bookingReviewData(result, id, request: pending);
      await storage.clear();
      check();
      data = validated;
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
    await load();
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }
}
