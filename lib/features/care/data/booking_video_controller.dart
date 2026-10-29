import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../chat/data/conversation_controller.dart' show chatRequestId;
import '../../customer/data/customer_api.dart';
import '../../wallet/data/wallet_draft_storage.dart';

typedef VideoJson = Map<String, dynamic>;

class VideoUpload {
  HttpClient? _client;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<VideoJson> send(
    CustomerApi api,
    String path,
    Uint8List bytes,
    void Function(double) progress,
  ) async {
    if (_cancelled) throw StateError('Yuklash bekor qilindi');
    final client = _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(Uri.parse('${api.baseUrl}$path'))
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${api.token}',
      );
      request.headers.contentType = ContentType('video', 'mp4');
      request.contentLength = bytes.length;
      for (var offset = 0; offset < bytes.length; offset += 65536) {
        if (_cancelled) throw StateError('Yuklash bekor qilindi');
        final end = (offset + 65536).clamp(0, bytes.length);
        request.add(Uint8List.sublistView(bytes, offset, end));
        await request.flush().timeout(const Duration(seconds: 30));
        progress(end / bytes.length);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 150),
      );
      final output = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        output.add(chunk);
        if (output.length > 65536) {
          throw const FormatException('Server javobi juda katta');
        }
      }
      final data = VideoJson.from(
        jsonDecode(utf8.decode(output.takeBytes())) as Map,
      );
      if (response.statusCode != 200) {
        throw CustomerApiException(
          data['error'] ?? 'Video yuborilmadi',
          response.statusCode,
        );
      }
      if (_cancelled) throw StateError('Server holatini qayta tekshiring');
      return data;
    } finally {
      client.close(force: true);
      _client = null;
    }
  }
}

class BookingVideoController extends ChangeNotifier {
  BookingVideoController(
    this.api,
    this.bookingId, {
    WalletDraftStorage? storage,
    WalletDraftStorage? explanationStorage,
    VideoUpload Function()? transport,
  }) : storage =
           storage ??
           EncryptedWalletDraftStorage(
             owner: api.userId,
             scope: '${api.baseUrl}:video:$bookingId',
             byteLimit: 46 * 1024 * 1024,
             videoDraft: true,
           ),
       explanationStorage =
           explanationStorage ??
           EncryptedWalletDraftStorage(
             owner: api.userId,
             scope: '${api.baseUrl}:video-explanation:$bookingId',
             videoDraft: true,
           ),
       transport = transport ?? VideoUpload.new;
  final CustomerApi api;
  final String bookingId;
  final WalletDraftStorage storage;
  final WalletDraftStorage explanationStorage;
  final VideoUpload Function() transport;
  final _session = CustomerApi.sessionVersion;
  bool _dead = false, _restored = false;
  bool busy = false, uploading = false;
  double progress = 0;
  VideoJson? data, pending, explanationDraft;
  Object? error;
  VideoUpload? _upload;
  String get path => '/bookings/$bookingId/videos';
  bool get live => !_dead && _session == CustomerApi.sessionVersion;
  bool get selectionInterrupted => pending?['kind'] == 'selection';
  void check() {
    if (!live) throw StateError('Session expired');
  }

  void changed() {
    if (live) notifyListeners();
  }

  bool canSelect(String pet, String slot) =>
      live &&
      !busy &&
      pending == null &&
      data?['canUpload'] == true &&
      (data!['pets'] as List).any((p) => p['id'] == pet) &&
      (data!['policy']['slots'] as List).any(
        (s) => s['slot'] == slot && s['open'] == true,
      ) &&
      !(data!['items'] as List).any(
        (v) => v['petId'] == pet && v['slot'] == slot,
      );

