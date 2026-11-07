import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  EncryptedWalletDraftStorage store({
    String owner = 'a',
    String scope = 'local',
  }) => EncryptedWalletDraftStorage(
    owner: owner,
    scope: scope,
    directory: () async => root,
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('momiq-draft-test-');
  });
  tearDown(() async {
    await EncryptedWalletDraftStorage.clearAll(directory: () async => root);
    await root.delete(recursive: true);
  });
  Future<File> draftFile() async =>
      (await Directory('${root.path}/wallet_drafts').list().toList()).single
          as File;

  test(
    'encrypted envelope uses the exact configured plaintext limit',
    () async {
      final data = {'text': 'x' * 16};
      final limit = utf8.encode(jsonEncode(data)).length;
      final bounded = EncryptedWalletDraftStorage(
        owner: 'a',
        scope: 'local',
        byteLimit: limit,
        directory: () async => root,
      );
      await bounded.write(data);
      expect(await bounded.read(), data);
      final file = await draftFile();
      final original = await file.readAsBytes();
      await expectLater(
        bounded.write({'text': 'x' * 17}),
        throwsFormatException,
      );
      expect(await file.readAsBytes(), original);
      await store().write({'text': 'x' * 17});
      final larger = await file.readAsBytes();
      await expectLater(bounded.read(), throwsFormatException);
      expect(await file.readAsBytes(), larger);
    },
  );

  for (final other in ['owner', 'environment']) {
    test(
      'copied ciphertext cannot cross $other binding after error normalization',
      () async {
        await store().write({'private': 'TEST source'});
        final source = await draftFile();
        final bytes = await source.readAsBytes();
        final target = store(
          owner: other == 'owner' ? 'b' : 'a',
          scope: other == 'environment' ? 'production' : 'local',
        );
        await target.write({'private': 'TEST target'});
        final targetFile =
            (await Directory('${root.path}/wallet_drafts').list().toList())
                .whereType<File>()
                .singleWhere((file) => file.path != source.path);
        await targetFile.writeAsBytes(bytes);
        await expectLater(target.read(), throwsFormatException);
        expect(await targetFile.readAsBytes(), bytes);
        await target.clear();
        expect(await store().read(), {'private': 'TEST source'});
        expect(await source.readAsBytes(), bytes);
      },
    );
  }

  for (final length in [0, 1, 11, 27]) {
    test(
      'truncated encrypted draft ($length bytes) is recoverable without deleting evidence',
      () async {
        await store().write({'private': 'TEST'});
        final file = await draftFile();
        final bytes = (await file.readAsBytes()).take(length).toList();
        await file.writeAsBytes(bytes);
        await expectLater(store().read(), throwsFormatException);
        expect(await file.readAsBytes(), bytes);
      },
    );
  }
  test(
    'authentication failure becomes a safe recoverable format error',
    () async {
      await store().write({'private': 'TEST'});
      final file = await draftFile();
      final bytes = await file.readAsBytes();
      bytes[20] ^= 1;
      await file.writeAsBytes(bytes);
      await expectLater(
        store().read(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.source,
            'no private source',
            isNull,
          ),
        ),
      );
      expect(await file.readAsBytes(), bytes);
    },
  );
  test(
    'a missing key never creates a replacement or deletes the draft on read',
    () async {
      await store().write({'private': 'TEST'});
      final file = await draftFile();
      final bytes = await file.readAsBytes();
      const secure = FlutterSecureStorage();
      await secure.delete(key: EncryptedWalletDraftStorage.keyName);
      await expectLater(store().read(), throwsFormatException);
      expect(
        await secure.read(key: EncryptedWalletDraftStorage.keyName),
        isNull,
      );
      expect(await file.readAsBytes(), bytes);
    },
  );
  test(
    'invalid key encoding does not appear in the exception source',
    () async {
      await store().write({'private': 'TEST'});
      const secure = FlutterSecureStorage();
      await secure.write(
        key: EncryptedWalletDraftStorage.keyName,
        value: 'TEST_PRIVATE_KEY!',
      );
      await expectLater(
        store().read(),
        throwsA(
          isA<FormatException>()
              .having((e) => e.source, 'no key source', isNull)
              .having(
                (e) => e.toString(),
                'no key text',
                isNot(contains('TEST_PRIVATE_KEY')),
              ),
        ),
      );
    },
  );
  for (final plaintext in [
    '[]',
    'null',
    '17',
    '"TEST_PRIVATE_TEXT"',
    '{"TEST_PRIVATE_TEXT":',
  ]) {
    test(
      'authenticated non-object or malformed JSON stays recoverable: $plaintext',
      () async {
        await store().write({'seed': true});
        const secure = FlutterSecureStorage();
        final encodedKey = await secure.read(
          key: EncryptedWalletDraftStorage.keyName,
        );
        final box = await AesGcm.with256bits().encrypt(
          utf8.encode(plaintext),
          secretKey: SecretKey(base64Decode(encodedKey!)),
          aad: utf8.encode(jsonEncode(['momiq.wallet-draft.v1', 'local', 'a'])),
        );
        final file = await draftFile();
        final bytes = box.concatenation();
        await file.writeAsBytes(bytes);
        await expectLater(
          store().read(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.source,
              'no plaintext source',
              isNull,
            ),
          ),
        );
        expect(await file.readAsBytes(), bytes);
      },
    );
  }
  test(
    'restart restores encrypted receipt, QR and retry id without plaintext files',
    () async {
      final data = {
        'amount': '15000.01',
        'receipt': 'PRIVATE_RECEIPT',
        'requestId': 'stable-id',
        'config': {'version': 7, 'qrImage': 'PRIVATE_QR'},
      };
      await store().write(data);
      expect(await store().read(), data);
      final file =
          (await Directory('${root.path}/wallet_drafts').list().toList()).single
              as File;
      final first = await file.readAsBytes();
      expect(
        utf8.decode(first, allowMalformed: true),
        isNot(contains('PRIVATE')),
      );
      await store().write({...data, 'amount': '16000'});
      expect((await store().read())!['amount'], '16000');
      expect(await file.readAsBytes(), isNot(first));
    },
  );
  test(
    'video draft expiry uses server timestamp and leaves wallet evidence intact',
    () async {
      final now = DateTime.utc(2026, 10, 28, 10);
      final video = EncryptedWalletDraftStorage(
        owner: 'a',
        scope: 'video:booking',
        videoDraft: true,
        directory: () async => root,
      )..serverTime = now;
      await store().write({'receipt': 'KEEP TEST'});
      await video.write({
        'bytes': 'PRIVATE TEST VIDEO',
        'createdAt': now.toIso8601String(),
      });
      await EncryptedWalletDraftStorage.clearExpiredVideoDrafts(
        now.add(const Duration(days: 30)).subtract(const Duration(seconds: 1)),
        directory: () async => root,
      );
      expect(await video.read(), isNotNull);
      await EncryptedWalletDraftStorage.clearExpiredVideoDrafts(
        now.add(const Duration(days: 30)),
        directory: () async => root,
      );
      expect(await video.read(), isNull);
      expect((await store().read())!['receipt'], 'KEEP TEST');
    },
  );
  test(
    'another account/environment cannot read a draft and tampering fails closed',
    () async {
      await store().write({'receipt': 'private'});
      expect(await store(owner: 'b').read(), isNull);
      expect(await store(scope: 'production').read(), isNull);
      final file =
          (await Directory('${root.path}/wallet_drafts').list().toList()).single
              as File;
      final bytes = await file.readAsBytes();
      bytes[20] ^= 1;
      await file.writeAsBytes(bytes);
      await expectLater(store().read(), throwsA(isA<Exception>()));
      expect(
        await file.exists(),
        isTrue,
      ); // No silent replacement of unreadable evidence.
    },
  );
  test(
    'logout invalidates queued writes and removes both key and ciphertext',
    () async {
      final old = store();
      await old.write({'amount': '100'});
      await EncryptedWalletDraftStorage.clearAll(directory: () async => root);
      await expectLater(old.write({'amount': '200'}), throwsStateError);
      expect(await Directory('${root.path}/wallet_drafts').exists(), isFalse);
      const secure = FlutterSecureStorage();
      expect(
        await secure.read(key: EncryptedWalletDraftStorage.keyName),
        isNull,
      );
      expect(await store().read(), isNull);
    },
  );
}
