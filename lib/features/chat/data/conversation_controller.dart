import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../customer/data/customer_api.dart';
import '../../wallet/data/wallet_draft_storage.dart';

typedef ChatJson = Map<String, dynamic>;

class ConversationController extends ChangeNotifier {
  ConversationController(this.api, this.id, {WalletDraftStorage? storage})
    : storage =
          storage ??
          EncryptedWalletDraftStorage(
            owner: api.userId,
            scope: '${api.baseUrl}/conversation/$id/outbox-v1',
          );
  final CustomerApi api;
  final String id;
  final WalletDraftStorage storage;
  final int _session = CustomerApi.sessionVersion;
  final List<ChatJson> messages = [];
  ChatJson? conversation, pending;
  bool loading = false, sending = false, more = false, ready = false;
  Object? error;
  bool _dead = false, _reading = false;
  String readCursor = '0';
  int _readAcknowledged = 0;
  bool get live => !_dead && _session == CustomerApi.sessionVersion;
  String get path => '/conversations/$id';

  void changed() {
    if (live) notifyListeners();
  }

  void check() {
    if (!live) throw StateError('Session expired');
  }

  Future<void> initialize() async {
    if (loading || ready) return;
    loading = true;
    error = null;
    changed();
    try {
      pending = await storage.read();
      check();
      if (pending != null &&
          (pending!['requestId'] is! String || pending!['text'] is! String)) {
        throw const FormatException('Invalid saved outbox');
      }
      final page = await api.request('GET', '$path/messages');
      check();
      merge(page);
      _advance(page);
      more = page['hasMore'] == true;
      ready = true;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      changed();
    }
  }

  void merge(ChatJson page) {
    conversation = ChatJson.from(page['conversation']);
    final byId = {for (final item in messages) item['id']: item};
    for (final item in page['items'] as List) {
      byId[item['id']] = ChatJson.from(item);
    }
    messages
      ..clear()
      ..addAll(byId.values);
    messages.sort((a, b) => int.parse(a['id']).compareTo(int.parse(b['id'])));
  }

  void _advance(ChatJson page) {
    final items = page['items'] as List;
    if (items.isNotEmpty) readCursor = items.last['id'] as String;
  }

  Future<void> refresh({bool older = false}) async {
    if (!live || loading || !ready || (older && (!more || messages.isEmpty))) {
      return;
    }
    loading = true;
    error = null;
    changed();
    try {
      final cursor = older
          ? 'before=${messages.first['id']}'
          : 'after=$readCursor';
      final page = await api.request('GET', '$path/messages?$cursor');
      check();
      merge(page);
      if (!older) _advance(page);
      if (older) more = page['hasMore'] == true;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      changed();
    }
  }

  Future<bool> send(String text, String? image) async {
    if (!live || !ready || sending) return false;
    sending = true;
    error = null;
    changed();
    try {
      if (pending == null) {
        if (text.trim().isEmpty && image == null) return false;
        final random = Random.secure();
        pending = {
          'text': text.trim(),
          'image': image,
          'requestId': base64UrlEncode(
            List.generate(24, (_) => random.nextInt(256)),
          ).replaceAll('=', ''),
        };
      }
      // Persist the exact request before sending. Restart/lost response retries
      // the same content and key; a failed local write never performs a POST.
      await storage.write(pending!);
      check();
      final result = await api.request('POST', '$path/messages', pending);
      check();
      final existing = messages.indexWhere((m) => m['id'] == result['id']);
      if (existing < 0) {
        messages.add(result);
      } else {
        messages[existing] = result;
      }
      messages.sort((a, b) => int.parse(a['id']).compareTo(int.parse(b['id'])));
      // If cleanup fails, retain the same request for safe server deduplication.
      await storage.clear();
      check();
      pending = null;
      return true;
    } catch (e) {
      error = e;
      return false;
    } finally {
      sending = false;
      changed();
    }
  }

  Future<void> readThrough(String id) async {
    if (!live || _reading || !ready || int.parse(id) <= _readAcknowledged) {
      return;
    }
    _reading = true;
    try {
      await api.request('POST', '$path/read', {'throughId': id});
      _readAcknowledged = int.parse(id);
    } catch (_) {
      /* A later visible poll retries; never mark a future message. */
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }
}
