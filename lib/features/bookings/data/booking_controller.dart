import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../customer/data/customer_api.dart';
import '../../wallet/data/wallet_draft_storage.dart';

typedef BookingJson = Map<String, dynamic>;

String bookingRequestId() =>
    base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));

class BookingController extends ChangeNotifier {
  BookingController(this.api, this.id, {WalletDraftStorage? storage})
    : storage =
          storage ??
          EncryptedWalletDraftStorage(
            owner: api.userId,
            scope: '${api.baseUrl}/booking/$id/action-v1',
          );
  final CustomerApi api;
  final String id;
  final WalletDraftStorage storage;
  final int _session = CustomerApi.sessionVersion;
  bool _disposed = false;
  bool loading = false, sending = false, ready = false;
  BookingJson? booking, pending;
  Object? error;
  bool get live => !_disposed && _session == CustomerApi.sessionVersion;
  void changed() {
    if (live) notifyListeners();
  }

  void check() {
    if (!live) throw StateError('Sessiya tugagan');
  }

  Future<void> load() async {
    if (!live || loading || sending) return;
    loading = true;
    error = null;
    changed();
    try {
      if (!ready) {
        pending = await storage.read();
        check();
        if (pending != null &&
            (![
                  'accept',
                  'reject',
                  'cancel',
                  'start',
                  'complete',
                ].contains(pending!['action']) ||
                pending!['body'] is! Map ||
                pending!['body']['requestId'] is! String ||
                pending!['body']['revision'] is! int)) {
          throw const FormatException('Buyurtma qoralamasi noto‘g‘ri');
        }
      }
      final result = await api.request('GET', '/bookings/$id');
      check();
      booking = result;
      ready = true;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      changed();
    }
  }

  Future<bool> act(String action, {String reason = ''}) async {
    if (!live || !ready || sending || loading) return false;
    if (!['accept', 'reject', 'cancel', 'start', 'complete'].contains(action)) {
      throw ArgumentError('action');
    }
    sending = true;
    error = null;
    changed();
    try {
      if (pending == null) {
        if (['reject', 'cancel'].contains(action) && reason.trim().isEmpty) {
          return false;
        }
        pending = {
          'action': action,
          'body': {
            'revision': booking!['revision'],
            'requestId': bookingRequestId(),
            'reason': reason.trim(),
          },
        };
      }
      // Always retry the saved command. No new revision/key after uncertain I/O.
      await storage.write(pending!);
      check();
      final result = await api.request(
        'POST',
        '/bookings/$id/${pending!['action']}',
        BookingJson.from(pending!['body']),
      );
      check();
      booking = result;
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

  Future<void> discardUncertainAction() async {
    if (!live || sending || loading) return;
    await storage.clear();
    check();
    pending = null;
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class BookingInboxController extends ChangeNotifier {
  BookingInboxController(this.api, {this.conversationId});
  final CustomerApi api;
  final String? conversationId;
  final int _session = CustomerApi.sessionVersion;
  bool _disposed = false, loading = false;
  int _generation = 0;
  String bucket = 'all', query = '';
  String? cursor;
  Object? error;
  final List<BookingJson> items = [];
  bool get live => !_disposed && _session == CustomerApi.sessionVersion;

  Future<void> filters({String? bucket, String? query}) async {
    if (!live) return;
    final nextBucket = bucket ?? this.bucket;
    final nextQuery = (query ?? this.query).trim();
    if (!['all', 'pending', 'ongoing', 'history'].contains(nextBucket) ||
        nextQuery.length > 80) {
      throw ArgumentError('Invalid booking filters');
    }
    if (nextBucket == this.bucket && nextQuery == this.query) return;
    this.bucket = nextBucket;
    this.query = nextQuery;
    _generation++;
    items.clear();
    cursor = null;
    loading = false;
    await load();
  }

  Future<void> load({bool more = false}) async {
    if (!live || loading || (more && cursor == null)) return;
    final generation = _generation;
    bool current() => live && generation == _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final parameters = <String, String>{
        if (bucket != 'all') 'bucket': bucket,
        if (query.isNotEmpty) 'q': query,
        if (more) 'before': cursor!,
      };
      final path = conversationId == null
          ? '/bookings'
          : '/conversations/$conversationId/bookings';
      final result = await api.request(
        'GET',
        Uri(
          path: path,
          queryParameters: parameters.isEmpty ? null : parameters,
        ).toString(),
      );
      if (!current()) return;
      final merged = <String, BookingJson>{
        if (more)
          for (final item in items) item['id'] as String: item,
        for (final item in result['items'] as List)
          item['id'] as String: BookingJson.from(item),
      };
      items
        ..clear()
        ..addAll(merged.values);
      cursor = result['nextCursor'];
    } catch (e) {
      if (current()) error = e;
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
