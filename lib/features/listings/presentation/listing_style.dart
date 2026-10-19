import 'package:flutter/material.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../data/listing_store.dart';

String lt(String uz, String en, String ru) =>
    switch (AppLanguage.current.value) {
      'en' => en,
      'ru' => ru,
      _ => uz,
    };
String serviceTitle(ServiceType type) => switch (type) {
  ServiceType.boarding => lt(
    'O‘z uyimda qarash',
    'Care at my home',
    'У себя дома',
  ),
  ServiceType.homeVisit => lt(
    'Mijoz uyiga borib qarash',
    'Care at client’s home',
    'У клиента дома',
  ),
  ServiceType.personal => lt(
    'Shaxsiy enaga',
    'Personal pet sitter',
    'Личная няня',
  ),
};
String petTitle(PetType pet) => pet == PetType.dog
    ? lt('It', 'Dog', 'Собака')
    : lt('Mushuk', 'Cat', 'Кошка');
IconData serviceIcon(ServiceType type) => switch (type) {
  ServiceType.boarding => Icons.home_rounded,
  ServiceType.homeVisit => Icons.directions_walk_rounded,
  ServiceType.personal => Icons.volunteer_activism_rounded,
};
String problemText(ListingProblem? problem) => switch (problem) {
  ListingProblem.pets => lt(
    'Hayvonni tanlang.',
    'Choose a pet.',
    'Выберите животное.',
  ),
  ListingProblem.capacity => lt(
    'Hayvonlar sonini tekshiring.',
    'Check pet capacity.',
    'Проверьте количество животных.',
  ),
  ListingProblem.location => lt(
    'Manzilni xaritadan belgilang.',
    'Select a location on the map.',
    'Укажите адрес на карте.',
  ),
  ListingProblem.price => lt(
    'Kunlik narxni kiriting.',
    'Enter a positive daily price.',
    'Введите стоимость за день.',
  ),
  ListingProblem.conflict => lt(
    'Avval boshqa faol xizmatlarni o‘chiring.',
    'Deactivate conflicting services first.',
    'Сначала отключите другие активные услуги.',
  ),
  _ => lt(
    'Saqlanmadi. Qayta urinib ko‘ring.',
    'Could not save. Please retry.',
    'Не удалось сохранить. Повторите попытку.',
  ),
};
String priceText(int price) => price.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]} ',
);
const listingGold = Color(0xFFBD8C43);
const listingSurface = Color(0xFFFAF6F0);
const listingBackground = Color(0xFFEFE4D8);
const listingBorder = Color(0xFFE4D7C9);
const listingAccent = Color(0xFFA55C08);

Widget serviceSurface(
  Widget child, {
  EdgeInsets padding = const EdgeInsets.all(14),
}) => Container(
  width: double.infinity,
  padding: padding,
  decoration: BoxDecoration(
    color: listingSurface,
    borderRadius: BorderRadius.circular(16),
  ),
  child: child,
);

Widget sectionLabel(String title, {String? hint}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: title.replaceAll(' *', '')),
            if (title.endsWith('*'))
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFC94130)),
              ),
          ],
        ),
        style: profileText(15, bold: true),
      ),
      if (hint != null) ...[
        const SizedBox(height: 3),
        Text(hint, style: profileText(11)),
      ],
    ],
  ),
);

ButtonStyle serviceButtonStyle({bool primary = true}) => FilledButton.styleFrom(
  backgroundColor: listingGold,
  foregroundColor: Colors.white,
  disabledBackgroundColor: const Color(0xFFCEC3BB),
  disabledForegroundColor: Colors.white,
  minimumSize: const Size(double.infinity, 44),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  textStyle: profileText(14, bold: true),
);

class ServiceMark extends StatelessWidget {
  const ServiceMark({super.key, required this.type, this.size = 48});
  final ServiceType type;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            type == ServiceType.personal
                ? Icons.favorite_border_rounded
                : Icons.home_outlined,
            size: size,
            color: AppColors.chocolate,
          ),
          Positioned(
            top: size * .41,
            child: Container(
              color: listingSurface,
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Icon(
                Icons.pets_rounded,
                size: size * .39,
                color: AppColors.chocolate,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ServicePetPhoto extends StatelessWidget {
  const ServicePetPhoto({super.key, required this.pet, this.height = 100});
  final PetType pet;
  final double height;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      'assets/images/service_${pet.name}.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    ),
  );
}
