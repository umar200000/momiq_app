import 'package:momiq_app/core/widgets/button_progress.dart';
import '../../../customer/data/customer_api.dart';
import '../../../wallet/presentation/wallet_page.dart';
import '../../../role_selection/presentation/pages/role_selection_page.dart';
import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../profile/presentation/sitter_profile_page.dart';
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
    this.firstName = '',
    this.lastName = '',
    this.careAnimalCount = 0,
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
    final api = await CustomerApi.restore();
    if (api != null) {
      try {
        final response = await api.request('GET', '/me');
        final account = Map<String, dynamic>.from(response['account']);
        await CustomerApi.rememberAccount(account);
        await AppLanguage.select(account['language'] ?? 'uz');
        if (!mounted) return;
        final profile = account['profile'];
        setState(() {
          _firstName = profile['first'] ?? '';
          _lastName = profile['last'] ?? '';
          _profileAvatar = profile['photo'] == null
              ? null
              : base64Decode(profile['photo']);
        });
      } catch (_) {
        // Keep the last server-backed view; local mock values cannot replace it.
      }
      return;
    }
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
        builder: (_) => SitterProfilePage(
          section: section,
          firstName: _firstName,
          lastName: _lastName,
          avatar: _profileAvatar,
        ),
      ),
    );
    if (mounted) await _loadProfile();
  }

  bool _loggingOut = false;
  Future<void> _logout({bool allDevices = false}) async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await CustomerApi.logout(allDevices: allDevices);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is CustomerApiException
                  ? e.message
                  : 'Ma’lumotlarni tozalab bo‘lmadi. Qayta urinib ko‘ring.',
            ),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const RoleSelectionPage()),
      (_) => false,
    );
  }

  int _tab = 0;
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
      t('Xush kelibsiz', 'Welcome', 'Добро пожаловать'),
      t('Hozircha buyurtmalar yo‘q', 'No bookings yet', 'Заказов пока нет'),
    ),
    card(
      text(
        t(
          'Haqiqiy buyurtmalar paydo bo‘lganda shu yerda ko‘rinadi.',
          'Your bookings will appear here.',
          'Здесь появятся ваши заказы.',
        ),
      ),
    ),
  ];
  List<Widget> orders() => [
    card(
      text(
        t('Hozircha buyurtmalar yo‘q', 'No bookings yet', 'Заказов пока нет'),
      ),
    ),
  ];
  List<Widget> chats() => [
    card(
      text(
        t(
          'Hozircha suhbatlar yo‘q',
          'No conversations yet',
          'Переписок пока нет',
        ),
      ),
    ),
  ];
  List<Widget> profile() => [
    ListTile(
      key: const ValueKey('sitterWallet'),
      leading: const Icon(Icons.account_balance_wallet_outlined),
      title: Text(t('Momiq balansi', 'Momiq balance', 'Баланс Momiq')),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const WalletPage())),
    ),
    ListTile(
      key: const ValueKey('sitterLogoutAll'),
      leading: const Icon(Icons.devices),
      title: Text(
        t(
          'Barcha qurilmalardan chiqish',
          'Log out on all devices',
          'Выйти на всех устройствах',
        ),
      ),
      onTap: _loggingOut ? null : () => _logout(allDevices: true),
    ),
    ListTile(
      key: const ValueKey('sitterLogout'),
      leading: ButtonProgress(
        loading: _loggingOut,
        child: const Icon(Icons.logout),
      ),
      title: Text(t('Chiqish', 'Log out', 'Выйти')),
      onTap: _loggingOut ? null : _logout,
    ),
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
