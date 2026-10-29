import 'dart:async';
import 'conversation_data.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../customer/data/customer_api.dart';
import '../../wallet/data/wallet_draft_storage.dart';

typedef ChatJson = Map<String, dynamic>;

String chatRequestId() {
  final random = Random.secure();
  return base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
}

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
  String _changeCursor = '0';
  final _redacted = <String>{};
  int _readAcknowledged = 0, _deliveryAcknowledged = 0;
  bool _receiving = false;
  int _summaryGeneration = 0;
  bool _blocking = false, _discarding = false;
  bool get live => !_dead && _session == CustomerApi.sessionVersion;
  String get path => '/conversations/$id';

  void changed() {
    if (live) notifyListeners();
  }

  void check() {
    if (!live) throw StateError('Session expired');
  }

  Future<void> initialize() async {
    if (!live || loading || ready) return;
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
      final response = await api.request('GET', '$path/messages');
      check();
      final page = chatPage(response, id: id);
      merge(page);
      _advance(page);
      _changeCursor = page['changeCursor'] ?? '0';
      more = page['hasMore'] == true;
      ready = true;
      unawaited(_receivedFetched());
    } catch (e) {
      if (live) error = e;
    } finally {
      loading = false;
      changed();
    }
  }

  void merge(ChatJson page, {bool updateSummary = true}) {
    if (!live) return;
    page = chatPage(page, id: id);
    if (updateSummary) conversation = ChatJson.from(page['conversation']);
    _redacted.addAll((page['redactedIds'] as List? ?? []).cast<String>());
    final byId = {for (final item in messages) item['id']: item};
    for (final item in page['items'] as List) {
      if (item['hidden'] == true) _redacted.add(item['id'] as String);
      byId[item['id']] = ChatJson.from(item);
    }
    for (final id in _redacted) {
      final item = byId[id];
      if (item != null) {
        item['hidden'] = true;
        item['text'] = '';
        item['hasImage'] = false;
      }
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
      final generation = _summaryGeneration;
      final before = older ? messages.first['id'] as String : null;
      final after = older ? null : readCursor;
      final changes = older ? null : _changeCursor;
      final cursor = older
          ? 'before=${messages.first['id']}'
          : 'after=$readCursor&changesAfter=$_changeCursor';
      final response = await api.request('GET', '$path/messages?$cursor');
      check();
      final page = chatPage(
        response,
        id: id,
        before: before,
        after: after,
        changesAfter: changes,
      );
      merge(page, updateSummary: generation == _summaryGeneration);
      if (!older) {
        _advance(page);
        _changeCursor = page['changeCursor'] ?? _changeCursor;
      }
      if (older) more = page['hasMore'] == true;
      unawaited(_receivedFetched());
    } catch (e) {
      if (live) error = e;
    } finally {
      loading = false;
      changed();
    }
  }

  Future<bool> send(String text, String? image) async {
    if (!live || !ready || sending || _discarding || _blocking) return false;
    sending = true;
    error = null;
    changed();
    try {
      if (pending == null) {
        if (text.trim().isEmpty && image == null) return false;
        pending = {
          'text': text.trim(),
          'image': image,
          'requestId': chatRequestId(),
        };
      }
      // Persist the exact request before sending. Restart/lost response retries
      // the same content and key; a failed local write never performs a POST.
      await storage.write(pending!);
      check();
      final response = await api.request('POST', '$path/messages', pending);
      check();
      final result = chatMessage(response, requestId: pending!['requestId']);
      if (result['hidden'] == true) _redacted.add(result['id'] as String);
      if (_redacted.contains(result['id'])) {
        result['hidden'] = true;
        result['text'] = '';
        result['hasImage'] = false;
      }
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
      if (live) error = e;
      return false;
    } finally {
      sending = false;
      changed();
    }
  }

  Future<void> _receivedFetched() async {
    if (!live || !ready || _receiving) return;
    var last = 0;
    for (final message in messages) {
      if (message['mine'] != true) {
        final id = int.parse(message['id']);
        if (id > last) last = id;
      }
    }
    if (last <= _deliveryAcknowledged) return;
    _receiving = true;
    try {
      final result = await api.request('POST', '$path/received', {
        'throughId': '$last',
      });
      if (result['ok'] != true) {
        throw const FormatException('Delivery not confirmed');
      }
      if (live) _deliveryAcknowledged = last;
    } catch (_) {
      // Receipt failure cannot turn a fetched message into a send failure.
      // The next poll retries the same highest fetched incoming ID.
    } finally {
      _receiving = false;
    }
  }

  Future<void> readThrough(String id) async {
    if (!live ||
        _reading ||
        !ready ||
        !chatNumber(id) ||
        !messages.any((m) => m['id'] == id) ||
        int.parse(id) <= _readAcknowledged) {
      return;
    }
    _reading = true;
    try {
      final result = await api.request('POST', '$path/read', {'throughId': id});
      if (result['ok'] != true) {
        throw const FormatException('Read not confirmed');
      }
      if (live) _readAcknowledged = int.parse(id);
    } catch (_) {
      /* A later visible poll retries; never mark a future message. */
    } finally {
      _reading = false;
    }
  }

  Future<void> setBlocked(bool value) async {
    check();
    if (!ready || _blocking || sending || _discarding) return;
    _blocking = true;
    _summaryGeneration++;
    final revision = conversation!['blockRevision'] as int;
    try {
      final response = await api.request('POST', '$path/block', {
        'blocked': value,
        'revision': revision,
      });
      check();
      final result = chatSummary(response, id: id);
      if (result['blockRevision'] != revision + 1 ||
          result['blockedByMe'] != value) {
        throw const FormatException('Block not confirmed');
      }
      conversation = result;
      changed();
    } finally {
      _summaryGeneration++;
      _blocking = false;
    }
  }

  Future<void> discardPending() async {
    check();
    if (sending || loading || _discarding || _blocking) return;
    _discarding = true;
    try {
      await storage.clear();
      check();
      pending = null;
      error = null;
      changed();
    } finally {
      _discarding = false;
    }
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }
}
