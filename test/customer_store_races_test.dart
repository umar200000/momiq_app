import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/core/localization/app_language.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';

class DelayedAccountApi extends CustomerApi {
  DelayedAccountApi() : super('test', 'customer');
  Map<String, dynamic> account = {
    '_revision': 1,
    'profile': {'first': 'Before', 'last': 'Test', 'photo': null},
    'pets': [
      {'id': 'pet', 'name': 'Cat', 'type': 'Mushuk', 'photo': 'test'},
    ],
    'favorites': [],
    'addresses': [],
    'support': [],
    'notifications': {'orders': true, 'chat': true, 'video': true},
    'language': 'uz',
    'sitterProfile': null,
  };
  Completer<void>? accountGate, messagesGate, sendGate;
  bool failRead = false;
  int reads = 0, messageReads = 0, sends = 0;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (path == '/messages') {
      if (method == 'POST') {
        sends++;
        await sendGate?.future;
        return {
          'messages': [body!],
        };
      }
      messageReads++;
      await messagesGate?.future;
      return {'messages': []};
    }
    if (method == 'GET') {
      reads++;
      final snapshot = jsonDecode(jsonEncode(account));
      await accountGate?.future;
      if (failRead) throw StateError('Offline');
      return {'account': snapshot};
    }
    if (path == '/me/pets/archive') {
      account = {
        ...account,
        '_revision': (account['_revision'] as int) + 1,
        'pets': [
          {...(account['pets'] as List).single as Map, 'archived': true},
        ],
      };
    } else {
      account = {...body!, '_revision': (account['_revision'] as int) + 1};
    }
    return {'account': jsonDecode(jsonEncode(account))};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerApi.active = null;
    CustomerApi.sessionVersion = 0;
    AppLanguage.current.value = 'uz';
  });
  tearDown(() {
    CustomerApi.active = null;
    CustomerApi.sessionVersion = 0;
    AppLanguage.current.value = 'uz';
  });

  for (final delayMessages in [false, true]) {
    test(
      'old refresh cannot undo a completed edit, messages=$delayMessages',
      () async {
        final api = DelayedAccountApi();
        CustomerApi.active = api;
        final store = CustomerStore();
        addTearDown(store.dispose);
        await store.load();
        final gate = Completer<void>();
        if (delayMessages) {
          api.messagesGate = gate;
        } else {
          api.accountGate = gate;
        }
        api.account['language'] = 'ru';
        final refresh = store.refreshRemote();
        await Future<void>.delayed(Duration.zero);
        await store.update((next) => next['profile']['first'] = 'After');
        gate.complete();
        await refresh;
        expect(store.profile['first'], 'After');
        expect(store.revision, 2);
        expect(AppLanguage.current.value, 'uz');
        final prefs = await SharedPreferences.getInstance();
        final cached = jsonDecode(prefs.getString('momiq.api.account')!);
        expect(cached['profile']['first'], 'After');
        expect(cached['_revision'], 2);
      },
    );
  }

  test('old refresh cannot undo archive or publish a stale error', () async {
    final api = DelayedAccountApi();
    CustomerApi.active = api;
    final store = CustomerStore();
    addTearDown(store.dispose);
    await store.load();
    api.accountGate = Completer<void>();
    final refresh = store.refreshRemote();
    await store.archivePet('pet', true, expectedRevision: 1);
    api.failRead = true;
    api.accountGate!.complete();
    await refresh;
    expect(store.list('pets'), isEmpty);
    expect(store.archivedPets.single['id'], 'pet');
    expect(store.syncError, isNull);
  });

  for (final dispose in [false, true]) {
    test(
      'initial load stops after delayed account, dispose=$dispose',
      () async {
        final api = DelayedAccountApi()..accountGate = Completer<void>();
        api.account['language'] = 'ru';
        CustomerApi.active = api;
        final store = CustomerStore();
        var notifications = 0;
        store.addListener(() => notifications++);
        final load = store.load();
        final rejected = expectLater(load, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        if (dispose) {
          store.dispose();
        } else {
          CustomerApi.sessionVersion++;
          addTearDown(store.dispose);
        }
        api.accountGate!.complete();
        await rejected;
        expect(api.messageReads, 0);
        expect(store.loaded, isFalse);
        expect(notifications, 0);
        expect(AppLanguage.current.value, 'uz');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('momiq.api.account'), isNull);
      },
    );
  }

  test(
    'duplicate loads share one request and a failed load can retry',
    () async {
      final api = DelayedAccountApi()..accountGate = Completer<void>();
      CustomerApi.active = api;
      final store = CustomerStore();
      addTearDown(store.dispose);
      final first = store.load();
      final second = store.load();
      expect(identical(first, second), isTrue);
      final rejected = expectLater(first, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(api.reads, 1);
      api.failRead = true;
      api.accountGate!.complete();
      await rejected;
      expect(store.loaded, isFalse);
      api.failRead = false;
      api.accountGate = null;
      await store.load();
      expect(api.reads, 2);
      expect(api.messageReads, 1);
      expect(store.loaded, isTrue);
    },
  );

  for (final archive in [false, true]) {
    test(
      'session change during cache wait prevents stale completion, archive=$archive',
      () async {
        final api = DelayedAccountApi();
        CustomerApi.active = api;
        final prefs = await SharedPreferences.getInstance();
        Completer<SharedPreferences>? gate;
        final store = CustomerStore(
          preferences: () => gate?.future ?? Future.value(prefs),
        );
        addTearDown(store.dispose);
        await store.load();
        var notifications = 0;
        store.addListener(() => notifications++);
        gate = Completer<SharedPreferences>();
        final save = archive
            ? store.archivePet('pet', true, expectedRevision: 1)
            : store.update((next) => next['profile']['first'] = 'After');
        final rejected = expectLater(save, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        CustomerApi.sessionVersion++;
        final countAtLogout = notifications;
        await prefs.remove('momiq.api.account');
        gate.complete(prefs);
        await rejected;
        expect(prefs.getString('${CustomerStore.storageKey}.customer'), isNull);
        expect(prefs.getString('momiq.api.account'), isNull);
        expect(store.profile['first'], 'Before');
        expect(store.list('pets').length, 1);
        expect(notifications, countAtLogout);
      },
    );
  }

  test(
    'late message and stale local pet save cannot affect a replacement session',
    () async {
      final api = DelayedAccountApi();
      CustomerApi.active = api;
      final store = CustomerStore();
      addTearDown(store.dispose);
      await store.load();
      api.sendGate = Completer<void>();
      final send = store.send('sitter', 'Hello');
      final rejected = expectLater(send, throwsStateError);
      await expectLater(store.send('sitter', 'Again'), throwsStateError);
      expect(api.sends, 1);
      CustomerApi.sessionVersion++;
      api.sendGate!.complete();
      await rejected;
      expect(store.list('messages'), isEmpty);
      await store.refreshRemote();
      expect(api.reads, 1);
      final local = CustomerStore(petSession: CustomerPetSession());
      local.api = null;
      CustomerApi.sessionVersion++;
      await expectLater(
        local.saveItem('pets', {'id': 'stale'}),
        throwsStateError,
      );
      expect(local.petSession.pets, isEmpty);
      local.dispose();
    },
  );

  test(
    'account cache rechecks the caller after preferences resolves',
    () async {
      CustomerApi.active = DelayedAccountApi();
      var current = true;
      final save = CustomerApi.rememberAccount({
        'private': 'old',
      }, isCurrent: () => current);
      current = false;
      await save;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('momiq.api.account'), isNull);
    },
  );
}
