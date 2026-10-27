import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart' as app;
import 'sitter_fixtures.dart' as fixtures;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  app.customerSitters
    ..clear()
    ..addAll(fixtures.customerSitters);
  await testMain();
}
