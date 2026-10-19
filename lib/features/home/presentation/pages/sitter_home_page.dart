import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../profile/presentation/mock_profile_page.dart';
import '../../../care/presentation/daily_care_page.dart';
import '../../../../core/theme/brand_typography.dart';
import '../../../../core/widgets/momiq_logo.dart';
import '../../../listings/presentation/listing_style.dart';
import '../../../listings/presentation/listings_panel.dart';
import '../../../../core/widgets/animal_art.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/localization/app_language.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../onboarding/presentation/widgets/onboarding_shell.dart';

class SitterHomePage extends StatefulWidget {
  const SitterHomePage({
    super.key,
    this.avatar,
    this.firstName = 'Hoji',
    this.lastName = 'Sherhojiyiv',
    this.careAnimalCount = 2,
  });
  final Uint8List? avatar;
  final String firstName;
  final String lastName;
  final int careAnimalCount;
  @override
  State<SitterHomePage> createState() => _SitterHomePageState();
}

class _SitterHomePageState extends State<SitterHomePage> {
  late String _firstName = widget.firstName;
  late String _lastName = widget.lastName;
  Uint8List? _profileAvatar;
  @override
  void initState() {
    super.initState();
    _profileAvatar = widget.avatar;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final photo = prefs.getString('mock.profile.avatar');
    Uint8List? bytes;
    try {
      if (photo != null) bytes = base64Decode(photo);
    } catch (_) {
      bytes = null;
    }
    setState(() {
      _firstName = prefs.getString('mock.profile.first') ?? widget.firstName;
      _lastName = prefs.getString('mock.profile.last') ?? widget.lastName;
      _profileAvatar = bytes ?? widget.avatar;
    });
  }

