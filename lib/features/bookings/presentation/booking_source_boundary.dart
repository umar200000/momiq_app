export '../../../core/widgets/owned_dialogs.dart' show OwnedDialogs;
import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../customer/presentation/customer_session_boundary.dart';
import '../../listings/presentation/listing_style.dart' show lt;

Widget bookingSourceNotice() => Padding(
  padding: const EdgeInsets.all(24),
  child: Text(
    lt(
      'Sessiya o‘zgardi. Buyurtmani qayta oching.',
      'The session changed. Reopen the booking.',
      'Сессия изменилась. Откройте заказ заново.',
    ),
  ),
);

Widget bookingSourceExpired() =>
    Scaffold(appBar: AppBar(), body: bookingSourceNotice());

class BookingSourceBoundary extends StatelessWidget {
  const BookingSourceBoundary({
    super.key,
    required this.api,
    required this.valid,
    required this.child,
    this.expired,
  });
  final CustomerApi api;
  final bool valid;
  final Widget child;
  final Widget? expired;
  @override
  Widget build(BuildContext context) => CustomerSessionBoundary(
    api: api,
    expired: expired ?? bookingSourceExpired(),
    child: valid ? child : (expired ?? bookingSourceExpired()),
  );
}
