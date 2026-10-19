import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage extends InheritedNotifier<ValueNotifier<String>> {
  AppLanguage({super.key, required super.child}) : super(notifier: current);
  static final current = ValueNotifier<String>('uz');
  static Future<void> restore() async {
    final value = (await SharedPreferences.getInstance()).getString('language');
    if (['uz', 'en', 'ru'].contains(value)) current.value = value!;
  }

  static Future<void> select(String value) async {
    current.value = value;
    await (await SharedPreferences.getInstance()).setString('language', value);
  }
}

extension Translation on BuildContext {
  String tr(String text) {
    dependOnInheritedWidgetOfExactType<AppLanguage>();
    final language = AppLanguage.current.value;
    if (language == 'uz') {
      if (text == 'otpDescription') {
        return '{phone} raqamiga\nyuborilgan 6 xonali kod';
      }
      if (text == 'photoTotal') return '{count} / 9 ta rasm';
      return text;
    }
    return _translations[text]?[language == 'en' ? 0 : 1] ?? text;
  }
}

const _translations = <String, List<String>>{
  'Davom etish uchun MyID orqali shaxsingizni tasdiqlang.': [
    'Verify your identity with MyID to continue.',
    'Подтвердите личность через MyID, чтобы продолжить.',
  ],
  'Rolingizni tanlang': ['Choose your role', 'Выберите роль'],
  'Mijozman': ['Pet owner', 'Владелец'],
  'Enagaman': ['Pet sitter', 'Няня'],
  'Davom etish': ['Continue', 'Продолжить'],
  'Orqaga': ['Back', 'Назад'],
  'Telefon raqamingiz': ['Your phone number', 'Ваш номер телефона'],
  'Boshlash uchun raqamingizni kiriting': [
    'Enter your number to get started',
    'Введите номер, чтобы начать',
  ],
  'Kod yuborish': ['Send code', 'Отправить код'],
  'SMS kodni kiriting': ['Enter SMS code', 'Введите код из SMS'],
  '6 xonali SMS kod': ['6-digit SMS code', '6-значный код из SMS'],
  'Kodni qayta jo‘natish': ['Resend code', 'Отправить код повторно'],
  'Qayta jo‘natish': ['Resend', 'Повторить'],
  'Shaxsingizni tasdiqlang': ['Verify your identity', 'Подтвердите личность'],
  'Ishonchli enaga bo‘lish uchun\nMyID orqali tasdiqlang.': [
    'Verify with MyID\nto become a trusted pet sitter.',
    'Пройдите проверку MyID,\nчтобы стать проверенной няней.',
  ],
  'MyID orqali davom etish': ['Continue with MyID', 'Продолжить с MyID'],
  'Bir necha daqiqa kifoya.': [
    'It only takes a few minutes.',
    'Это займёт всего пару минут.',
  ],
  'Ro‘yxatdan o‘tish': ['Sign up', 'Регистрация'],
  'Galereya': ['Gallery', 'Галерея'],
  'Kamera': ['Camera', 'Камера'],
  'Profil tayyor!': ['Profile ready!', 'Профиль готов!'],
  'Tahrirlash': ['Edit', 'Редактировать'],
  'Profil rasmini yuklash yoki almashtirish': [
    'Add or change profile photo',
    'Добавить или изменить фото профиля',
  ],
  'Profil rasmi *': ['Profile photo *', 'Фото профиля *'],
  'Ism': ['First name', 'Имя'],
  'Familiya': ['Last name', 'Фамилия'],
  'Qaysi hayvonlarga qaraysiz?': [
    'Which pets can you care for?',
    'За какими животными вы ухаживаете?',
  ],
  'Bir nechtasini tanlashingiz mumkin.': [
    'You can select several.',
    'Можно выбрать несколько.',
  ],
  'It': ['Dog', 'Собака'],
  'Mushuk': ['Cat', 'Кошка'],
  'Qush': ['Bird', 'Птица'],
  'Baliq': ['Fish', 'Рыба'],
  'Quyon': ['Rabbit', 'Кролик'],
  'Toshbaqa': ['Turtle', 'Черепаха'],
  'Boshqa': ['Other', 'Другое'],
  'Hayvon qo‘shish': ['Add an animal', 'Добавить животное'],
  'Hayvon nomini tahrirlash': [
    'Edit animal name',
    'Изменить название животного',
  ],
  'Hayvon nomini yozing': ['Enter animal name', 'Введите название животного'],
  'Qo‘shish': ['Add', 'Добавить'],
  'Saqlash': ['Save', 'Сохранить'],
  'Tajribangiz': ['Your experience', 'Ваш опыт'],
  'Necha yildan beri?': ['How many years?', 'Сколько лет?'],
  'yil': ['years', 'лет'],
  'Tajribangiz haqida': ['About your experience', 'Расскажите о своём опыте'],
  'Hayvonlarga qanday g‘amxo‘rlik qilasiz?': [
    'How do you care for animals?',
    'Как вы заботитесь о животных?',
  ],
  'Uy rasmlari': ['Home photos', 'Фото дома'],
  'Kamida 3 ta, ko‘pi bilan 9 ta.': [
    'At least 3, up to 9 photos.',
    'От 3 до 9 фотографий.',
  ],
  'Rasmni olib tashlash': ['Remove photo', 'Удалить фото'],
  'Qayerda xizmat ko‘rsatasiz?': [
    'Where can you provide care?',
    'Где вы готовы ухаживать?',
  ],
  'Ikkalasini ham tanlash mumkin.': [
    'You can select both.',
    'Можно выбрать оба варианта.',
  ],
  'O‘z uyimda': ['At my home', 'У себя дома'],
  'Mijozning uyida': ['At the owner\'s home', 'У владельца дома'],
  'Profil rasmi va kamida 3 ta uy rasmini yuklang.': [
    'Add a profile photo and at least 3 home photos.',
    'Добавьте фото профиля и минимум 3 фото дома.',
  ],
  'Rasmni ochib bo‘lmadi. Kamera yoki galereya ruxsatini tekshirib, qayta urinib ko‘ring.': [
    'Could not open the photo. Check camera or gallery access and try again.',
    'Не удалось открыть фото. Проверьте доступ к камере или галерее и повторите попытку.',
  ],
  'otpDescription': [
    '6-digit code sent to {phone}',
    '6-значный код, отправленный на {phone}',
  ],
  'photoTotal': ['{count} / 9 photos', '{count} / 9 фото'],
};
