import 'package:flutter/material.dart';

/// Dialogs belong to the source page, including when another route is above it.
mixin OwnedDialogs<T extends StatefulWidget> on State<T> {
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
