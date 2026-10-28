import 'package:flutter/material.dart';
import '../../listings/presentation/listing_style.dart' show lt;

const petSafetyFields = [
  'vaccinations',
  'allergies',
  'medications',
  'behavior',
  'emergencyName',
  'emergencyPhone',
];
int petSafetyLimit(String field) => switch (field) {
  'emergencyName' => 120,
  'emergencyPhone' => 16,
  _ => 2000,
};
String petSafetyLabel(String field) => switch (field) {
  'vaccinations' => lt(
    'Emlash va pasport ma’lumoti',
    'Vaccinations and passport notes',
    'Прививки и сведения о паспорте',
  ),
  'allergies' => lt('Allergiyalar', 'Allergies', 'Аллергии'),
  'medications' => lt(
    'Dorilar va egasining ko‘rsatmalari',
    'Medicines and owner instructions',
    'Лекарства и указания владельца',
  ),
  'behavior' => lt(
    'Xulqi va ehtiyot choralari',
    'Behavior and precautions',
    'Поведение и меры предосторожности',
  ),
  'emergencyName' => lt(
    'Favqulodda kontakt ismi',
    'Emergency contact name',
    'Имя экстренного контакта',
  ),
  'emergencyPhone' => lt(
    'Favqulodda telefon (+998...)',
    'Emergency phone (+998...)',
    'Экстренный телефон (+998...)',
  ),
  _ => field,
};
String? validatePetSafety(String field, String? raw) {
  final value = raw ?? '';
  if (value.length > petSafetyLimit(field) ||
      value.runes.any((c) => c < 32 && c != 10 && c != 9)) {
    return lt(
      'Matn juda uzun yoki yaroqsiz.',
      'Text is too long or invalid.',
      'Текст слишком длинный или недопустимый.',
    );
  }
  if (field == 'emergencyPhone' &&
      value.trim().isNotEmpty &&
      !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value.trim())) {
    return lt(
      '+ va davlat kodi bilan kiriting.',
      'Enter + and the country code.',
      'Введите + и код страны.',
    );
  }
  return null;
}

class PetSafetyFields extends StatelessWidget {
  const PetSafetyFields({super.key, required this.controllers});
  final Map<String, TextEditingController> controllers;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        lt(
          'Parvarish uchun ma’lumot',
          'Care information',
          'Сведения для ухода',
        ),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        lt(
          'Bilmagan maydonni bo‘sh qoldiring. Bo‘sh maydon «muammo yo‘q» degani emas. Ma’lumotlar faqat hisobingiz va shu hayvon buyurtmasida ko‘rinadi. Favqulodda kontakt enagaga buyurtma qabul qilingach ko‘rsatiladi. Pasport rasmini bron berishda qo‘shishingiz mumkin.',
          'Leave unknown fields empty. Empty does not mean no issues. These details appear only in your account and this pet’s bookings. The sitter sees the emergency contact after accepting. You can attach a passport image when booking.',
          'Неизвестные сведения оставьте пустыми. Пустое поле не означает отсутствие проблем. Данные доступны в вашем профиле и заказах этого питомца. Экстренный контакт доступен няне после принятия заказа. Фото паспорта можно добавить при бронировании.',
        ),
      ),
      const SizedBox(height: 16),
      for (final field in petSafetyFields)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            key: ValueKey('petSafety-$field'),
            controller: controllers[field],
            maxLength: petSafetyLimit(field),
            maxLines: field.startsWith('emergency') ? 1 : 3,
            keyboardType: field == 'emergencyPhone'
                ? TextInputType.phone
                : TextInputType.multiline,
            validator: (value) => validatePetSafety(field, value),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              labelText: petSafetyLabel(field),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
    ],
  );
}

class PetSafetySummary extends StatelessWidget {
  const PetSafetySummary({super.key, required this.pet});
  final Map<String, dynamic> pet;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final field in petSafetyFields)
        if ((pet[field] as String? ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${petSafetyLabel(field)}: ${pet[field]}',
              key: ValueKey('petSafetySummary-$field'),
            ),
          ),
      Text(
        lt(
          'Egasi kiritgan ma’lumotlar; Momiq emlashni tasdiqlamaydi yoki davolash tavsiya qilmaydi. Ko‘rsatilmagan ma’lumot noma’lum hisoblanadi.',
          'Owner supplied information; Momiq does not verify vaccinations or recommend treatment. Missing information is unknown.',
          'Сведения предоставлены владельцем; Momiq не подтверждает прививки и не назначает лечение. Неуказанные сведения неизвестны.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
