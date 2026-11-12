import 'package:flutter/material.dart';

/// Clamp only the calendar's initial cursor, never the saved value. Compare
/// calendar days (as the picker does), not UTC instants or times of day.
DateTime calendarInitialDate(DateTime value, DateTime first, DateTime last) {
  final day = DateUtils.dateOnly(value);
  final lower = DateUtils.dateOnly(first), upper = DateUtils.dateOnly(last);
  if (day.isBefore(lower)) return lower;
  if (day.isAfter(upper)) return upper;
  return day;
}

/// Dialogs belong to the source page, including when another route is above it.
mixin OwnedDialogs<T extends StatefulWidget> on State<T> {
  final _dialogs = <Route<dynamic>>{};
  Future<R?> showOwnedPage<R>(Widget page) async {
    if (!mounted) return null;
    return _pushOwned(MaterialPageRoute<R>(builder: (_) => page));
  }

  Future<R?> showOwnedDialog<R>({required WidgetBuilder builder}) async {
    if (!mounted) return null;
    final route = DialogRoute<R>(context: context, builder: builder);
    return _pushOwned(route);
  }

  Future<R?> showOwnedSheet<R>({
    required WidgetBuilder builder,
    Color? backgroundColor,
    bool isScrollControlled = false,
  }) async {
    if (!mounted) return null;
    return _pushOwned(
      ModalBottomSheetRoute<R>(
        builder: builder,
        backgroundColor: backgroundColor,
        isScrollControlled: isScrollControlled,
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
      initialDate: calendarInitialDate(initialDate, firstDate, lastDate),
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

  void dismissOwnedRoutes() {
    final routes = List<Route<dynamic>>.of(_dialogs);
    _dialogs.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    dismissOwnedRoutes();
    super.dispose();
  }
}
