import 'package:momiq_app/core/widgets/button_progress.dart';
import 'dart:typed_data';
import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/localization/app_language.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../../listings/presentation/listing_style.dart';
import '../data/customer_store.dart';
export '../data/customer_store.dart';
export '../../listings/presentation/listing_style.dart'
    show
        listingGold,
        listingSurface,
        listingBackground,
        listingBorder,
        priceText,
        lt;

String ct(String text) {
  final pair = _words[text];
  return pair == null
      ? text
      : switch (AppLanguage.current.value) {
          'en' => pair[0],
          'ru' => pair[1],
          _ => text,
        };
}

const _words = <String, List<String>>{
  'Bosh sahifa': ['Home', 'Главная'],
  'Buyurtmalar': ['Bookings', 'Заказы'],
  'Chatlar': ['Chats', 'Чаты'],
  'Profil': ['Profile', 'Профиль'],
  'Enagalar': ['Sitters', 'Няни'],
  'Enaga qidirish': ['Search sitters', 'Найти няню'],
  'Enaga profili': ['Sitter profile', 'Профиль няни'],
  'Enaga uyida qarash': ['At sitter’s home', 'У няни дома'],
  'Uyimga kelib qarash': ['Home visits', 'У меня дома'],
  'Shaxsiy enaga': ['Personal sitter', 'Личная няня'],
  'Saqlash': ['Save', 'Сохранить'],
  'Davom etish': ['Continue', 'Продолжить'],
  'Bekor qilish': ['Cancel', 'Отменить'],
  'Ortga': ['Back', 'Назад'],
  'Filtrlar': ['Filters', 'Фильтры'],
  'Hayvon turi': ['Pet type', 'Вид питомца'],
  'Mushuk': ['Cat', 'Кошка'],
  'It': ['Dog', 'Собака'],
  'Boshqa': ['Other', 'Другой'],
  'Hayvonni tanlang': ['Choose pet', 'Выберите питомца'],
  'Hayvon qo‘shish': ['Add pet', 'Добавить питомца'],
  'Mening hayvonlarim': ['My pets', 'Мои питомцы'],
  'Band qilish': ['Book', 'Забронировать'],
  'Parvarish sanalari': ['Care dates', 'Даты ухода'],
  'Parvarish ko‘rsatmalari': ['Care instructions', 'Указания по уходу'],
  'Buyurtmani tekshiring': ['Review booking', 'Проверьте заказ'],
  'So‘rov yuborish': ['Send request', 'Отправить заявку'],
  'So‘rov yuborildi': ['Request sent', 'Заявка отправлена'],
  'Faol': ['Active', 'Активные'],
  'Kutilmoqda': ['Pending', 'Ожидается'],
  'Tarix': ['History', 'История'],
  'Parvarishda': ['In care', 'На передержке'],
  'Tugatilgan': ['Completed', 'Завершён'],
  'Bekor qilingan': ['Cancelled', 'Отменён'],
  'Buyurtma tafsilotlari': ['Booking details', 'Детали заказа'],
  'Bugungi parvarish': ['Today’s care', 'Уход сегодня'],
  'Video hisobotlar': ['Video reports', 'Видеоотчёты'],
  'Ovqatlantirish': ['Feeding', 'Кормление'],
  'Dori berish': ['Medication', 'Лекарство'],
  'Sayr': ['Walk', 'Прогулка'],
  'Enaga bilan yozishish': ['Message sitter', 'Написать няне'],
  'Profilni tahrirlash': ['Edit profile', 'Редактировать профиль'],
  'Saqlangan enagalar': ['Saved sitters', 'Избранные няни'],
  'Manzillarim': ['My addresses', 'Мои адреса'],
  'Bildirishnomalar': ['Notifications', 'Уведомления'],
  'Til': ['Language', 'Язык'],
  'Yordam': ['Help', 'Помощь'],
  'Chiqish': ['Log out', 'Выйти'],
  'Ism': ['First name', 'Имя'],
  'Familiya': ['Last name', 'Фамилия'],
  'Ismi': ['Name', 'Кличка'],
  'Yoshi': ['Age', 'Возраст'],
  'Jinsi': ['Sex', 'Пол'],
  'Erkak': ['Male', 'Самец'],
  'Urg‘ochi': ['Female', 'Самка'],
  'Zoti': ['Breed', 'Порода'],
  'Xususiyatlari': ['Notes', 'Особенности'],
  'Rasmni almashtirish': ['Change photo', 'Изменить фото'],
  'Manzil qo‘shish': ['Add address', 'Добавить адрес'],
  'Manzilni belgilang': ['Choose address', 'Выберите адрес'],
  'Baho va fikr': ['Rating and review', 'Оценка и отзыв'],
  'Fikrni yuborish': ['Send review', 'Отправить отзыв'],
  'Tahrirlash': ['Edit', 'Изменить'],
  'Yuborish': ['Send', 'Отправить'],
  'Hech narsa topilmadi': ['Nothing found', 'Ничего не найдено'],
  'Hozircha bo‘sh': ['Nothing here yet', 'Пока пусто'],
  'Jami': ['Total', 'Итого'],
};
Widget cText(
  String text, {
  double size = 15,
  bool bold = false,
  Color? color,
}) => Text(
  ct(text),
  style: profileText(
    size,
    bold: bold,
  ).copyWith(color: color ?? AppColors.chocolate),
);
Widget cCard(Widget child, {VoidCallback? onTap}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: Material(
    color: listingSurface,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);
Widget cButton(
  String title,
  VoidCallback? onTap, {
  String? id,
  bool secondary = false,
  bool loading = false,
  IconData? icon,
}) => SizedBox(
  width: double.infinity,
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: FilledButton(
      onPressed: loading ? null : onTap,
      key: id == null ? null : ValueKey(id),
      style: FilledButton.styleFrom(
        backgroundColor: secondary ? listingSurface : listingGold,
        foregroundColor: secondary ? AppColors.chocolate : Colors.white,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: ButtonProgress(
        loading: loading,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(ct(title), textAlign: TextAlign.center)),
          ],
        ),
      ),
    ),
  ),
);
Widget cRow(IconData icon, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(
    children: [
      Icon(icon, size: 19, color: AppColors.brown),
      const SizedBox(width: 10),
      Expanded(child: cText(text, size: 13)),
    ],
  ),
);
Widget cField(
  TextEditingController controller,
  String label, {
  String? id,
  int lines = 1,
  bool required = false,
  bool number = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextFormField(
    key: id == null ? null : ValueKey(id),
    controller: controller,
    maxLines: lines,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    decoration: InputDecoration(
      labelText: ct(label),
      filled: true,
      fillColor: listingSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: listingBorder),
      ),
    ),
    validator: (value) => required && (value == null || value.trim().isEmpty)
        ? lt('To‘ldiring', 'Required', 'Обязательное поле')
        : null,
  ),
);
void cNotice(BuildContext context, String text) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(ct(text))));
Future<T?> cPush<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
Future<void> cAction(BuildContext context, Future<void> Function() task) async {
  try {
    await task();
  } catch (_) {
    if (context.mounted) {
      cNotice(
        context,
        lt(
          'Amal bajarilmadi. Qayta urinib ko‘ring.',
          'Action failed. Please retry.',
          'Не удалось выполнить. Повторите.',
        ),
      );
    }
  }
}