  Future<void> load({String? day}) async {
    if (!live || busy) return;
    busy = true;
    error = null;
    changed();
    try {
      if (!_restored) {
        pending = await storage.read();
        explanationDraft = await explanationStorage.read();
        check();
        if (pending != null &&
            ((!selectionInterrupted && pending!['bytes'] is! String) ||
                pending!['requestId'] is! String ||
                pending!['petId'] is! String ||
                pending!['day'] is! String ||
                pending!['slot'] is! String)) {
          throw const FormatException('Video qoralamasi ochilmadi');
        }
        _restored = true;
      }
      final result = await api.request(
        'GET',
        '$path${day == null ? '' : '?day=${Uri.encodeQueryComponent(day)}'}',
      );
      check();
      data = result;
      final serverNow = DateTime.tryParse('${result['policy']?['serverTime']}');
      if (explanationStorage is EncryptedWalletDraftStorage &&
          serverNow != null) {
        (explanationStorage as EncryptedWalletDraftStorage).serverTime =
            serverNow;
      }
      if (storage is EncryptedWalletDraftStorage && serverNow != null) {
        (storage as EncryptedWalletDraftStorage).serverTime = serverNow;
        await EncryptedWalletDraftStorage.clearExpiredVideoDrafts(serverNow);
        check();
        final created = DateTime.tryParse('${pending?['createdAt']}');
        if (created != null &&
            !created.isAfter(serverNow.subtract(const Duration(days: 30)))) {
          pending = null;
        }
        final noteCreated = DateTime.tryParse(
          '${explanationDraft?['createdAt']}',
        );
        if (noteCreated != null &&
            !noteCreated.isAfter(
              serverNow.subtract(const Duration(days: 30)),
            )) {
          explanationDraft = null;
        }
      }
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> explain(
    String pet,
    String slot,
    String reason,
    bool emergency,
  ) async {
    if (!live || busy || explanationDraft != null || data == null) return;
    busy = true;
    error = null;
    changed();
    try {
      final draft = <String, dynamic>{
        'petId': pet,
        'slot': slot,
        'day': data!['day'],
        'reason': reason,
        'emergency': emergency,
        'requestId': chatRequestId(),
        'createdAt': data!['policy']['serverTime'],
      };
      await explanationStorage.write(draft);
      check();
      explanationDraft = draft;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
    if (live && explanationDraft != null) await sendExplanation();
  }

  Future<void> sendExplanation() async {
    if (!live || busy || explanationDraft == null) return;
    busy = true;
    error = null;
    changed();
    final draft = explanationDraft!;
    try {
      final result = await api.request('POST', '$path/explanations', {
        for (final key in [
          'petId',
          'slot',
          'day',
          'reason',
          'emergency',
          'requestId',
        ])
          key: draft[key],
      });
      check();
      if (result['ok'] != true ||
          result['bookingId'] != bookingId ||
          [
            'requestId',
            'petId',
            'day',
            'slot',
            'emergency',
          ].any((key) => result[key] != draft[key]) ||
          result['reason'] != (draft['reason'] as String).trim() ||
          result['created'] is! String ||
          DateTime.tryParse(result['created']) == null) {
        throw const FormatException('Sabab tasdig‘i mos emas');
      }
      await explanationStorage.clear();
      check();
      explanationDraft = null;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
    if (live && explanationDraft == null) await load(day: draft['day']);
  }

  Future<void> discardExplanation() async {
    if (!live || busy) return;
    busy = true;
    error = null;
    changed();
    try {
      await explanationStorage.clear();
      check();
      explanationDraft = null;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
    if (live) await load();
  }

  /// Save the target before handing control to a camera/gallery activity. After
  /// process death its global lost-data cache cannot safely identify our flow.
  Future<String?> beginSelection(String pet, String slot) async {
    if (!canSelect(pet, slot) || !_restored) return null;
    busy = true;
    error = null;
    changed();
    try {
      final intent = <String, dynamic>{
        'kind': 'selection',
        'petId': pet,
        'slot': slot,
        'day': data!['day'],
        'requestId': chatRequestId(),
        'createdAt': data!['policy']['serverTime'],
      };
      await storage.write(intent);
      check();
      pending = intent;
      return intent['requestId'] as String;
    } catch (e) {
      if (live) error = e;
      return null;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> cancelSelection(String requestId) async {
    if (!live ||
        busy ||
        !selectionInterrupted ||
        pending!['requestId'] != requestId) {
      return;
    }
    await discard();
  }

  Future<void> select(
    String pet,
    String slot,
    Uint8List bytes, {
    String? selectionId,
  }) async {
    final intent = pending;
    final fromPicker =
        selectionId != null &&
        selectionInterrupted &&
        intent!['requestId'] == selectionId &&
        intent['petId'] == pet &&
        intent['slot'] == slot;
    if (!live ||
        busy ||
        !_restored ||
        (selectionId != null ? !fromPicker : !canSelect(pet, slot))) {
      return;
    }
    busy = true;
    error = null;
    changed();
    try {
      if (bytes.length < 12 || bytes.length > 32 * 1024 * 1024) {
        throw const FormatException('Video 32 MiB dan oshmasin');
      }
      final draft = <String, dynamic>{
        'petId': pet,
        'slot': slot,
        'day': fromPicker ? intent['day'] : data!['day'],
        'requestId': fromPicker ? selectionId : chatRequestId(),
        'bytes': base64Encode(bytes),
        'createdAt': fromPicker
            ? intent['createdAt']
            : data!['policy']['serverTime'],
      };
      await storage.write(draft);
      check();
      pending = draft;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> send() async {
    if (!live || busy || pending == null || selectionInterrupted) return;
    busy = uploading = true;
    progress = 0;
    error = null;
    changed();
    final draft = pending!;
    final upload = _upload = transport();
    try {
      final query = Uri(
        queryParameters: {
          for (final key in ['petId', 'day', 'slot', 'requestId'])
            key: draft[key] as String,
        },
      ).query;
      final result = await upload.send(
        api,
        '$path?$query',
        base64Decode(draft['bytes']),
        (value) {
          if (live) {
            progress = value;
            changed();
          } else {
            upload.cancel();
          }
        },
      );
      check();
      if (result['id'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(result['id']) ||
          result['bookingId'] != bookingId ||
          result['requestId'] != draft['requestId'] ||
          result['petId'] != draft['petId'] ||
          result['day'] != draft['day'] ||
          result['slot'] != draft['slot'] ||
          result['durationMs'] is! int ||
          result['durationMs'] < 10000 ||
          result['durationMs'] > 60000 ||
          result['bytes'] is! int ||
          result['bytes'] < 12 ||
          result['bytes'] > 32 * 1024 * 1024 ||
          result['width'] is! int ||
          result['height'] is! int ||
          result['width'] < 16 ||
          result['height'] < 16 ||
          result['width'] > 1920 ||
          result['height'] > 1920 ||
          result['width'] * result['height'] > 1920 * 1080 ||
          result['created'] is! String ||
          DateTime.tryParse(result['created']) == null) {
        throw const FormatException('Video tasdig‘i mos emas');
      }
      await storage.clear();
      check();
      pending = null;
    } catch (e) {
      if (live) error = e;
    } finally {
      _upload = null;
      busy = uploading = false;
      changed();
    }
    if (live && pending == null) await load(day: draft['day']);
  }

  void cancel() {
    _upload?.cancel();
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
      _restored = true;
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
    if (live) await load();
  }

  @override
  void dispose() {
    _dead = true;
    _upload?.cancel();
    super.dispose();
  }
}
