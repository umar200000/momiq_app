import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/listings/data/map_access.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';
import 'package:momiq_app/features/listings/presentation/service_form_page.dart';

class FakeProbe extends MapAccessProbe {
  MapAccessState value = const MapAccessState(
    location: false,
    permission: false,
  );
  @override
  bool get supported => false;
  @override
  Future<MapAccessState> check() async => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'GPS and permission gate access; internet is not a prerequisite',
    () async {
      final probe = FakeProbe();
      final controller = MapAccessController(probe: probe);
      expect(await controller.refresh(), isFalse);
      probe.value = const MapAccessState(location: false, permission: true);
      expect(await controller.refresh(), isFalse);
      probe.value = const MapAccessState(location: true, permission: false);
      expect(await controller.refresh(), isFalse);
      probe.value = const MapAccessState(location: true, permission: true);
      expect(await controller.refresh(), isTrue);
      probe.value = const MapAccessState(location: false, permission: true);
      expect(await controller.refresh(), isFalse);
      controller.dispose();
    },
  );

  testWidgets(
    'form prompts on entry and does not expose map until requirements are met',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = ListingStore();
      await store.load();
      final probe = FakeProbe();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ServiceFormPage(
            type: ServiceType.boarding,
            store: store,
            accessProbe: probe,
            locationPicker: (_, current) async {
              opened++;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('chooseCareLocation')), findsNothing);
      expect(opened, 0);
      await tester.tap(find.text('Davom etish'));
      await tester.pumpAndSettle();
      probe.value = const MapAccessState(location: true, permission: true);
      await tester.ensureVisible(find.byKey(const ValueKey('mapCheckAgain')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mapCheckAgain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chooseCareLocation')), findsOneWidget);
      // Recheck at the exact moment of opening, even before the periodic check.
      probe.value = const MapAccessState(location: false, permission: true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('chooseCareLocation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chooseCareLocation')));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(find.byKey(const ValueKey('chooseCareLocation')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