class CustomerPage extends StatelessWidget {
  const CustomerPage({
    super.key,
    required this.title,
    required this.children,
    this.bottom,
    this.actions,
  });
  final String title;
  final List<Widget> children;
  final Widget? bottom;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => MomiqScaffold(
    backgroundColor: listingBackground,
    appBar: AppBar(
      backgroundColor: listingBackground,
      foregroundColor: AppColors.chocolate,
      title: cText(title, size: 20, bold: true),
      actions: actions,
    ),
    body: SafeArea(
      child: ListView(padding: const EdgeInsets.all(18), children: children),
    ),
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: bottom,
            ),
          ),
  );
}

class SitterPortrait extends StatelessWidget {
  const SitterPortrait({super.key, required this.index, this.size = 70});
  final Object? index;
  final double size;
  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (index is String) {
      try {
        bytes = base64Decode(index as String);
      } catch (_) {}
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null
            ? const Icon(Icons.person_outline)
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person_outline),
              ),
      ),
    );
  }
}

class CustomerPetArt extends StatelessWidget {
  const CustomerPetArt({super.key, required this.pet, this.size = 64});
  final CJson pet;
  final double size;
  @override
  Widget build(BuildContext context) {
    final photo = pet['photo'];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: size,
        height: size,
        child: photo != null
            ? Image.memory(base64Decode(photo as String), fit: BoxFit.cover)
            : pet['type'] == 'Boshqa'
            ? Container(
                color: listingSurface,
                child: Icon(
                  Icons.pets_outlined,
                  size: size * .55,
                  color: AppColors.brown,
                ),
              )
            : Image.asset(
                'assets/images/service_${pet['type'] == 'It' ? 'dog' : 'cat'}.png',
                fit: BoxFit.contain,
              ),
      ),
    );
  }
}

Widget cRating(String value) => Row(
  children: [
    const Icon(Icons.star_rounded, size: 18, color: listingGold),
    const SizedBox(width: 4),
    Expanded(child: cText(value, color: listingGold, size: 13)),
  ],
);
