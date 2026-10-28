import '../../chat/presentation/conversation_page.dart';
import '../../auth/presentation/role_switch_tile.dart';
import '../data/customer_api.dart';
import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'customer_home_design.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/widgets/momiq_shimmer.dart';
import '../data/customer_feed_repository.dart';
import '../data/customer_location_service.dart';
import '../../listings/data/current_position.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/momiq_logo.dart';
import '../../role_selection/presentation/pages/role_selection_page.dart';
import 'customer_widgets.dart';
import 'customer_discovery.dart';
import 'customer_bookings.dart';
import 'customer_account.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../../bookings/presentation/bookings_page.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key, this.store, this.locationService});
  final CustomerLocationService? locationService;
  final CustomerStore? store;
  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage>
    with WidgetsBindingObserver {
  late final CustomerStore _store = widget.store ?? CustomerStore();
  late final CustomerLocationService _locationService =
      widget.locationService ?? CustomerLocationService();
  CustomerCoordinates? _coordinates;
  int _tab = 0;
  String? _error;
  bool _loading = true,
      _refreshing = false,
      _locating = false,
      _waitingSettings = false;
  bool _resumePending = false;
  bool _locationOfferOpen = false;
  Future<void>? _refreshRequest;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    await _load();
    if (!mounted || _error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _offerLocation(automatic: true);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _store.load();
      await _store.refreshSitters(location: _coordinates);
    } catch (_) {
      if (mounted) {
        _error = lt(
          'Ma’lumotlar yuklanmadi. Qayta urinib ko‘ring.',
          'Could not load. Please retry.',
          'Не удалось загрузить. Повторите.',
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshFeed({bool showShimmer = true}) =>
      _refreshRequest ??= _fetchFeed(
        showShimmer: showShimmer,
      ).whenComplete(() => _refreshRequest = null);
  Future<void> _fetchFeed({required bool showShimmer}) async {
    if (!mounted) return;
    if (showShimmer) setState(() => _refreshing = true);
    try {
      await _store.refreshSitters(location: _coordinates);
    } catch (_) {
      if (mounted) {
        cNotice(
          context,
          lt(
            'Yangilanmadi. Qayta tortib urining.',
            'Refresh failed. Pull to retry.',
            'Не удалось обновить. Потяните снова.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _offerLocation({bool automatic = false}) async {
    if (_locationOfferOpen) return;
    _locationOfferOpen = true;
    try {
      final status = await _locationService.status();
      if (!mounted || status == CustomerLocationStatus.unsupported) return;
      if (status == CustomerLocationStatus.ready) {
        await _requestLocation();
        return;
      }
      final preferences = await SharedPreferences.getInstance();
      const offerKey = 'momiq.locationOfferSeen.v1';
      if (automatic && preferences.getBool(offerKey) == true) return;
      // This is only prompt history, never a substitute for OS permission.
      await preferences.setBool(offerKey, true);
      if (!mounted) return;
      final enable = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: listingSurface,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.near_me_outlined,
                    color: listingGold,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  cText(
                    lt(
                      'Yaqiningizdagi enagalarni toping',
                      'Find sitters near you',
                      'Найдите няню рядом',
                    ),
                    size: 23,
                    bold: true,
                  ),
                  const SizedBox(height: 12),
                  cText(
                    lt(
                      'Joylashuvni yoqsangiz, sizga yaqin enagalar birinchi ko‘rinadi. Masofani hisoblash uchun joriy joylashuvingizdan foydalanamiz.',
                      'Enable location to see nearby sitters first. We use your current location to calculate distance.',
                      'Включите геолокацию, чтобы сначала видеть нянь поблизости. Местоположение нужно для расчёта расстояния.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  cButton(
                    lt(
                      'Joylashuvni yoqish',
                      'Enable location',
                      'Включить геолокацию',
                    ),
                    () => Navigator.pop(context, true),
                    id: 'enableCustomerLocation',
                  ),
                  TextButton(
                    key: const ValueKey('skipCustomerLocation'),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(lt('Hozir emas', 'Not now', 'Не сейчас')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (enable == true && mounted) await _requestLocation();
    } catch (_) {
      if (mounted) {
        cNotice(
          context,
          lt(
            'Joylashuv tekshirilmadi. Qayta urinib ko‘ring.',
            'Could not check location. Retry.',
            'Не удалось проверить геолокацию. Повторите.',
          ),
        );
      }
    } finally {
      _locationOfferOpen = false;
    }
  }

  Future<void> _requestLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var status = await _locationService.status();
      if (!mounted) return;
      if (status == CustomerLocationStatus.unsupported) {
        cNotice(
          context,
          lt(
            'Joylashuvni Android yoki iOS qurilmada yoqishingiz mumkin.',
            'Location is available on Android or iOS.',
            'Геолокация доступна на Android или iOS.',
          ),
        );
        return;
      }
      if (status == CustomerLocationStatus.disabled) {
        _waitingSettings = true;
        await _locationService.openLocationSettings();
        return;
      }
      if (status == CustomerLocationStatus.deniedForever) {
        _waitingSettings = true;
        await _locationService.openAppSettings();
        return;
      }
      if (status == CustomerLocationStatus.denied) {
        await _locationService.requestPermission();
        status = await _locationService.status();
      }
      if (!mounted) return;
      if (status != CustomerLocationStatus.ready) {
        cNotice(
          context,
          lt(
            'Joylashuv ruxsatisiz ham enagalarni ko‘rishingiz mumkin. Ruxsatni keyinroq yoqing.',
            'You can still browse sitters. Enable location later.',
            'Можно просматривать нянь без геолокации. Разрешите доступ позже.',
          ),
        );
        return;
      }
      final point = await _locationService.locate();
      if (!mounted) return;
      setState(() => _coordinates = point);
      if (_refreshRequest != null) await _refreshRequest;
      if (mounted) await _refreshFeed(showShimmer: false);
    } on PositionQualityException {
      if (mounted) {
        cNotice(
          context,
          lt(
            'Joylashuv yetarlicha aniq emas. Toshkent bo‘yicha qidirishda davom eting yoki qayta urining.',
            'Location is not precise enough. Keep browsing Toshkent or retry.',
            'Местоположение недостаточно точное. Продолжайте поиск по Ташкенту или повторите.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        cNotice(
          context,
          lt(
            'Joylashuv aniqlanmadi. Qayta urinib ko‘ring.',
            'Could not find your location. Retry.',
            'Не удалось определить местоположение. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
        if (_resumePending) {
          _resumePending = false;
          _resumeLocation();
        }
      }
    }
  }

  Future<void> _resumeLocation() async {
    try {
      final status = await _locationService.status();
      if (!mounted) return;
      if (status == CustomerLocationStatus.ready ||
          status == CustomerLocationStatus.denied) {
        await _requestLocation();
      }
    } catch (_) {
      // Leave browsing available; the location button lets the user retry.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingSettings) {
      _waitingSettings = false;
      if (_locating) {
        _resumePending = true;
      } else {
        _resumeLocation();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  void _search({int? service}) =>
      cPush(context, CustomerSearchPage(store: _store, service: service));
  bool _loggingOut = false;
  Future<void> _logout({bool allDevices = false}) async {
    if (_loggingOut) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: cText('Chiqish'),
        content: cText(
          lt(
            allDevices
                ? 'Barcha qurilmalardan chiqasizmi?'
                : 'Hisobdan chiqasizmi?',
            allDevices ? 'Log out on all devices?' : 'Log out of your account?',
            allDevices ? 'Выйти на всех устройствах?' : 'Выйти из аккаунта?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ct('Ortga')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ct('Chiqish')),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      setState(() => _loggingOut = true);
      try {
        await CustomerApi.logout(allDevices: allDevices);
      } catch (e) {
        if (mounted) {
          cNotice(
            context,
            e is CustomerApiException
                ? e.message
                : 'Ma’lumotlarni tozalab bo‘lmadi. Qayta urinib ko‘ring.',
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _loggingOut = false);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
        (_) => false,
      );
    }
  }

  List<Widget> _home() => [
    Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cText(
                lt(
                  'Salom, ${_store.profile['first']}!',
                  'Hello, ${_store.profile['first']}!',
                  'Здравствуйте, ${_store.profile['first']}!',
                ),
                size: 26,
                bold: true,
              ),
              TextButton.icon(
                key: const ValueKey('customerLocation'),
                onPressed: _locating ? null : _offerLocation,
                icon: const Icon(Icons.my_location_outlined, size: 16),
                label: Text(
                  _coordinates == null
                      ? lt(
                          'Joylashuvni yoqish',
                          'Enable location',
                          'Включить геолокацию',
                        )
                      : lt(
                          'Yaqin enagalar',
                          'Nearby sitters',
                          'Няни поблизости',
                        ),
                ),
              ),
              if (_locating)
                const SizedBox(
                  width: 140,
                  height: 8,
                  child: MomiqShimmer(
                    child: ColoredBox(color: Color(0xFFE3D7C7)),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => cPush(context, const NotificationsPage()),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    ),
    cCard(
      Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.brown),
          const SizedBox(width: 12),
          cText('Enaga qidirish', color: AppColors.brown),
        ],
      ),
      onTap: () => _search(),
    ),
    const CustomerBannerCarousel(),
    cText(
      lt('Xizmat turini tanlang', 'Choose a service', 'Выберите услугу'),
      size: 20,
      bold: true,
    ),
    const SizedBox(height: 12),
    CustomerServiceTiles(onSelected: (i) => _search(service: i)),
    const SizedBox(height: 24),
    Row(
      children: [
        Expanded(
          child: cText(
            lt(
              'Tavsiya etilgan enagalar',
              'Recommended sitters',
              'Рекомендуемые няни',
            ),
            size: 18,
            bold: true,
          ),
        ),
        IconButton(
          onPressed: () => _search(),
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    ),
    for (final sitter in _store.sitters)
      SitterCard(store: _store, sitter: sitter),
    CatalogMoreButton(store: _store),
  ];
  List<Widget> _profile() {
    final p = _store.profile;
    return [
      Container(
        padding: const EdgeInsets.all(22),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF5DFAB), Color(0xFFF8EFE0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: listingSurface,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: listingBackground,
                    backgroundImage: p['photo'] == null
                        ? null
                        : MemoryImage(base64Decode(p['photo'])),
                    child: p['photo'] == null
                        ? const Icon(
                            Icons.person_outline_rounded,
                            size: 36,
                            color: AppColors.brown,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cText('${p['first']} ${p['last']}', size: 22, bold: true),
                      const SizedBox(height: 6),
                      cText('Mening profilim', size: 13),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            cButton(
              'Profilni tahrirlash',
              () => cPush(context, CustomerProfileForm(store: _store)),
              secondary: true,
              icon: Icons.edit_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final stat in [
                  ('${_store.list('pets').length}', 'Hayvonlar'),
                  (
                    _store.remote ? '—' : '${_store.list('bookings').length}',
                    'Buyurtmalar',
                  ),
                  ('${_store.favorites.length}', 'Saqlangan'),
                ])
                  Expanded(
                    child: Column(
                      children: [
                        cText(stat.$1, size: 23, bold: true),
                        const SizedBox(height: 3),
                        cText(stat.$2, size: 11),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: cText('Shaxsiy ma’lumotlar va sozlamalar', size: 16, bold: true),
      ),
      for (final item in <(IconData, String, Widget)>[
        (
          Icons.pets_outlined,
          'Mening hayvonlarim',
          CustomerPetsPage(store: _store),
        ),
        (
          Icons.favorite_border,
          'Saqlangan enagalar',
          CustomerSearchPage(store: _store, favoritesOnly: true),
        ),
        (
          Icons.location_on_outlined,
          'Manzillarim',
          CustomerAddressesPage(store: _store),
        ),
        (
          Icons.notifications_none_rounded,
          'Bildirishnomalar',
          CustomerSettingsPage(store: _store),
        ),
        (Icons.language, 'Til', CustomerSettingsPage(store: _store)),
        (Icons.help_outline_rounded, 'Yordam', CustomerHelpPage(store: _store)),
      ])
        cCard(
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5E6C7),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(item.$1, color: AppColors.brown, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: cText(item.$2)),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          onTap: () => cPush(context, item.$3),
        ),
      const RoleSwitchTile(customer: false),
      cButton(
        lt(
          'Barcha qurilmalardan chiqish',
          'Log out on all devices',
          'Выйти на всех устройствах',
        ),
        () => _logout(allDevices: true),
        loading: _loggingOut,
        secondary: true,
        icon: Icons.devices,
      ),
      cButton(
        'Chiqish',
        _logout,
        loading: _loggingOut,
        secondary: true,
        icon: Icons.logout_rounded,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_store, AppLanguage.current]),
    builder: (context, _) => MomiqScaffold(
      showPetVisitors: true,
      extendBody: true,
      backgroundColor: listingBackground,
      appBar: _tab == 0
          ? null
          : AppBar(
              backgroundColor: listingBackground,
              automaticallyImplyLeading: false,
              title: cText(
                ['Bosh sahifa', 'Buyurtmalar', 'Chatlar', 'Profil'][_tab],
                size: 24,
                bold: true,
              ),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 18),
                  child: MomiqLogo(size: 28),
                ),
              ],
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _loading
              ? const SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(18),
                    child: CustomerHomeSkeleton(
                      key: ValueKey('customerInitialShimmer'),
                    ),
                  ),
                )
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        cText(_error!),
                        cButton('Qayta urinish', _start),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  bottom: false,
                  child: RefreshIndicator.noSpinner(
                    key: const ValueKey('customerRefresh'),
                    notificationPredicate: (notification) =>
                        _tab == 0 && notification.depth == 0,
                    onRefresh: _refreshFeed,
                    child: ListView(
                      key: ValueKey('customerTab-$_tab'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        18,
                        14,
                        18,
                        112 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      children: switch (_tab) {
                        0 =>
                          _refreshing
                              ? [
                                  const CustomerHomeSkeleton(
                                    key: ValueKey('customerRefreshShimmer'),
                                  ),
                                ]
                              : _home(),
                        1 => [
                          _store.api == null
                              ? CustomerOrders(store: _store)
                              : BookingInbox(api: _store.api),
                        ],
                        2 => [
                          ConversationInbox(api: _store.api),
                          if (_store.list('messages').isNotEmpty)
                            ExpansionTile(
                              title: Text(
                                lt(
                                  'Oldingi yordam yozishmalari',
                                  'Earlier support conversations',
                                  'Предыдущие обращения',
                                ),
                              ),
                              children: [CustomerChatList(store: _store)],
                            ),
                        ],
                        _ => _profile(),
                      },
                    ),
                  ),
                ),
        ],
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: NavigationBar(
          backgroundColor: listingSurface,
          indicatorColor: const Color(0xFFF1D68E),
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: [
            for (var i = 0; i < 4; i++)
              NavigationDestination(
                key: ValueKey('customerNav-$i'),
                icon: SvgPicture.asset(
                  'assets/svg/nav_${['home', 'orders', 'chat', 'profile'][i]}.svg',
                  width: 27,
                  height: 27,
                  excludeFromSemantics: true,
                ),
                selectedIcon: SvgPicture.asset(
                  'assets/svg/nav_${['home', 'orders', 'chat', 'profile'][i]}.svg',
                  width: 29,
                  height: 29,
                  excludeFromSemantics: true,
                  colorFilter: const ColorFilter.mode(
                    AppColors.chocolate,
                    BlendMode.srcIn,
                  ),
                ),
                label: ct(
                  ['Bosh sahifa', 'Buyurtmalar', 'Chatlar', 'Profil'][i],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
