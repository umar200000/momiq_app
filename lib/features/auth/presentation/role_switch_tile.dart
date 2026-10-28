import 'package:flutter/material.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../customer/data/customer_api.dart';
import 'session_destination.dart';

class RoleSwitchTile extends StatefulWidget {
  const RoleSwitchTile({super.key, required this.customer});
  final bool customer;
  @override
  State<RoleSwitchTile> createState() => _RoleSwitchTileState();
}

class _RoleSwitchTileState extends State<RoleSwitchTile> {
  bool _busy = false;
  Future<void> _switch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final account = await CustomerApi.switchRole(customer: widget.customer);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) =>
              accountDestination(account, customer: widget.customer),
        ),
        (_) => false,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey(widget.customer ? 'switchToCustomer' : 'switchToSitter'),
    leading: _busy
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(),
          )
        : const Icon(Icons.swap_horiz),
    title: Text(
      widget.customer
          ? lt(
              'Mijoz rejimiga o‘tish',
              'Switch to customer',
              'Перейти в режим клиента',
            )
          : lt(
              'Enaga rejimiga o‘tish',
              'Switch to sitter',
              'Перейти в режим няни',
            ),
    ),
    subtitle: Text(
      lt(
        'Hisobingiz va buyurtmalaringiz saqlanadi.',
        'Your account and bookings are preserved.',
        'Ваш аккаунт и заказы сохраняются.',
      ),
    ),
    onTap: _busy ? null : _switch,
  );
}
