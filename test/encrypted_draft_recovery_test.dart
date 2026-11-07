import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';
import 'package:momiq_app/features/chat/data/conversation_controller.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/reviews/data/booking_review_controller.dart';
import 'package:momiq_app/features/bookings/data/booking_dispute_controller.dart';
import 'package:momiq_app/features/care/data/booking_video_controller.dart';
import 'booking_video_test.dart' show ExplanationApi, FakeUpload;
import 'booking_video_draft_test.dart' show draft;
import 'conversation_test.dart' show ChatApi;
import 'support_test.dart' show SupportApi;
import 'booking_care_test.dart' show CareApi;
import 'booking_review_test.dart' show ReviewApi;
import 'booking_dispute_test.dart' show DisputeApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final explanation in [false, true]) {
    test('video encrypted recovery keeps companion ($explanation)', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp(
        'momiq-video-recovery-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => root.path);
      addTearDown(() async {
        await EncryptedWalletDraftStorage.clearAll(directory: () async => root);
        await root.delete(recursive: true);
        messenger.setMockMethodCallHandler(channel, null);
      });
      EncryptedWalletDraftStorage storage(String scope) =>
          EncryptedWalletDraftStorage(
            owner: 'test-owner',
            scope: scope,
            videoDraft: true,
            directory: () async => root,
          )..serverTime = DateTime.parse('2026-10-28T04:00:00Z');
      final broken = storage('broken'), companion = storage('companion');
      await broken.write(draft(explanation: explanation));
      final file =
          (await Directory('${root.path}/video_drafts').list().toList()).single
              as File;
      await companion.write(draft(explanation: !explanation));
      final bytes = await file.readAsBytes();
      bytes[20] ^= 1;
      await file.writeAsBytes(bytes);
      final api = ExplanationApi(), upload = FakeUpload();
      final c = BookingVideoController(
        api,
        'booking',
        storage: explanation ? companion : broken,
        explanationStorage: explanation ? broken : companion,
        transport: () => upload,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.invalidVideoDraft, !explanation);
      expect(c.invalidExplanationDraft, explanation);
      await c.send();
      await c.sendExplanation();
      expect(api.sent, isEmpty);
      expect(upload.paths, isEmpty);
      expect(await file.readAsBytes(), bytes);
      if (explanation) {
        await c.discardExplanation();
      } else {
        await c.discard();
      }
      expect(c.error, isNull);
      expect(c.draftsReady, true);
      expect(await file.exists(), false);
      expect(await companion.read(), draft(explanation: !explanation));
      expect(
        explanation ? c.pending : c.explanationDraft,
        draft(explanation: !explanation),
      );
    });
  }
  for (final kind in ['chat', 'support', 'care', 'review', 'dispute']) {
    test(
      '$kind can recover an authenticated-file failure without deleting it on read',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp(
          'momiq-recovery-test-',
        );
        addTearDown(() async {
          await EncryptedWalletDraftStorage.clearAll(
            directory: () async => root,
          );
          await root.delete(recursive: true);
        });
        final storage = EncryptedWalletDraftStorage(
          owner: 'test-owner',
          scope: kind,
          directory: () async => root,
        );
        await storage.write({'seed': 'TEST private draft'});
        final file =
            (await Directory(
                  '${root.path}/wallet_drafts',
                ).list().toList()).single
                as File;
        final bytes = await file.readAsBytes();
        bytes[20] ^= 1;
        await file.writeAsBytes(bytes);
        final dynamic api = switch (kind) {
          'chat' => ChatApi(),
          'support' => SupportApi(),
          'care' => CareApi(),
          'review' => ReviewApi(),
          _ => DisputeApi(),
        };
        final id = 'a' * 32;
        final dynamic c = switch (kind) {
          'chat' => ConversationController(api, id, storage: storage),
          'support' => SupportController(api, id, storage: storage),
          'care' => BookingCareController(api, id, storage: storage),
          'review' => BookingReviewController(api, id, storage: storage),
          _ => BookingDisputeController(api, id, storage: storage),
        };
        addTearDown(() => c.dispose());
        if (kind == 'chat') {
          await c.initialize();
        } else {
          await c.load();
        }
        expect(c.invalidDraft, true);
        expect(c.error, isA<FormatException>());
        expect(c.pending, isNull);
        expect(api.posts, isEmpty);
        expect(await file.readAsBytes(), bytes);
        if (kind == 'chat') {
          await c.discardPending();
        } else {
          await c.discard();
        }
        expect(c.invalidDraft, false);
        expect(c.error, isNull);
        expect(await file.exists(), false);
        expect(api.posts, isEmpty);
        if (kind == 'chat') {
          expect(c.ready, true);
        } else {
          expect(c.data, isNotNull);
        }
      },
    );
  }
}
