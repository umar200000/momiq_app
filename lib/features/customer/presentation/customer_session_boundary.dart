import 'package:flutter/material.dart';
import '../data/customer_api.dart';

/// A target change must not re-authorize the API of an expired session.
class CustomerSessionBoundary extends StatefulWidget {
  const CustomerSessionBoundary({
    super.key,
    required this.api,
    required this.child,
    required this.expired,
  });
  final CustomerApi? api;
  final Widget child, expired;
  @override
  State<CustomerSessionBoundary> createState() =>
      _CustomerSessionBoundaryState();
}

class _CustomerSessionBoundaryState extends State<CustomerSessionBoundary> {
  int _session = CustomerApi.sessionVersion;
  @override
  void didUpdateWidget(CustomerSessionBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api, widget.api)) {
      _session = CustomerApi.sessionVersion;
    }
  }

  @override
  Widget build(BuildContext context) =>
      _session == CustomerApi.sessionVersion ? widget.child : widget.expired;
}
