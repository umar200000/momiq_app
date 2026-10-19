import '../../../customer/presentation/customer_home_page.dart';
import '../../../../core/localization/app_language.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/onboarding_shell.dart';
import 'sitter_registration_page.dart';

class MyIdPage extends StatelessWidget {
  const MyIdPage({super.key, this.customer = false});
  final bool customer;
  @override
  Widget build(BuildContext context) => OnboardingShell(
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              minHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Image.asset(
                    'assets/images/myid_pets.png',
                    width: math.min(constraints.maxWidth * .88, 340),
                    height: math.min(constraints.maxHeight * .47, 350),
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.tr('Shaxsingizni tasdiqlang'),
                    textAlign: TextAlign.center,
                    style: profileText(27, bold: true),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.tr(
                      customer
                          ? 'Davom etish uchun MyID orqali shaxsingizni tasdiqlang.'
                          : 'Ishonchli enaga bo‘lish uchun\nMyID orqali tasdiqlang.',
                    ),
                    textAlign: TextAlign.center,
                    style: profileText(17),
                  ),
                  const SizedBox(height: 38),
                  ProfileButton(
                    label: context.tr('MyID orqali davom etish'),
                    onPressed: () {
                      // Temporary mock identity. No MyID SDK or verification request.
                      if (customer) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute<void>(
                            builder: (_) => const CustomerHomePage(),
                          ),
                          (_) => false,
                        );
                        return;
                      }
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const SitterRegistrationPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.tr('Bir necha daqiqa kifoya.'),
                    style: profileText(13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
