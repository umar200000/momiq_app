import 'package:flutter/foundation.dart';
import '../customer/data/customer_api.dart';
import '../chat/data/conversation_controller.dart' show chatRequestId;
import '../wallet/data/wallet_draft_storage.dart';

typedef SupportJson = Map<String, dynamic>;

class SupportController extends ChangeNotifier {
  SupportController(this.api, this.id, {WalletDraftStorage? storage})
    : storage =
          storage ??
          EncryptedWalletDraftStorage(
            owner: api.userId,
            scope: '${api.baseUrl}/support/${id ?? 'new'}',
          );
  final CustomerApi api;
  final String? id;
  final WalletDraftStorage storage;
  final session = CustomerApi.sessionVersion;
  bool busy = false, _dead = false, _restored = false;
  Object? error;
  SupportJson? data, pending;
  bool get live => !_dead && session == CustomerApi.sessionVersion;
  String get path => '/support${id == null ? '' : '/$id'}';
  void changed() {
    if (live) notifyListeners();
  }

  void check() {
    if (!live) throw StateError('Session changed');
  }

  Future<void> load({bool more = false}) async {
    if (!live || busy || (more && data?['nextCursor'] == null)) return;
    busy = true;
    error = null;
    changed();
    try {
      if (!_restored) {
        pending = await storage.read();
        check();
        _restored = true;
      }
      final result = id == null
          ? <String, dynamic>{'ticket': null, 'items': [], 'nextCursor': null}
          : await api.request(
              'GET',
              '$path${more ? '?before=${data!['nextCursor']}' : ''}',
            );
      check();
      if (more) {
        final byId = <String, dynamic>{
          for (final m in [...result['items'], ...data!['items']]) m['id']: m,
        };
        result['items'] = byId.values.toList()
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

  Future<bool> send(
    String text,
    String? image, {
    String subject = '',
    String topic = 'general',
    String? bookingId,
  }) async {
    if (!live || busy || !_restored || data == null) return false;
    busy = true;
    error = null;
    changed();
    try {
      pending ??= {
        'text': text.trim(),
        'image': image,
        'revision': data!['ticket']?['revision'] ?? 0,
        'requestId': chatRequestId(),
        'action': 'reply',
        if (id == null) ...{
          'subject': subject.trim(),
          'topic': topic,
          'bookingId': bookingId,
        },
      };
      await storage.write(pending!);
      check();
      final result = await api.request('POST', path, pending);
      check();
      data = result;
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
