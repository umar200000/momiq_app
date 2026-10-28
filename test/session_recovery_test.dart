import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/storage/session_vault.dart';
import 'package:momiq_app/features/auth/presentation/session_destination.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/role_selection/presentation/pages/role_selection_page.dart';
import 'package:momiq_app/features/wallet/data/wallet_draft_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    CustomerApi.active = null;
    FlutterSecureStorage.setMockInitialValues({
      EncryptedWalletDraftStorage.keyName: 'TEST-preserved-key',
    });
    await SessionVault.save(
      token: 'TEST-private',
      userId: 'TEST-owner',
      scope: 'local|http://127.0.0.1:8081/api',
    );
    SharedPreferences.setMockInitialValues({
      'momiq.api.scope': 'local|http://127.0.0.1:8081/api',
      'momiq.api.user': 'TEST-owner',
      'momiq.api.account': '{"private":"TEST-cached-profile"}',
      'momiq.unsent': 'TEST-draft-marker',
    });
  });
  tearDown(() => CustomerApi.active = null);

  test(
    'wrong-environment restore and new login cannot delete or reuse the saved session',
    () async {
      final before = await SessionVault.read();
      for (var i = 0; i < 2; i++) {
        await expectLater(
          CustomerApi.restore(),
          throwsA(isA<SessionEnvironmentMismatch>()),
        );
        await expectLater(
          CustomerApi.login('998000000000', '111111'),
          throwsA(isA<SessionEnvironmentMismatch>()),
        );
      }
      expect(await SessionVault.read(), before);
      expect(
        await SessionVault.storage.read(
          key: EncryptedWalletDraftStorage.keyName,
        ),
        'TEST-preserved-key',
      );
      expect(
        (await SharedPreferences.getInstance()).getString('momiq.unsent'),
        'TEST-draft-marker',
      );
      expect(CustomerApi.active, isNull);
    },
  );

  testWidgets(
    'recovery hides cached identity and clearing requires an explicit confirmed choice',
    (tester) async {
      final destination = await restoreDestination();
      expect(destination, isA<SessionRecoveryPage>());
      await tester.pumpWidget(MaterialApp(home: destination));
      await tester.pumpAndSettle();
      expect(find.textContaining('qoralamalar saqlab qolindi'), findsOneWidget);
      expect(find.textContaining('TEST-cached-profile'), findsNothing);
      expect(find.byType(RoleSelectionPage), findsNothing);
      await tester.tap(find.byKey(const ValueKey('clearSavedSession')));
      await tester.pumpAndSettle();
      expect(find.textContaining('yuborilmagan chek'), findsOneWidget);
      await tester.tap(find.text('Bekor qilish'));
      await tester.pumpAndSettle();
      expect(await SessionVault.read(), isNotNull);
      expect(
        await SessionVault.storage.read(
          key: EncryptedWalletDraftStorage.keyName,
        ),
        'TEST-preserved-key',
      );
      await tester.tap(find.byKey(const ValueKey('clearSavedSession')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmClearSession')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RoleSelectionPage), findsOneWidget);
      expect(await SessionVault.read(), isNull);
      expect(
        await SessionVault.storage.read(
          key: EncryptedWalletDraftStorage.keyName,
        ),
        isNull,
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
}
