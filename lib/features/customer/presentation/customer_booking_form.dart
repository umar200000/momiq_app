import 'package:flutter/material.dart';
import '../../bookings/presentation/booking_request_page.dart';
import '../../onboarding/data/profile_photo_source.dart';
import 'customer_widgets.dart';

/// Compatibility entry point: only the server-backed booking flow is allowed.
class CustomerBookingForm extends StatelessWidget {
  const CustomerBookingForm({
    super.key,
    required this.store,
    required this.sitter,
    this.photoSource,
  });
  final CustomerStore store;
  final CJson sitter;
  final ProfilePhotoSource? photoSource;
  @override
  Widget build(BuildContext context) {
    if (store.api == null || sitter['bookingEnabled'] != true) {
      return Scaffold(
        appBar: AppBar(title: Text(lt('Buyurtma', 'Booking', 'Заказ'))),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            lt(
              'Buyurtma berish hali ochilmagan. Hisobingizga kiring va katalogni yangilang.',
              'Booking is unavailable. Sign in and refresh the catalog.',
              'Заказ недоступен. Войдите и обновите каталог.',
            ),
          ),
        ),
      );
    }
    return BookingRequestPage(
      store: store,
      sitter: sitter,
      photoSource: photoSource,
    );
  }
}
