import '../../support/support_page.dart';
import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../listings/presentation/listings_panel.dart';
import '../../wallet/presentation/topup_history_page.dart';
import '../../bookings/presentation/bookings_page.dart';
import '../../chat/presentation/conversation_page.dart';
import '../../care/presentation/booking_care_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    this.api,
    this.bookingBuilder,
    this.careBuilder,
    this.supportBuilder,
    this.conversationBuilder,
  });
  final CustomerApi? api;
  final Widget Function(CustomerApi api, String id)? bookingBuilder;
  final Widget Function(CustomerApi api, String id)? careBuilder,
      conversationBuilder,
      supportBuilder;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  CustomerApi? _api;
  final List<Map<String, dynamic>> _items = [];
  bool _busy = false;
  String? _error, _cursor;
  int _unread = 0;
  final Set<String> _reading = {};
  final int _session = CustomerApi.sessionVersion;
  bool get _live => mounted && _session == CustomerApi.sessionVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!_live || _busy || _reading.isNotEmpty || (more && _cursor == null)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _api ??= widget.api ?? await CustomerApi.restore();
      if (!mounted || !_live) return;
      if (_api == null) {
        throw CustomerApiException(
          lt(
            'Hisobingizga kiring.',
            'Sign in to continue.',
            'Войдите в аккаунт.',
          ),
        );
      }
      final data = await _api!.request(
        'GET',
        '/notifications${more ? '?before=${Uri.encodeQueryComponent(_cursor!)}' : ''}',
      );
      if (!mounted || !_live) return;
      setState(() {
        if (!more) _items.clear();
        final ids = _items.map((e) => e['id']).toSet();
        _items.addAll(
          (data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => ids.add(e['id'])),
        );
        _cursor = data['nextCursor'] as String?;
        _unread = data['unreadCount'] as int;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = lt(
            'Bildirishnomalar yuklanmadi. Qayta urinib ko‘ring.',
            'Could not load notifications. Please retry.',
            'Не удалось загрузить уведомления. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _title(Map<String, dynamic> item) {
    if (item['kind'] == 'support') {
      return lt('Yordam xizmatidan javob', 'Support reply', 'Ответ поддержки');
    }
    if (item['kind'] == 'conversation') {
      return lt('Yangi chat xabari', 'New chat message', 'Новое сообщение');
    }
    if (item['kind'] == 'care') {
      return item['status'] == 'instructions'
          ? lt(
              'Parvarish ko‘rsatmasi yangilandi',
              'Care instructions updated',
              'Инструкции по уходу обновлены',
            )
          : lt(
              'Parvarish hisoboti yangilandi',
              'Care report updated',
              'Отчёт по уходу обновлён',
            );
    }
    if (item['kind'] == 'booking') {
      if (item['status'] == 'contact_reminder') {
        return lt(
          'Boshlanishni tekshiring',
          'Check the service start',
          'Проверьте начало ухода',
        );
      }
      if (item['status'] == 'complaint_available') {
        return lt(
          'Kelmaslik bo‘yicha murojaat qilish mumkin',
          'No-show report available',
          'Можно сообщить о неявке',
        );
      }
      return '${lt('Buyurtma', 'Booking', 'Заказ')} · ${bookingStateLabel(item['status'])}';
    }
    final topic = item['kind'] == 'wallet_topup'
        ? lt('Balans to‘ldirish', 'Balance top-up', 'Пополнение баланса')
        : lt('E’lon moderatsiyasi', 'Listing review', 'Проверка объявления');
    final status = switch (item['status']) {
      'approved' => lt('Tasdiqlangan', 'Approved', 'Одобрено'),
      'rejected' => lt('Rad etilgan', 'Rejected', 'Отклонено'),
      'suspended' => lt('To‘xtatilgan', 'Suspended', 'Приостановлено'),
      'needs_info' => lt(
        'Aniqlashtirish kerak',
        'More information needed',
        'Нужно уточнение',
      ),
      _ => lt('Yangilangan', 'Updated', 'Обновлено'),
    };
    return '$topic · $status';
  }

  String _date(String value) {
    final date = DateTime.parse(value).toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(date)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  bool _hasDestination(Map<String, dynamic> item) {
    final target = item['targetId'];
    if (target is! String) return false;
    return switch (item['kind']) {
      'wallet_topup' ||
      'booking' ||
      'conversation' ||
      'support' ||
      'care' => RegExp(r'^[a-f0-9]{32}$').hasMatch(target),
      'listing' => const {'boarding', 'homeVisit', 'personal'}.contains(target),
      _ => false,
    };
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    if (!_live || _busy || !_reading.add(id)) return;
    setState(() {});
    try {
      if (item['readAt'] == null) {
        await _api!.request(
          'POST',
          '/notifications/${Uri.encodeComponent(id)}/read',
          {},
        );
        if (!mounted || !_live) return;
        setState(() {
          item['readAt'] = DateTime.now().toUtc().toIso8601String();
          if (_unread > 0) _unread--;
        });
      }
      if (!mounted || !_live) return;
      final target = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_title(item)),
          content: SingleChildScrollView(
            child: Text(item['reason'] as String? ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(lt('Yopish', 'Close', 'Закрыть')),
            ),
            if (_hasDestination(item))
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  lt('Sahifani ochish', 'Open page', 'Открыть страницу'),
                ),
              ),
          ],
        ),
      );
      if (target != true || !mounted || !_live || !_hasDestination(item)) {
        return;
      }
      // Only local, known destinations are accepted; no server-provided URLs.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => item['kind'] == 'support'
              ? (widget.supportBuilder?.call(
                      _api!,
                      item['targetId'] as String,
                    ) ??
                    SupportThreadPage(
                      api: _api!,
                      id: item['targetId'] as String,
                    ))
              : item['kind'] == 'conversation'
              ? (widget.conversationBuilder?.call(
                      _api!,
                      item['targetId'] as String,
                    ) ??
                    ConversationPage(
                      api: _api!,
                      conversationId: item['targetId'] as String,
                    ))
              : item['kind'] == 'care'
              ? (widget.careBuilder?.call(_api!, item['targetId'] as String) ??
                    BookingCarePage(
                      api: _api!,
                      bookingId: item['targetId'] as String,
                    ))
              : item['kind'] == 'booking'
              ? (widget.bookingBuilder?.call(
                      _api!,
                      item['targetId'] as String,
                    ) ??
                    BookingDetailPage(
                      api: _api!,
                      id: item['targetId'] as String,
                    ))
              : item['kind'] == 'wallet_topup'
              ? TopupHistoryPage(
                  api: _api!,
                  topupId: item['targetId'] as String,
                )
              : Scaffold(
                  appBar: AppBar(
                    title: Text(lt('E’lonlar', 'Listings', 'Объявления')),
                  ),
                  body: const ListingsPanel(),
                ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lt(
                'Xabar ochilmadi. Qayta urinib ko‘ring.',
                'Could not open the notice. Please retry.',
                'Не удалось открыть уведомление. Повторите.',
              ),
            ),
          ),
        );
      }
    } finally {
      _reading.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Bildirishnomalar', 'Notifications', 'Уведомления')),
      actions: [
        IconButton(
          tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            lt(
              'O‘qilmagan: $_unread',
              'Unread: $_unread',
              'Непрочитанных: $_unread',
            ),
            key: const ValueKey('noticeUnreadCount'),
          ),
          Text(
            lt(
              'Qarorlar tarixi shu yerda saqlanadi. Push xabarlar hali ulanmagan.',
              'Decision history is kept here. Push notifications are not connected yet.',
              'История решений хранится здесь. Push-уведомления пока не подключены.',
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
            ),
          ],
          if (!_busy && _error == null && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                lt(
                  'Hozircha bildirishnoma yo‘q.',
                  'No notifications yet.',
                  'Уведомлений пока нет.',
                ),
              ),
            ),
          for (final item in _items)
            Card(
              child: ListTile(
                key: ValueKey('notice-${item['id']}'),
                onTap: _reading.contains(item['id']) ? null : () => _open(item),
                leading: Icon(
                  item['readAt'] == null
                      ? Icons.mark_email_unread_outlined
                      : Icons.drafts_outlined,
                ),
                title: Text(_title(item)),
                subtitle: Text(
                  '${item['reason']}\n${_date(item['created'] as String)}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          if (_cursor != null)
            TextButton(
              key: const ValueKey('moreNotices'),
              onPressed: _busy ? null : () => _load(more: true),
              child: Text(lt('Yana yuklash', 'Load more', 'Загрузить ещё')),
            ),
        ],
      ),
    ),
  );
}
