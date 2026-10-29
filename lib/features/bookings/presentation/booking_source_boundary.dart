import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../customer/presentation/customer_session_boundary.dart';
import '../../listings/presentation/listing_style.dart' show lt;

Widget bookingSourceExpired() => Scaffold(
  appBar: AppBar(),
  body: Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      lt(
        'Sessiya o‘zgardi. Buyurtmani qayta oching.',
        'The session changed. Reopen the booking.',
        'Сессия изменилась. Откройте заказ заново.',
      ),
    ),
  ),
);

class BookingSourceBoundary extends StatelessWidget {
  const BookingSourceBoundary({
    super.key,
    required this.api,
    required this.valid,
    required this.child,
  });
  final CustomerApi api;
  final bool valid;
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomerSessionBoundary(
    api: api,
    expired: bookingSourceExpired(),
    child: valid ? child : bookingSourceExpired(),
  );
}

/// Dialogs belong to the source page, including when another route is above it.
mixin BookingOwnedDialogs<T extends StatefulWidget> on State<T> {
  final _dialogs = <Route<dynamic>>{};
  Future<R?> showOwnedDialog<R>({required WidgetBuilder builder}) async {
    if (!mounted) return null;
    final route = DialogRoute<R>(context: context, builder: builder);
    return _pushOwned(route);
  }

  Future<R?> showOwnedSheet<R>({required WidgetBuilder builder}) async {
    if (!mounted) return null;
    return _pushOwned(
      ModalBottomSheetRoute<R>(
        builder: builder,
        isScrollControlled: false,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
      ),
    );
  }

  Future<DateTime?> showOwnedDatePicker({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) => showOwnedDialog<DateTime>(
    builder: (_) => DatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );

  Future<R?> _pushOwned<R>(Route<R> route) async {
    _dialogs.add(route);
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      _dialogs.remove(route);
    }
  }

  @override
  void dispose() {
    final routes = List<Route<dynamic>>.of(_dialogs);
    _dialogs.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
    super.dispose();
  }
}
