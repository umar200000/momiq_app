import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/listings/data/listing_store.dart';
import 'package:momiq_app/features/home/presentation/pages/sitter_home_page.dart';
import 'package:momiq_app/features/onboarding/presentation/pages/sitter_registration_page.dart';

class RegistrationApi extends CustomerApi {
  RegistrationApi(String user) : super('test-$user', user);
  Completer<void>? readGate, writeGate;
  int profileWrites = 0, listingWrites = 0;
  bool failHousing = false;
  Map<String, dynamic>? received;
  Map<String, dynamic> account = {
    '_revision': 8,
    'profile': {'first': 'Saved', 'last': 'Sitter', 'photo': null},
    'sitterProfile': {
      'years': 3,
      'about': 'TEST care',
      'housing': 'apartment',
      'homePhotos': [],
      'closedDates': ['2026-11-02'],
      'schedule': {
        'days': [true, true, true, true, true, false, false],
        'start': 540,
        'end': 1080,
      },
    },
    'language': 'uz',
  };
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/me/dashboard') {
      throw CustomerApiException('TEST dashboard unavailable', 503);
    }
    if (path == '/me/listings') {
      if (method == 'PUT') {
        listingWrites++;
        if (failHousing) throw CustomerApiException('TEST unavailable', 503);
      }
      return {'housing': 'apartment', 'listings': [], '_revision': 0};
    }
    if (method == 'GET') await readGate?.future;
    if (method == 'PUT') {
      profileWrites++;
      received = body;
      await writeGate?.future;
      account = {...body!, '_revision': (body['_revision'] as int) + 1};
    }
    return {'account': account};
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
    CustomerApi.sessionVersion = 0;
    ListingStore.instance.resetSession();
  });
  tearDown(() {
    CustomerApi.active = null;
    ListingStore.instance.resetSession();
  });
  Future<void> open(WidgetTester tester, RegistrationApi api) async {
    CustomerApi.active = api;
    ListingStore.instance.api = api;
    await tester.pumpWidget(const MaterialApp(home: SitterRegistrationPage()));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('registerSubmit'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
  }

  for (final dispose in [false, true]) {
    testWidgets('late registration load is ignored, dispose=$dispose', (
      tester,
    ) async {
      final api = RegistrationApi('old')..readGate = Completer<void>();
      await open(tester, api);
      if (dispose) {
        await tester.pumpWidget(const SizedBox());
      } else {
        CustomerApi.active = RegistrationApi('new');
        CustomerApi.sessionVersion++;
      }
      api.readGate!.complete();
      await tester.pumpAndSettle();
      if (!dispose) {
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('sitterFirst')))
              .controller!
              .text,
          isEmpty,
        );
      }
      expect(tester.takeException(), isNull);
      expect(api.profileWrites, 0);
    });
  }

  testWidgets(
    'retry after housing failure uses the saved profile revision and retains calendar',
    (tester) async {
      final api = RegistrationApi('same')..failHousing = true;
      await open(tester, api);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(api.profileWrites, 1);
      expect(api.received!['_revision'], 8);
      expect(find.byType(SitterRegistrationPage), findsOneWidget);
      api.failHousing = false;
      await submit(tester);
      // The destination has ongoing visual animation; verify the completed
      // navigation without waiting for every frame source to become idle.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.profileWrites, 2);
      expect(api.received!['_revision'], 9);
      expect(api.received!['sitterProfile']['closedDates'], ['2026-11-02']);
      expect(api.received!['sitterProfile']['schedule']['start'], 540);
      expect(find.byType(SitterHomePage), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mock.profile.first'), isNull);
      expect(
        jsonDecode(prefs.getString('momiq.api.account')!)['_revision'],
        10,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old registration cannot submit to a replacement account', (
    tester,
  ) async {
    final api = RegistrationApi('old');
    await open(tester, api);
    final replacement = RegistrationApi('new');
    CustomerApi.active = replacement;
    CustomerApi.sessionVersion++;
    ListingStore.instance.resetSession();
    ListingStore.instance.api = replacement;
    await submit(tester);
    expect(api.profileWrites, 0);
    expect(replacement.profileWrites, 0);
    expect(find.byType(SitterHomePage), findsNothing);
  });

  testWidgets(
    'late registration save preserves replacement cache and skips housing and navigation',
    (tester) async {
      final api = RegistrationApi('old')..writeGate = Completer<void>();
      await open(tester, api);
      await submit(tester);
      expect(api.profileWrites, 1);
      expect(api.received!['sitterProfile']['closedDates'], ['2026-11-02']);
      expect(api.received!['sitterProfile']['schedule']['start'], 540);
      CustomerApi.active = RegistrationApi('new');
      CustomerApi.sessionVersion++;
      ListingStore.instance.resetSession();
      final prefs = await SharedPreferences.getInstance();
      final newCache = jsonEncode({
        'profile': {'first': 'New account'},
      });
      await prefs.setString('momiq.api.account', newCache);
      api.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(prefs.getString('momiq.api.account'), newCache);
      expect(prefs.getString('mock.profile.first'), isNull);
      expect(api.listingWrites, 0);
      expect(find.byType(SitterRegistrationPage), findsOneWidget);
      expect(find.byType(SitterHomePage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