  Future<void> _openProfileSection(int section) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MockProfilePage(
          section: section,
          firstName: _firstName,
          lastName: _lastName,
          avatar: _profileAvatar,
        ),
      ),
    );
    if (mounted) await _loadProfile();
  }

  int _tab = 0;
  int _orderTab = 0;
  String t(String uz, String en, String ru) =>
      switch (AppLanguage.current.value) {
        'en' => en,
        'ru' => ru,
        _ => uz,
      };
  String get fullName => '$_firstName $_lastName';
  Widget text(
    String value, {
    double size = 15,
    bool bold = false,
    Color? color,
  }) => Text(
    value,
    style: profileText(size, bold: bold).copyWith(color: color),
    softWrap: true,
  );
  Widget title(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: text(value, size: 20, bold: true),
  );
  Widget card(Widget child, {Color color = formSurface}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: AppColors.chocolate.withValues(alpha: .035),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
  Widget pill(String value, {Color color = AppColors.yellow}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: text(value, size: 12, bold: true),
  );
  Widget avatar({double radius = 25}) => CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.yellow,
    backgroundImage: _profileAvatar == null
        ? null
        : MemoryImage(_profileAvatar!),
    child: _profileAvatar == null
        ? const Icon(Icons.person_outline_rounded, color: AppColors.brown)
        : null,
  );
  Widget line(IconData icon, String value) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppColors.brown),
        const SizedBox(width: 9),
        Expanded(child: text(value, size: 13, color: AppColors.brown)),
      ],
    ),
  );
  Widget stat(String value, String label, IconData icon) => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.brown, size: 22),
        const SizedBox(height: 12),
        text(value, size: 23, bold: true),
        const SizedBox(height: 4),
        text(label, size: 12),
      ],
    ),
  );
  Widget pair(Widget left, Widget right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 12),
      Expanded(child: right),
    ],
  );

  Widget petArt({double size = 110, bool cat = false}) =>
      AnimalArt(index: cat ? 0 : 1, size: size);
  Widget banner(
    String heading,
    String subtitle, {
    bool cat = false,
    bool petPair = false,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.fromLTRB(20, 20, 8, 18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFF6DDA4), Color(0xFFEFC77B)],
      ),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text(heading, size: 24, bold: true),
              const SizedBox(height: 10),
              text(subtitle, size: 13, color: AppColors.brown),
            ],
          ),
        ),
        petPair
            ? Image.asset(
                'assets/images/home_pet_pair.png',
                width: 120,
                height: 130,
                fit: BoxFit.contain,
              )
            : petArt(size: 110, cat: cat),
      ],
    ),
  );

  Widget chart() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        text(
          t('Oxirgi 6 oy', 'Last 6 months', 'Последние 6 месяцев'),
          bold: true,
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 125,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
              6,
              (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: [30.0, 46.0, 40.0, 62.0, 72.0, 96.0][i],
                        decoration: BoxDecoration(
                          color: i == 5
                              ? AppColors.gold
                              : const Color(0xFFE5D9C8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      text(['04', '05', '06', '07', '08', '09'][i], size: 11),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget order({bool request = false, int index = 0}) {
    const pets = ['Momi', 'Rex', 'Oppoq', 'Tosh', 'Chitti', 'Oltin', 'Boshqa'];
    const species = [
      'Mushuk',
      'It',
      'Quyon',
      'Toshbaqa',
      'Qush',
      'Baliq',
      'Boshqa',
    ];
    const clients = [
      'Madina Karimova',
      'Javohir Akmalov',
      'Dilnoza Aliyeva',
      'Sardor Umarov',
      'Malika Sobirova',
      'Akmal Usmonov',
      'Shahnoza Azimova',
    ];

    final name = request
        ? (index == 6 ? context.tr('Boshqa') : pets[index])
        : 'Boni';
    final days = request ? [3, 2, 4, 5, 2, 3, 4][index] : (index == 0 ? 5 : 3);
    // Demo bookings include both the first and last care day.
    final careEnd = DateTime(2026, 9, 28).add(Duration(days: days - 1));
    final endUz = '${careEnd.day} ${careEnd.month == 9 ? 'sentabr' : 'oktabr'}';
    final endEn = '${careEnd.day} ${careEnd.month == 9 ? 'Sep' : 'Oct'}';
    final endRu =
        '${careEnd.day} ${careEnd.month == 9 ? 'сентября' : 'октября'}';
    final price = request
        ? [
            '360 000',
            '240 000',
            '280 000',
            '250 000',
            '120 000',
            '150 000',
            '400 000',
          ][index]
        : '600 000';
    return Container(
      key: ValueKey(
        request
            ? 'request-$index'
            : (index == 0 ? 'accepted-booking' : 'accepted-cat'),
      ),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: formSurface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.gold.withValues(alpha: .22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFFF7E2BA), formSurface],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      pill(
                        request
                            ? t('Yangi so‘rov', 'New request', 'Новая заявка')
                            : t('Qabul qilingan', 'Accepted', 'Принят'),
                        color: formSurface,
                      ),
                      const SizedBox(height: 10),
                      text(name, size: 25, bold: true),
                      const SizedBox(height: 4),
                      text(
                        context.tr(
                          request
                              ? species[index]
                              : (index == 0 ? 'It' : 'Mushuk'),
                        ),
                        size: 13,
                        color: AppColors.brown,
                      ),
                      const SizedBox(height: 8),
                      text(
                        request
                            ? '#MQ-${(248 + index).toString().padLeft(4, '0')}'
                            : (index == 0 ? '#MQ-0241' : '#MQ-0242'),
                        size: 11,
                        color: AppColors.brown,
                      ),
                    ],
                  ),
                ),
                AnimalArt(
                  index: request ? index : (index == 0 ? 1 : 0),
                  size: 120,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line(
                  Icons.person_outline_rounded,
                  request
                      ? clients[index]
                      : (index == 0 ? 'Aziz Rahimov' : 'Nodira Sobirova'),
                ),
                line(
                  Icons.calendar_today_outlined,
                  t(
                    '28 sentabrdan ${endUz}gacha\nJami $days kun',
                    '28 Sep to $endEn\n$days days total',
                    'С 28 сентября по $endRu\nВсего $days дн.',
                  ),
                ),
                line(
                  Icons.home_outlined,
                  context.tr(
                    (request && index >= 2) || index.isOdd
                        ? 'Mijozning uyida'
                        : 'O‘z uyimda',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: text(
                        t('$price so‘m', '$price UZS', '$price сум'),
                        size: 21,
                        bold: true,
                      ),
                    ),
                    Transform.rotate(
                      angle: .3,
                      child: Opacity(
                        opacity: .3,
                        child: SvgPicture.asset(
                          'assets/svg/paw.svg',
                          width: 30,
                        ),
                      ),
                    ),
                  ],
                ),
                if (request) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: requestAction(accept: false)),
                      const SizedBox(width: 10),
                      Expanded(child: requestAction(accept: true)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget requestAction({required bool accept}) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: accept ? AppColors.gold : const Color(0xFFECE0D5),
      borderRadius: BorderRadius.circular(14),
    ),
    alignment: Alignment.center,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        accept
            ? t('Qabul qilish', 'Accept', 'Принять')
            : t('Rad etish', 'Decline', 'Отклонить'),
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: profileText(
          14,
          bold: true,
        ).copyWith(color: accept ? AppColors.chocolate : AppColors.brown),
      ),
    ),
  );
  Widget compactCare() => GestureDetector(
    key: const ValueKey('openDailyCare'),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DailyCarePage())),
    child: card(
      Row(
        children: [
          Image.asset(
            'assets/images/daily_pet_care.png',
            width: 64,
            height: 64,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text(
                  t('Bugungi parvarish', 'Today’s care', 'Уход сегодня'),
                  bold: true,
                ),
                const SizedBox(height: 5),
                Text(
                  t(
                    '${widget.careAnimalCount} ta hayvonga qarashingiz kerak',
                    '${widget.careAnimalCount} ${widget.careAnimalCount == 1 ? 'pet needs' : 'pets need'} your care',
                    'Сегодня под вашей заботой: ${widget.careAnimalCount}',
                  ),
                  key: const ValueKey('careAnimalSubtitle'),
                  style: profileText(12).copyWith(color: AppColors.brown),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.brown),
        ],
      ),
    ),
  );
  Widget roundedViewport(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: ClipRRect(
      key: const ValueKey('roundedHomeViewport'),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: child,
    ),
  );

  Widget roundedNavigation(Widget child) => ClipRRect(
    key: const ValueKey('roundedHomeNavigation'),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    child: child,
  );
  List<Widget> overview() => [
    banner(
      petPair: true,
      t(
        'Mehringizni\nkutishmoqda',
        'Ready for\nyour care',
        'Они ждут\nвашей заботы',
      ),
      t(
        'Yangi mehmonlar bilan tanishing.',
        'Meet your next little guests.',
        'Познакомьтесь с новыми гостями.',
      ),
    ),
    compactCare(),
    title(t('Yangi buyurtmalar · 2', 'New bookings · 2', 'Новые заказы · 2')),
    for (var i = 0; i < 2; i++) order(request: true, index: i),
  ];
  List<String> get orderLabels => [
    t('Qabul qilingan', 'Accepted', 'Принятые'),
    t('Yangi', 'New', 'Новые'),
    t('Tarix', 'History', 'История'),
  ];

  Widget orderTabs() => Row(
    children: List.generate(3, (i) {
      final selected = _orderTab == i;
      return Expanded(
        flex: i == 0 ? 5 : 3,
        child: Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
          child: Semantics(
            selected: selected,
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('orderStatus-$i'),
                borderRadius: BorderRadius.circular(13),
                onTap: () => setState(() => _orderTab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.yellow : formSurface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected ? AppColors.gold : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            orderLabels[i],
                            maxLines: 1,
                            softWrap: false,
                            style: profileText(12, bold: selected),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.gold
                                  : AppColors.cream,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: text(
                              i == 1 ? '7' : '2',
                              size: 10,
                              bold: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }),
  );
  Widget pastOrder(bool completed) => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AnimalArt(index: 0, size: 76),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  text(completed ? 'Luna' : 'Mimi', size: 23, bold: true),
                  const SizedBox(height: 6),
                  pill(
                    completed
                        ? t('Tugatilgan', 'Completed', 'Завершён')
                        : t('Rad etilgan', 'Declined', 'Отклонён'),
                    color: completed
                        ? const Color(0xFFDCE5CF)
                        : const Color(0xFFEBDAD0),
                  ),
                ],
              ),
            ),
          ],
        ),
        line(
          Icons.person_outline_rounded,
          completed
              ? 'Dilnoza Aliyeva · #MQ-0235'
              : 'Malika Sobirova · #MQ-0230',
        ),
        line(
          Icons.calendar_today_outlined,
          t(
            '20–22 sentabr · 3 kun',
            '20–22 Sep · 3 days',
            '20–22 сент. · 3 дня',
          ),
        ),
        const SizedBox(height: 14),
        text(
          t('300 000 so‘m', '300,000 UZS', '300 000 сум'),
          size: 20,
          bold: true,
        ),
      ],
    ),
  );

  List<Widget> orders() => [
    const SizedBox(height: 8),
    orderTabs(),
    title(orderLabels[_orderTab]),
    if (_orderTab == 0) ...[order(), order(index: 1)],
    if (_orderTab == 1)
      for (var i = 0; i < 7; i++) order(request: true, index: i),
    if (_orderTab == 2) ...[pastOrder(true), pastOrder(false)],
  ];
  List<Widget> chats() => [
    card(
      Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.brown),
          const SizedBox(width: 12),
          Expanded(
            child: text(
              t(
                'Suhbatlarni qidirish',
                'Search conversations',
                'Поиск переписки',
              ),
              color: AppColors.brown,
            ),
          ),
        ],
      ),
    ),
    for (final item in [
      ('Madina Karimova', 'Momi', '#MQ-0248', '10:24'),
      ('Aziz Rahimov', 'Boni', '#MQ-0241', '09:15'),
    ])
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.yellow,
                  child: text(item.$1[0], size: 20, bold: true),
                ),
                const SizedBox(width: 12),
                Expanded(child: text(item.$1, bold: true)),
                text(item.$4, size: 12),
              ],
            ),
            const SizedBox(height: 12),
            pill('${item.$3} · ${item.$2}'),
            const SizedBox(height: 12),
            text(
              t(
                'Salom, hayvonim haqida gaplashsak.',
                'Hello, can we talk about my pet?',
                'Здравствуйте, обсудим уход за питомцем?',
              ),
              size: 14,
              color: AppColors.brown,
            ),
          ],
        ),
      ),
  ];
  Widget earningsSummary() => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        text(
          t('Sentabr · 2026', 'September · 2026', 'Сентябрь · 2026'),
          size: 13,
          color: AppColors.brown,
        ),
        const SizedBox(height: 8),
        text(
          t('2 400 000 so‘m', '2,400,000 UZS', '2 400 000 сум'),
          size: 28,
          bold: true,
        ),
        const SizedBox(height: 12),
        pill(
          t(
            '+33% o‘tgan oyga nisbatan',
            '+33% from last month',
            '+33% к прошлому месяцу',
          ),
          color: const Color(0xFFDCE5CF),
        ),
        const SizedBox(height: 12),
        text(
          t(
            'O‘tgan oy: 1 800 000 so‘m',
            'Last month: 1,800,000 UZS',
            'Прошлый месяц: 1 800 000 сум',
          ),
          size: 13,
        ),
      ],
    ),
  );
  List<Widget> earnings() => [
    banner(
      t('Mehringiz qadrlanadi', 'Your care matters', 'Ваша забота ценна'),
      t(
        'Har bir g‘amxo‘rlik — yangi imkoniyat.',
        'Every visit brings a new opportunity.',
        'Каждая встреча — новая возможность.',
      ),
    ),
    chart(),
    earningsSummary(),
    pair(
      stat(
        '12',
        t('Tugatilgan buyurtma', 'Completed bookings', 'Завершённые заказы'),
        Icons.task_alt_rounded,
      ),
      stat(
        '24',
        t('Qarov kunlari', 'Care days', 'Дни ухода'),
        Icons.calendar_month_outlined,
      ),
    ),
    title(
      t(
        'Qaysi hayvonlarga qaradingiz',
        'Pets you cared for',
        'За кем вы ухаживали',
      ),
    ),
    card(
      Column(
        children: [
          line(
            Icons.pets_outlined,
            t(
              'It · 7 buyurtma · 15 kun',
              'Dogs · 7 bookings · 15 days',
              'Собаки · 7 заказов · 15 дней',
            ),
          ),
          line(
            Icons.pets_outlined,
            t(
              'Mushuk · 5 buyurtma · 9 kun',
              'Cats · 5 bookings · 9 days',
              'Кошки · 5 заказов · 9 дней',
            ),
          ),
        ],
      ),
    ),
    title(
      t(
        'Oxirgi tugatilgan buyurtma',
        'Latest completed booking',
        'Последний завершённый заказ',
      ),
    ),
    card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          text('Luna · ${context.tr('Mushuk')}', bold: true),
          line(Icons.person_outline, 'Dilnoza Aliyeva · #MQ-0235'),
          line(
            Icons.calendar_today_outlined,
            t(
              '20–22 sentabr · 3 kun',
              '20–22 Sep · 3 days',
              '20–22 сент. · 3 дня',
            ),
          ),
          const SizedBox(height: 12),
          text(
            t('300 000 so‘m', '300,000 UZS', '300 000 сум'),
            size: 20,
            bold: true,
          ),
        ],
      ),
    ),
  ];
  List<Widget> profile() => [
    banner(
      t('Momiq oilasidasiz', 'Part of Momiq', 'Вы в семье Momiq'),
      t(
        'Mehr ulashadigan insonlar uchun.',
        'For people who love to care.',
        'Для тех, кто любит заботиться.',
      ),
      cat: true,
    ),
    card(
      Column(
        children: [
          avatar(radius: 44),
          const SizedBox(height: 12),
          text(fullName, size: 21, bold: true),
          const SizedBox(height: 8),
          pill(t('Enaga', 'Pet sitter', 'Няня')),
        ],
      ),
    ),
    for (final entry in [
      (
        Icons.manage_accounts_outlined,
        t('Profilni tahrirlash', 'Edit profile', 'Редактировать профиль'),
      ),
      (
        Icons.event_available_outlined,
        t('Ish jadvali', 'Availability', 'График работы'),
      ),
      (
        Icons.star_outline_rounded,
        t('Mijozlar fikrlari', 'Client reviews', 'Отзывы клиентов'),
      ),
      (
        Icons.notifications_none_rounded,
        t('Bildirishnomalar', 'Notifications', 'Уведомления'),
      ),
      (Icons.help_outline_rounded, t('Yordam', 'Help', 'Помощь')),
      (Icons.language_rounded, t('Til', 'Language', 'Язык')),
    ].indexed)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: formSurface,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: ValueKey('profileSection-${entry.$1}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Icon(entry.$2.$1, color: AppColors.brown),
            title: text(entry.$2.$2),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.brown,
            ),
            onTap: () => _openProfileSection(entry.$1),
          ),
        ),
      ),
  ];
  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppLanguage>();
    final labels = [
      t('Bosh sahifa', 'Home', 'Главная'),
      t('Buyurtmalar', 'Bookings', 'Заказы'),
      t('E’lon berish', 'Post a service', 'Объявление'),
      t('Chatlar', 'Chats', 'Чаты'),
      t('Profil', 'Profile', 'Профиль'),
    ];
    const icons = ['home', 'orders', 'listings', 'chat', 'profile'];
    return MomiqScaffold(
      showPetVisitors: true,
      extendBody: true,
      backgroundColor: _tab == 2 ? listingBackground : AppColors.cream,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (_tab == 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Momiq', style: momiqWordmark(35)),
                              const SizedBox(width: 7),
                              const MomiqLogo(size: 26),
                            ],
                          ),
                          Text(
                            t(
                              'Mehrli parvarish, baxtli hayvonlar',
                              'Loving care, happy pets',
                              'Забота с любовью, счастливые питомцы',
                            ),
                            style: profileText(10),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      children: [
                        avatar(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              text(
                                _tab == 0
                                    ? t(
                                        'Salom, $_firstName!',
                                        'Hello, $_firstName!',
                                        'Здравствуйте, $_firstName!',
                                      )
                                    : labels[_tab],
                                size: 23,
                                bold: true,
                              ),
                              const SizedBox(height: 3),
                              text(fullName, size: 13, color: AppColors.brown),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.notifications_none_rounded,
                          color: AppColors.brown,
                          size: 27,
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: roundedViewport(
                    SingleChildScrollView(
                      key: ValueKey('homeTab-$_tab'),
                      padding: EdgeInsets.fromLTRB(
                        8,
                        8,
                        8,
                        112 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: switch (_tab) {
                              0 => overview(),
                              1 => orders(),
                              2 => [const ListingsPanel()],
                              3 => chats(),
                              _ => profile(),
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: roundedNavigation(
        NavigationBar(
          elevation: 0,
          backgroundColor: formSurface,
          indicatorColor: AppColors.yellow,
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() {
            _tab = value;
            if (value == 1) _orderTab = 0;
          }),
          labelTextStyle: WidgetStatePropertyAll(profileText(10, bold: true)),
          destinations: List.generate(
            5,
            (index) => NavigationDestination(
              key: ValueKey('homeNav-$index'),
              icon: SvgPicture.asset(
                'assets/svg/nav_${icons[index]}.svg',
                width: 27,
                height: 27,
                excludeFromSemantics: true,
              ),
              selectedIcon: SvgPicture.asset(
                'assets/svg/nav_${icons[index]}.svg',
                width: 29,
                height: 29,
                colorFilter: const ColorFilter.mode(
                  AppColors.chocolate,
                  BlendMode.srcIn,
                ),
                excludeFromSemantics: true,
              ),
              label: labels[index],
            ),
          ),
        ),
      ),
    );
  }
}
