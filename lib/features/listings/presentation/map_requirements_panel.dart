import 'package:flutter/material.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../data/map_access.dart';
import 'listing_style.dart';

class MapRequirementsPanel extends StatelessWidget {
  const MapRequirementsPanel({super.key, required this.controller});
  final MapAccessController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      if (state == null) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: listingGold)),
        );
      }
      if (state.ready) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            lt(
              'Xarita tayyor. Davom etishingiz mumkin.',
              'Map is ready. You can continue.',
              'Карта готова. Можно продолжить.',
            ),
          ),
        );
      }
      final message = [
        if (!state.location)
          lt(
            'Telefon joylashuvini (GPS) yoqing.',
            'Turn on device location (GPS).',
            'Включите геолокацию (GPS).',
          ),
        if (state.location && !state.permission)
          lt(
            'Momiq uchun joylashuvga ruxsat bering.',
            'Allow Momiq to access your location.',
            'Разрешите Momiq доступ к геолокации.',
          ),
      ].join('\n');
      return Container(
        key: const ValueKey('mapRequirements'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFECCE),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lt(
                'Xaritani ochish uchun',
                'To open the map',
                'Чтобы открыть карту',
              ),
              style: profileText(14, bold: true),
            ),
            const SizedBox(height: 8),
            Text(message, style: profileText(12)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('mapOpenSettings'),
                  style: FilledButton.styleFrom(backgroundColor: listingGold),
                  onPressed: controller.checking ? null : controller.resolve,
                  child: Text(
                    !state.location
                        ? lt('GPS ni yoqish', 'Enable GPS', 'Включить GPS')
                        : lt(
                            'Ruxsat berish',
                            'Allow location',
                            'Разрешить доступ',
                          ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('mapCheckAgain'),
                  onPressed: controller.checking ? null : controller.refresh,
                  child: Text(
                    lt('Qayta tekshirish', 'Check again', 'Проверить снова'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
