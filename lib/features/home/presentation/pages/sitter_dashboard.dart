import 'package:flutter/material.dart';
import '../../../customer/data/customer_api.dart';
import '../../../bookings/presentation/bookings_page.dart';
import '../../../listings/presentation/listing_style.dart' show lt;
import '../../../../core/localization/app_language.dart';

class SitterDashboard extends StatefulWidget {
  const SitterDashboard({
    super.key,
    this.api,
    required this.onOrders,
    required this.onListings,
    required this.onWallet,
    required this.onProfile,
  });
  final CustomerApi? api;
  final VoidCallback onOrders, onListings;
  final Future<void> Function() onWallet, onProfile;
  @override
  State<SitterDashboard> createState() => _SitterDashboardState();
}

class _SitterDashboardState extends State<SitterDashboard>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SitterDashboard old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api) {
      _data = null;
      _reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation, session = CustomerApi.sessionVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = widget.api;
      if (api == null) throw StateError('No session');
      final result = await api.request('GET', '/me/dashboard');
      if (mounted &&
          generation == _generation &&
          session == CustomerApi.sessionVersion) {
        setState(() => _data = result);
      }
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          session == CustomerApi.sessionVersion) {
        setState(
          () => _error = lt(
            'Ma’lumot yangilanmadi. Qayta urinib ko‘ring.',
            'Could not refresh. Please retry.',
            'Не удалось обновить. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted &&
          generation == _generation &&
          session == CustomerApi.sessionVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _card(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
  String _state(String value) => switch (value) {
    'draft' => lt('Qoralama', 'Draft', 'Черновик'),
    'pending' => lt('Ko‘rib chiqilmoqda', 'Under review', 'На проверке'),
    'approved' => lt('Tasdiqlangan', 'Approved', 'Одобрено'),
    'rejected' => lt('Rad etilgan', 'Rejected', 'Отклонено'),
    'suspended' => lt('To‘xtatilgan', 'Paused', 'Приостановлено'),
    'archived' => lt('Arxivlangan', 'Archived', 'В архиве'),
    _ => value,
  };
  Future<void> _open(Map<String, dynamic> booking) async {
    final api = widget.api;
    if (api == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingDetailPage(api: api, id: booking['id']),
      ),
    );
    if (mounted) await _reload();
  }

  Widget _bookings(String title, Map<String, dynamic> section) => _card([
    Text(title, style: Theme.of(context).textTheme.titleMedium),
    if ((section['items'] as List).isEmpty)
      Text(
        lt(
          'Bu ro‘yxatda buyurtma yo‘q.',
          'No bookings in this list.',
          'В этом списке нет заказов.',
        ),
      ),
    for (final raw in section['items'] as List)
      Builder(
        builder: (context) {
          final b = Map<String, dynamic>.from(raw);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            key: ValueKey('dashboardBooking-${b['id']}'),
            title: Text(
              '${b['peerName']} · ${bookingServiceLabel(b['service'])}',
            ),
            subtitle: Text(
              '${bookingTime(b['startsAt'])} — ${bookingStateLabel(b['status'])}\n${(b['petNames'] as List).join(', ')}${b['overdue'] == true ? '\n${lt('Kelishilgan muddat o‘tgan. Yakun yoki yordam kerak.', 'Agreed end passed. Complete or contact support.', 'Согласованный срок истёк. Завершите или обратитесь за помощью.')}' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(b),
          );
        },
      ),
    if (section['hasMore'] == true)
      TextButton(
        onPressed: widget.onOrders,
        child: Text(lt('Barcha buyurtmalar', 'All bookings', 'Все заказы')),
      ),
  ]);
  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppLanguage>();
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                lt('Ish holati', 'Work overview', 'Обзор работы'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              key: const ValueKey('refreshDashboard'),
              tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          _card([
            Text(_error!, key: const ValueKey('dashboardError')),
            if (data != null)
              Text(
                lt(
                  'Quyida oxirgi olingan ma’lumot ko‘rsatilgan.',
                  'The last loaded data is shown below.',
                  'Ниже показаны последние загруженные данные.',
                ),
              ),
          ]),
        if (data != null) ...[
          Text(
            '${lt('Yangilangan', 'Updated', 'Обновлено')}: ${bookingTime(data['asOf'])}',
          ),
          const SizedBox(height: 12),
          _card([
            Text(
              '${lt('Yangi so‘rovlar', 'New requests', 'Новые запросы')}: ${data['pendingCount']}',
              key: const ValueKey('dashboardPending'),
            ),
            Text(
              '${lt('Faol parvarishdagi hayvonlar', 'Pets in active care', 'Питомцы на передержке')}: ${data['activePetCount']}',
            ),
            Text(
              '${lt('Nizo ko‘rilmoqda', 'Under review', 'Спор рассматривается')}: ${data['disputedCount']}',
            ),
            TextButton(
              onPressed: widget.onOrders,
              child: Text(
                lt('Buyurtmalarni ochish', 'Open bookings', 'Открыть заказы'),
              ),
            ),
          ]),
          _card([
            Text(
              '${lt('Momiq balansi', 'Momiq balance', 'Баланс Momiq')}: ${bookingMoney(data['balanceMinor'])}',
            ),
            if (data['balanceEligible'] != true)
              Text(
                lt(
                  'Balans 15 000 so‘mdan kam. Yangi mijozlar olish uchun to‘ldiring; mavjud buyurtmalar davom etadi.',
                  'Balance is below 15,000 UZS. Top up to receive new clients; existing bookings continue.',
                  'Баланс ниже 15 000 сум. Пополните для новых клиентов; текущие заказы продолжаются.',
                ),
              ),
            TextButton(
              onPressed: () async {
                await widget.onWallet();
                if (mounted) await _reload();
              },
              child: Text(
                lt('Balansni ochish', 'Open balance', 'Открыть баланс'),
              ),
            ),
          ]),
          _card([
            Text(
              lt(
                'Profil va e’lonlar',
                'Profile and services',
                'Профиль и объявления',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (data['profilePresent'] != true)
              Text(
                lt(
                  'Enaga profilini to‘ldiring.',
                  'Complete your sitter profile.',
                  'Заполните профиль няни.',
                ),
              ),
            if ((data['listings'] as List).isEmpty)
              Text(
                lt(
                  'Hali xizmat e’loni yo‘q.',
                  'No service posted yet.',
                  'Объявлений пока нет.',
                ),
              ),
            for (final item in data['listings'] as List) ...[
              const SizedBox(height: 8),
              Text(
                '${bookingServiceLabel(item['service'])}: ${_state(item['status'])}${item['testOnly'] == true ? ' · TEST' : ''}',
              ),
              if ((item['reason'] as String).isNotEmpty) Text(item['reason']),
              if ((item['missing'] as List).isNotEmpty)
                Text(
                  '${lt('Profilning to‘ldirilmagan maydonlari', 'Incomplete profile fields', 'Незаполненные поля профиля')}: ${(item['missing'] as List).length}',
                ),
            ],
            Text(
              lt(
                'MyID tekshiruvi hali ulanmagan. TEST tasdiq shaxs tekshiruvi emas.',
                'MyID is not connected yet. TEST approval is not identity verification.',
                'MyID пока не подключён. Одобрение TEST не является проверкой личности.',
              ),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: () async {
                    await widget.onProfile();
                    if (mounted) await _reload();
                  },
                  child: Text(
                    lt(
                      'Profilni to‘ldirish',
                      'Complete profile',
                      'Заполнить профиль',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onListings,
                  child: Text(
                    lt(
                      'E’lonlarni ochish',
                      'Open services',
                      'Открыть объявления',
                    ),
                  ),
                ),
              ],
            ),
          ]),
          _bookings(
            lt('Bugungi buyurtmalar', 'Today’s bookings', 'Заказы сегодня'),
            Map<String, dynamic>.from(data['today']),
          ),
          _bookings(
            lt('Yaqin buyurtmalar', 'Upcoming bookings', 'Ближайшие заказы'),
            Map<String, dynamic>.from(data['upcoming']),
          ),
        ],
      ],
    );
  }
}
