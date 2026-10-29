import 'package:flutter/foundation.dart';
import '../../customer/data/customer_api.dart';
import '../../chat/data/conversation_controller.dart' show chatRequestId;
import '../../wallet/data/wallet_draft_storage.dart';
import 'booking_dispute_data.dart';

typedef DisputeJson = Map<String, dynamic>;

class BookingDisputeController extends ChangeNotifier {
  BookingDisputeController(this.api, this.id, {WalletDraftStorage? storage})
    : storage =
          storage ??
          EncryptedWalletDraftStorage(
            owner: api.userId,
            scope: '${api.baseUrl}/dispute/$id',
          );
  final CustomerApi api;
  final String id;
  final WalletDraftStorage storage;
  final session = CustomerApi.sessionVersion;
  bool busy = false, _dead = false, _restored = false;
  DisputeJson? data, pending;
  Object? error;
  bool get live => !_dead && session == CustomerApi.sessionVersion;
  String get path => '/bookings/$id/dispute';
  void check() {
    if (!live) throw StateError('Session changed');
  }

  void changed() {
    if (live) notifyListeners();
  }

  Future<void> load({bool more = false}) async {
    if (!live || busy || (more && data?['nextCursor'] == null)) return;
    busy = true;
    error = null;
    changed();
    try {
      if (!_restored) {
        final saved = await storage.read();
        check();
        pending = disputeDraft(saved);
        _restored = true;
      }
      final response = await api.request(
        'GET',
        '$path${more ? '?before=${data!['nextCursor']}' : ''}',
      );
      check();
      final result = disputeData(
        response,
        id,
        before: more ? data!['nextCursor'] : null,
      );
      if (more) {
        final messages = <String, dynamic>{
          for (final m in [...result['items'], ...data!['items']]) m['id']: m,
        };
        result['items'] = messages.values.toList()
          ..sort((a, b) => int.parse(a['id']).compareTo(int.parse(b['id'])));
      }
      data = result;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> send(String text, String? image) async {
    if (!live || busy || !_restored || data == null) return false;
    if (pending == null &&
        !(data!['canReportNoShow'] == true ||
            data!['canReportService'] == true ||
            data!['canAddEvidence'] == true)) {
      return false;
    }
    busy = true;
    error = null;
    changed();
    try {
      final existing = data!['case'];
      pending ??= disputeDraft({
        'action': existing == null ? 'report' : 'evidence',
        'kind':
            existing?['kind'] ??
            (data!['canReportNoShow'] == true ? 'no_show' : 'service'),
        'revision': existing?['revision'] ?? 0,
        'bookingRevision': data!['bookingRevision'],
        'text': text.trim(),
        'image': image,
        'requestId': chatRequestId(),
      });
      await storage.write(pending!);
      check();
      final result = await api.request('POST', path, pending);
      check();
      final validated = disputeData(result, id, request: pending);
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
