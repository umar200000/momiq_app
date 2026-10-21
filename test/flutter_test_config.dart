import 'dart:async';
import 'package:momiq_app/features/customer/data/customer_store.dart' as app;
import 'sitter_fixtures.dart' as fixtures;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  app.customerSitters
    ..clear()
    ..addAll(fixtures.customerSitters);
  await testMain();
}
