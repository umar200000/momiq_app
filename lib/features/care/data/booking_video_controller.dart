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
    VideoUpload Function()? transport,
  }) : storage =
           storage ??
           EncryptedWalletDraftStorage(
             owner: api.userId,
             scope: '${api.baseUrl}:video:$bookingId',
             byteLimit: 46 * 1024 * 1024,
             videoDraft: true,
           ),
       transport = transport ?? VideoUpload.new;
  final CustomerApi api;
  final String bookingId;
  final WalletDraftStorage storage;
  final VideoUpload Function() transport;
  final _session = CustomerApi.sessionVersion;
  bool _dead = false, _restored = false;
  bool busy = false, uploading = false;
  double progress = 0;
  VideoJson? data, pending;
  Object? error;
  VideoUpload? _upload;
  String get path => '/bookings/$bookingId/videos';
  bool get live => !_dead && _session == CustomerApi.sessionVersion;
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
        check();
        if (pending != null &&
            (pending!['bytes'] is! String ||
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
      if (storage is EncryptedWalletDraftStorage && serverNow != null) {
        (storage as EncryptedWalletDraftStorage).serverTime = serverNow;
        await EncryptedWalletDraftStorage.clearExpiredVideoDrafts(serverNow);
        check();
        final created = DateTime.tryParse('${pending?['createdAt']}');
        if (created != null &&
            !created.isAfter(serverNow.subtract(const Duration(days: 30)))) {
          pending = null;
        }
      }
    } catch (e) {
      if (live) error = e;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> select(String pet, String slot, Uint8List bytes) async {
    if (!canSelect(pet, slot) || !_restored) return;
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
        'day': data!['day'],
        'requestId': chatRequestId(),
        'bytes': base64Encode(bytes),
        'createdAt': data!['policy']['serverTime'],
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
    if (!live || busy || pending == null) return;
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
          result['petId'] != draft['petId'] ||
          result['day'] != draft['day'] ||
          result['slot'] != draft['slot']) {
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
