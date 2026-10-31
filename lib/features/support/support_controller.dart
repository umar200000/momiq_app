import 'package:flutter/foundation.dart';
import 'support_data.dart';
import '../customer/data/customer_api.dart';
import '../chat/data/conversation_controller.dart' show chatRequestId;
import '../wallet/data/wallet_draft_storage.dart';

typedef SupportJson = Map<String, dynamic>;

class SupportController extends ChangeNotifier {
  SupportController(
    this.api,
    this.id, {
    WalletDraftStorage? storage,
    Map<String, String>? target,
  }) : target = target == null ? null : Map.unmodifiable(target),
       storage =
           storage ??
           EncryptedWalletDraftStorage(
             owner: api.userId,
             scope: draftScope(api, id, target),
           );
  static String draftScope(
    CustomerApi api,
    String? id,
    Map<String, String>? target,
  ) {
    final base = '${api.baseUrl}/support/${id ?? 'new'}';
    if (id != null || target == null) return base;
    final source =
        '$base/${target['kind']}/${Uri.encodeComponent(target['id']!)}';
    if (target.containsKey('media')) {
      return '$source/photo/${target['media']}/${target['sha256']}';
    }
    if (target['purpose'] == 'appeal') {
      return '$source/appeal/${target['revision']}';
    }
    return source;
  }

  final Map<String, String>? target;
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
      final before = more ? data!['nextCursor'] as String : null;
      final response = id == null
          ? <String, dynamic>{'ticket': null, 'items': [], 'nextCursor': null}
          : await api.request(
              'GET',
              '$path${before != null ? '?before=$before' : ''}',
            );
      check();
      final result = id == null
          ? response
          : supportThread(
              response,
              id: id,
              before: before,
              minimumRevision: data?['ticket']?['revision'],
            );
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
    bool confirmAccountRequest = false,
    String? bookingId,
  }) async {
    if (!live || busy || !_restored || data == null) return false;
    if (pending == null &&
        id == null &&
        topic == 'account_deletion' &&
        (!confirmAccountRequest || bookingId != null || target != null)) {
      return false;
    }
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
          if (topic == 'account_deletion')
            'confirmAccountRequest': confirmAccountRequest,
          'bookingId': bookingId,
          if (target != null) 'target': target,
        },
      };
      await storage.write(pending!);
      check();
      final response = await api.request('POST', path, pending);
      check();
      final result = supportThread(
        response,
        id: id,
        minimumRevision: (pending!['revision'] as int) + 1,
      );
      if (pending!['topic'] == 'account_deletion' &&
          result['ticket']['topic'] != 'account_deletion') {
        throw const FormatException('Account request confirmation mismatch');
      }
      final original = pending!['target'];
      if (original is Map && original.containsKey('media')) {
        final confirmed = result['target'];
        final media = confirmed?['snapshot']?['media'];
        if (confirmed?['kind'] != original['kind'] ||
            confirmed?['id'] != original['id'] ||
            media is! Map ||
            media['slot'] != original['media'] ||
            media['sha256'] != original['sha256']) {
          throw const FormatException(
            'Public photo report confirmation mismatch',
          );
        }
      }
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
