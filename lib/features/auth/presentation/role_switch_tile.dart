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
  final _sessionVersion = CustomerApi.sessionVersion;
  final _source = CustomerApi.active;
  bool _busy = false;

  bool get _current =>
      mounted &&
      _sessionVersion == CustomerApi.sessionVersion &&
      (_source == null || identical(_source, CustomerApi.active));
  Future<void> _switch() async {
    if (!_current || _busy || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final customer = widget.customer;
    setState(() => _busy = true);
    try {
      final account = await CustomerApi.switchRole(customer: customer);
      if (!mounted ||
          CustomerApi.sessionVersion != _sessionVersion + 1 ||
          (_source != null && !identical(CustomerApi.active, _source)) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => accountDestination(account, customer: customer),
        ),
        (_) => false,
      );
    } catch (_) {
      if (_current && ModalRoute.of(context)?.isCurrent != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lt(
                'Rejimni almashtirib bo‘lmadi. Qayta urinib ko‘ring.',
                'Could not switch modes. Please retry.',
                'Не удалось сменить режим. Повторите попытку.',
              ),
            ),
          ),
        );
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
    onTap: _busy || !_current ? null : _switch,
  );
}
