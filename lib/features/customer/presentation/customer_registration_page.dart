import 'package:flutter/material.dart';
import '../../../core/widgets/momiq_shimmer.dart';
import 'customer_widgets.dart';
import 'customer_account.dart';

/// Temporary manual registration while MyID is disabled.
class CustomerRegistrationPage extends StatefulWidget {
  const CustomerRegistrationPage({super.key});
  @override
  State<CustomerRegistrationPage> createState() =>
      _CustomerRegistrationPageState();
}

class _CustomerRegistrationPageState extends State<CustomerRegistrationPage> {
  final _store = CustomerStore();
  late Future<void> _load = _store.load();
  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return CustomerPage(
          title: lt('Ro‘yxatdan o‘tish', 'Registration', 'Регистрация'),
          children: [
            MomiqShimmer(
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  color: listingBorder,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        );
      }
      if (snapshot.hasError) {
        return CustomerPage(
          title: lt('Ro‘yxatdan o‘tish', 'Registration', 'Регистрация'),
          children: [
            cText(
              lt(
                'Ma’lumotlar yuklanmadi.',
                'Could not load profile.',
                'Не удалось загрузить профиль.',
              ),
            ),
            cButton(
              'Qayta urinish',
              () => setState(() => _load = _store.load()),
            ),
          ],
        );
      }
      return CustomerProfileForm(store: _store, registration: true);
    },
  );
}
