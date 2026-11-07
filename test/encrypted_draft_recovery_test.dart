import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';
import 'package:momiq_app/features/chat/data/conversation_controller.dart';
import 'package:momiq_app/features/support/support_controller.dart';
import 'package:momiq_app/features/care/data/booking_care_controller.dart';
import 'package:momiq_app/features/reviews/data/booking_review_controller.dart';
import 'package:momiq_app/features/bookings/data/booking_dispute_controller.dart';
import 'conversation_test.dart' show ChatApi;
import 'support_test.dart' show SupportApi;
import 'booking_care_test.dart' show CareApi;
import 'booking_review_test.dart' show ReviewApi;
import 'booking_dispute_test.dart' show DisputeApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
