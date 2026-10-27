import 'dart:convert';
import 'dart:io';
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
