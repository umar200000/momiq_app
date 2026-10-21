import 'package:flutter/material.dart';

/// Keeps the action's dimensions stable while a request is in flight.
class ButtonProgress extends StatelessWidget {
  const ButtonProgress({super.key, required this.loading, required this.child});
  final bool loading;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      ExcludeSemantics(
        excluding: loading,
        child: Opacity(opacity: loading ? 0 : 1, child: child),
      ),
      if (loading)
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            semanticsLabel: 'Yuklanmoqda',
          ),
        ),
    ],
  );
}
