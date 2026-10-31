import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/storage/session_vault.dart';

abstract class WalletDraftStorage {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
  Future<void> clear();
}

/// Only ciphertext is stored in the app support directory. The key remains in
/// device-only secure storage. Scope/user binding is authenticated with the data.
class EncryptedWalletDraftStorage implements WalletDraftStorage {
  EncryptedWalletDraftStorage({
    required String owner,
    required String scope,
    this.byteLimit = maxBytes,
    this.videoDraft = false,
    Future<Directory> Function()? directory,
  }) : _binding = jsonEncode(['momiq.wallet-draft.v1', scope, owner]),
       _directory = directory ?? getApplicationSupportDirectory,
       _epoch = _generation;

  static const keyName = 'momiq.wallet-draft-key.v1';
  static const maxBytes = 10 * 1024 * 1024;
  static int _generation = 0;
  static Future<void> _pending = Future.value();
  final String _binding;
  final int byteLimit;
  final bool videoDraft;
  DateTime? serverTime;
  final Future<Directory> Function() _directory;
  final int _epoch;

  static Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkSession() {
    if (_epoch != _generation) throw StateError('Qoralama sessiyasi tugagan');
  }

  static AesGcm _cipher() {
    return AesGcm.with256bits();
  }

  Future<File> _file() async {
    final root = await _directory();
    final digest = await Sha256().hash(utf8.encode(_binding));
    final name = digest.bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    return File(
      '${root.path}/${videoDraft ? 'video_drafts' : 'wallet_drafts'}/$name.bin',
    );
  }

  Future<SecretKey> _key({required bool create}) async {
    var encoded = await SessionVault.storage.read(key: keyName);
    if (encoded == null) {
      if (!create) throw StateError('Qoralama kaliti mavjud emas');
      final key = await _cipher().newSecretKey();
      encoded = base64Encode(await key.extractBytes());
      _checkSession();
      await SessionVault.storage.write(key: keyName, value: encoded);
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) {
      throw const FormatException('Qoralama kaliti noto‘g‘ri');
    }
    return SecretKey(bytes);
  }

  @override
  Future<Map<String, dynamic>?> read() => _serial(() async {
    _checkSession();
    final file = await _file();
    if (!await file.exists()) return null;
    if (await file.length() > byteLimit + 64) {
      throw const FormatException('Qoralama juda katta');
    }
    final cipher = _cipher();
    final box = SecretBox.fromConcatenation(
      await file.readAsBytes(),
      nonceLength: cipher.nonceLength,
      macLength: cipher.macAlgorithm.macLength,
    );
    final bytes = await cipher.decrypt(
      box,
      secretKey: await _key(create: false),
      aad: utf8.encode(_binding),
    );
    _checkSession();
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  });

  @override
  Future<void> write(Map<String, dynamic> data) {
    // Capture before queuing so later form edits cannot mutate this snapshot.
    final bytes = utf8.encode(jsonEncode(data));
    return _serial(() async {
      _checkSession();
      if (bytes.length > byteLimit) {
        throw const FormatException('Qoralama juda katta');
      }
      if (videoDraft && serverTime == null) {
        throw StateError('Video qoralamasi uchun server vaqti kerak');
      }
      final box = await _cipher().encrypt(
        bytes,
        secretKey: await _key(create: true),
        aad: utf8.encode(_binding),
      );
      _checkSession();
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(box.concatenation(), flush: true);
      if (videoDraft) {
        try {
          await temporary.setLastModified(serverTime!.toUtc());
        } catch (_) {
          await temporary.delete();
          rethrow;
        }
      }
      _checkSession();
      // On Android/iOS rename replaces the prior complete snapshot atomically.
      await temporary.rename(file.path);
    });
  }

  @override
  Future<void> clear() => _serial(() async {
    _checkSession();
    final file = await _file();
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  });

  static Future<void> clearAll({
    Future<Directory> Function()? directory,
    bool removeFiles = true,
  }) {
    _generation++; // Invalidates both running and queued saves before logout.
    return _serial(() async {
      await SessionVault.storage.delete(key: keyName);
      if (!removeFiles) return;
      final root = await (directory ?? getApplicationSupportDirectory)();
      for (final name in ['wallet_drafts', 'video_drafts']) {
        final folder = Directory('${root.path}/$name');
        if (await FileSystemEntity.isLink(folder.path)) {
          await Link(folder.path).delete();
        } else if (await folder.exists()) {
          await folder.delete(recursive: true);
        }
      }
    });
  }

  static Future<void> clearExpiredVideoDrafts(
    DateTime serverNow, {
    Future<Directory> Function()? directory,
  }) => _serial(() async {
    final root = await (directory ?? getApplicationSupportDirectory)();
    final folder = Directory('${root.path}/video_drafts');
    if (await FileSystemEntity.isLink(folder.path) || !await folder.exists()) {
      return;
    }
    final cutoff = serverNow.toUtc().subtract(const Duration(days: 30));
    await for (final item in folder.list(followLinks: false)) {
      if (item is! File ||
          !RegExp(
            r'[a-f0-9]{64}\.bin(?:\.tmp)?$',
          ).hasMatch(item.path.split(Platform.pathSeparator).last)) {
        continue;
      }
      final modified = (await item.stat()).modified.toUtc();
      if (!modified.isAfter(cutoff)) await item.delete();
    }
  });
}
