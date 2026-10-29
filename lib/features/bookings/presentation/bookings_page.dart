import 'booking_source_boundary.dart';
import '../../support/support_page.dart';
import 'booking_dispute_page.dart';
import '../../customer/presentation/pet_safety.dart';
import '../../media/presentation/private_api_image.dart';
import 'package:flutter/material.dart';
import '../../care/presentation/booking_care_page.dart';
import '../../reviews/presentation/booking_review_page.dart';
import '../../../core/localization/app_language.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../customer/data/customer_api.dart';
import '../data/booking_controller.dart';
import '../../chat/presentation/conversation_page.dart';

String bookingStateLabel(String state) => switch (state) {
  'pending' => lt('Javob kutilmoqda', 'Awaiting reply', 'Ожидает ответа'),
  'accepted' => lt('Qabul qilingan', 'Accepted', 'Принят'),
  'rejected' => lt('Rad etilgan', 'Rejected', 'Отклонён'),
  'expired' => lt('Muddati tugagan', 'Expired', 'Истёк срок'),
  'cancelled' => lt('Bekor qilingan', 'Cancelled', 'Отменён'),
  'active' => lt('Parvarishda', 'In progress', 'В процессе'),
  'completed' => lt('Yakunlangan', 'Completed', 'Завершён'),
  'disputed' => lt('Nizo ko‘rilmoqda', 'Under review', 'Рассматривается спор'),
  _ => state,
};
String bookingMoney(int value) =>
    '${value ~/ 100}${value % 100 == 0 ? '' : '.${(value % 100).toString().padLeft(2, '0')}'} UZS';
String bookingServiceLabel(String? service) => switch (service) {
  'boarding' => lt('Uyda qarash', 'Boarding', 'Передержка'),
  'homeVisit' => lt('Uyga borib qarash', 'Home visits', 'Визиты на дом'),
  'personal' => lt('Shaxsiy enaga', 'Personal sitter', 'Личная няня'),
  _ => lt('Xizmat', 'Service', 'Услуга'),
};
String bookingTime(String value) {
  final d = DateTime.parse(value).toUtc().add(const Duration(hours: 5));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(d.day)}.${pad(d.month)}.${d.year} ${pad(d.hour)}:${pad(d.minute)} (UTC+5)';
}

class BookingInbox extends StatelessWidget {
  const BookingInbox({super.key, this.api, this.conversationId});
  final CustomerApi? api;
  final String? conversationId;
  @override
  Widget build(BuildContext context) {
    final source = api ?? CustomerApi.active;
    if (source == null) {
      return Text(
        lt(
          'Buyurtmalar uchun hisobingizga kiring.',
          'Sign in to see bookings.',
          'Войдите для просмотра заказов.',
        ),
      );
    }
    return BookingSourceBoundary(
      api: source,
      valid: true,
      expired: bookingSourceNotice(),
      child: _BookingInbox(
        key: ValueKey((source, conversationId)),
        api: source,
        conversationId: conversationId,
      ),
    );
  }
}

class _BookingInbox extends StatefulWidget {
  const _BookingInbox({super.key, this.api, this.conversationId});
  final CustomerApi? api;
  final String? conversationId;
  @override
  State<_BookingInbox> createState() => _BookingInboxState();
}

class _BookingInboxState extends State<_BookingInbox> {
  BookingInboxController? controller;
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    final api = widget.api ?? CustomerApi.active;
    if (api != null) {
      controller = BookingInboxController(
        api,
        conversationId: widget.conversationId,
      )..load();
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppLanguage>();
    final c = controller;
    if (c == null) {
      return Text(
        lt(
          'Buyurtmalar uchun hisobingizga kiring.',
          'Sign in to see bookings.',
          'Войдите для просмотра заказов.',
        ),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => !c.live
          ? bookingSourceNotice()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('bookingSearch'),
                  controller: _search,
                  maxLength: 80,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) => c.filters(query: value),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: lt(
                      'Ism, hayvon yoki buyurtma raqami',
                      'Name, pet or booking ID',
                      'Имя, питомец или номер заказа',
                    ),
                    suffixIcon: IconButton(
                      tooltip: lt('Qidirish', 'Search', 'Поиск'),
                      onPressed: () => c.filters(query: _search.text),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final bucket in [
                      'all',
                      'pending',
                      'ongoing',
                      'history',
                    ])
                      ChoiceChip(
                        key: ValueKey('bookingBucket-$bucket'),
                        label: Text(switch (bucket) {
                          'pending' => lt(
                            'Kutilayotgan',
                            'Pending',
                            'Ожидающие',
                          ),
                          'ongoing' => lt(
                            'Davom etayotgan',
                            'Ongoing',
                            'Текущие',
                          ),
                          'history' => lt('Tarix', 'History', 'История'),
                          _ => lt('Barchasi', 'All', 'Все'),
                        }),
                        selected: c.bucket == bucket,
                        onSelected: (_) =>
                            c.filters(bucket: bucket, query: _search.text),
                      ),
                    if (c.query.isNotEmpty || c.bucket != 'all')
                      TextButton(
                        onPressed: () {
                          _search.clear();
                          c.filters(bucket: 'all', query: '');
                        },
                        child: Text(lt('Tozalash', 'Clear', 'Сбросить')),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: c.loading ? null : () => c.load(),
                    icon: const Icon(Icons.refresh),
                    label: Text(lt('Yangilash', 'Refresh', 'Обновить')),
                  ),
                ),
                if (c.loading) const LinearProgressIndicator(),
                if (c.error != null)
                  Text(
                    c.error.toString(),
                    key: const ValueKey('bookingInboxError'),
                  ),
                if (!c.loading && c.error == null && c.items.isEmpty)
                  Text(
                    lt(
                      'Hozircha buyurtmalar yo‘q',
                      'No bookings yet',
                      'Заказов пока нет',
                    ),
                  ),
                for (final item in c.items)
                  Card(
                    child: ListTile(
                      key: ValueKey('booking-${item['id']}'),
                      leading: const Icon(Icons.pets),
                      title: Text(bookingStateLabel(item['status'])),
                      subtitle: Text(
                        [
                          '#${(item['id'] as String).substring(0, 8)}',
                          if (item['peerName'] != null)
                            '${item['peerName']} · ${bookingServiceLabel(item['service'])}',
                          if (item['startsAt'] != null)
                            bookingTime(item['startsAt']),
                          if (item['pets'] is List)
                            (item['pets'] as List)
                                .map((p) => p['name'])
                                .where((name) => name != null && name != '')
                                .join(', '),
                          if (item['serviceTotalMinor'] is int)
                            bookingMoney(item['serviceTotalMinor']),
                        ].where((s) => s.isNotEmpty).join('\n'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        if (!mounted || !c.live) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                BookingDetailPage(api: c.api, id: item['id']),
                          ),
                        );
                        if (mounted && c.live) await c.load();
                      },
                    ),
                  ),
                if (c.cursor != null)
                  TextButton(
                    onPressed: c.loading ? null : () => c.load(more: true),
                    child: Text(
                      lt('Yana yuklash', 'Load more', 'Загрузить ещё'),
                    ),
                  ),
              ],
            ),
    );
  }
}

class BookingDetailPage extends StatelessWidget {
  const BookingDetailPage({
    super.key,
    required this.api,
    required this.id,
    this.controller,
  });
  final CustomerApi api;
  final String id;
  final BookingController? controller;
  @override
  Widget build(BuildContext context) => BookingSourceBoundary(
    api: api,
    valid:
        controller == null ||
        (identical(controller!.api, api) &&
            controller!.id == id &&
            controller!.live),
    child: _BookingDetailPage(
      key: ValueKey((api, id, controller)),
      api: api,
      id: id,
      controller: controller,
    ),
  );
}

class _BookingDetailPage extends StatefulWidget {
  const _BookingDetailPage({
    super.key,
    required this.api,
    required this.id,
    this.controller,
  });
  final CustomerApi api;
  final String id;
  final BookingController? controller;
  @override
  State<_BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<_BookingDetailPage>
    with BookingOwnedDialogs<_BookingDetailPage> {
  bool get live => mounted && c.live;

  Future<T?> navigate<T>(Route<T> route) async {
    if (!live || !(ModalRoute.of(context)?.isCurrent ?? true)) return null;
    return Navigator.of(context).push(route);
  }

  bool confirming = false;
  bool _openingChat = false;
  Future<void> openChat() async {
    if (_openingChat || !live) return;
    setState(() => _openingChat = true);
    try {
      final chat = await c.api.request(
        'POST',
        '/bookings/${widget.id}/conversation',
        {},
      );
      if (!mounted || !live) return;
      await navigate(
        MaterialPageRoute(
          builder: (_) =>
              ConversationPage(api: c.api, conversationId: chat['id']),
        ),
      );
    } catch (error) {
      if (mounted && live) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (live) setState(() => _openingChat = false);
    }
  }

  final _dialogControllers = <TextEditingController>[];
  late final BookingController c =
      widget.controller ?? BookingController(widget.api, widget.id);
  @override
  void initState() {
    super.initState();
    c.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in _dialogControllers) {
        controller.dispose();
      }
    });
  }

  Future<void> act(String action) async {
    if (!live || confirming || c.sending || c.loading || c.booking == null) {
      return;
    }
    confirming = true;
    final reason = TextEditingController();
    _dialogControllers.add(reason);
    final price = c.booking!['snapshot']['price'];
    final confirmed = await showOwnedDialog<bool>(
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          action == 'accept'
              ? lt('Buyurtmani qabul qilish', 'Accept booking', 'Принять заказ')
              : action == 'start'
              ? lt(
                  'Xizmat boshlanishini tasdiqlash',
                  'Confirm service start',
                  'Подтвердить начало услуги',
                )
              : action == 'complete'
              ? lt(
                  'Xizmat yakunini tasdiqlash',
                  'Confirm service completion',
                  'Подтвердить завершение услуги',
                )
              : action == 'reject'
              ? lt('So‘rovni rad etish', 'Reject request', 'Отклонить запрос')
              : lt(
                  'Buyurtmani bekor qilish',
                  'Cancel booking',
                  'Отменить заказ',
                ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action == 'accept')
              Text(
                lt(
                  'Balansingizdan ${bookingMoney(price['commission_minor'])} komissiya yechiladi. Xizmat pulini mijoz sizga bevosita to‘laydi.',
                  '${bookingMoney(price['commission_minor'])} commission will be debited from your balance. The customer pays you directly for the service.',
                  'С баланса будет списана комиссия ${bookingMoney(price['commission_minor'])}. Клиент оплачивает услугу вам напрямую.',
                ),
              )
            else if (action == 'start' || action == 'complete')
              Text(
                lt(
                  action == 'start'
                      ? 'Xizmat amalda boshlanganini tasdiqlang. Ikkala tomon tasdiqlagach parvarish faol bo‘ladi. Rejadagi boshlanish vaqtidan oldin tasdiqlab bo‘lmaydi.'
                      : 'Xizmat amalda tugaganini tasdiqlang. Ikkinchi tomon ham tasdiqlashi kerak. Oldinroq tugatish kelishilgan narxni o‘zgartirmaydi va avtomatik qaytim yaratmaydi.',
                  action == 'start'
                      ? 'Confirm the service has actually started. Both parties must confirm. Confirmation is allowed only from the scheduled start.'
                      : 'Confirm the service has actually finished. Both parties must confirm. Finishing early does not change the agreed price or create an automatic refund.',
                  action == 'start'
                      ? 'Подтвердите фактическое начало услуги. Требуется подтверждение обеих сторон, не ранее запланированного начала.'
                      : 'Подтвердите фактическое завершение услуги. Требуется подтверждение обеих сторон. Досрочное завершение не меняет цену и не создаёт автоматический возврат.',
                ),
              )
            else
              TextField(
                controller: reason,
                maxLength: 1000,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: lt('Sabab', 'Reason', 'Причина'),
                ),
              ),
            if (action == 'cancel')
              Text(
                lt(
                  'Xizmat boshlanishidan oldin komissiya enaga balansiga qaytadi. Momiq mijozning xizmat pulini qaytarmaydi.',
                  'Before service starts, commission returns to the sitter balance. Momiq does not refund the customer service payment.',
                  'До начала услуги комиссия вернётся на баланс няни. Momiq не возвращает оплату услуги клиентом.',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Ortga', 'Back', 'Назад')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(lt('Tasdiqlash', 'Confirm', 'Подтвердить')),
          ),
        ],
      ),
    );
    confirming = false;
    if (!mounted || !live) return;
    final text = reason.text;
    // Keep the controller alive through the dialog's reverse transition.
    if (confirmed == true && mounted && live) {
      if (['reject', 'cancel'].contains(action) && text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lt('Sababni kiriting', 'Enter a reason', 'Укажите причину'),
            ),
          ),
        );
        return;
      }
      await c.act(action, reason: text);
    }
  }

  Future<void> discard() async {
    if (!live || confirming || c.sending || c.loading) return;
    confirming = true;
    final confirmed = await showOwnedDialog<bool>(
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          lt(
            'Saqlangan urinishni tozalash',
            'Clear saved attempt',
            'Очистить сохранённую попытку',
          ),
        ),
        content: Text(
          lt(
            'Server bu amalni bajargan bo‘lishi mumkin. Bu buyurtmani bekor qilmaydi; holat qayta yuklanadi.',
            'The server may already have completed the action. This does not cancel the booking; its state will be reloaded.',
            'Сервер мог уже выполнить действие. Это не отменяет заказ; состояние будет загружено снова.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Ortga', 'Back', 'Назад')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(lt('Tozalash', 'Clear', 'Очистить')),
          ),
        ],
      ),
    );
    confirming = false;
    if (confirmed == true && mounted && live) {
      try {
        await c.discardUncertainAction();
      } catch (e) {
        if (mounted && live) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      context.dependOnInheritedWidgetOfExactType<AppLanguage>();
      if (!c.live) return bookingSourceExpired();
      final b = c.booking, s = b?['snapshot'], p = s?['price'];
      final locked = c.loading || c.sending || c.pending != null;
      return Scaffold(
        appBar: AppBar(
          title: Text(lt('Buyurtma', 'Booking', 'Заказ')),
          actions: [
            IconButton(
              onPressed: locked ? null : c.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (c.loading || c.sending) const LinearProgressIndicator(),
            if (c.error != null)
              Text(
                c.error.toString(),
                key: const ValueKey('bookingActionError'),
              ),
            if (b != null) ...[
              Text(
                bookingStateLabel(b['status']),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                b['myRole'] == 'sitter' ? s['customerName'] : s['sitterName'],
              ),
              Text(bookingServiceLabel(p['service'])),
              TextButton(
                key: const ValueKey('bookingAmendmentPolicy'),
                onPressed: () => showOwnedDialog<void>(
                  builder: (context) => AlertDialog(
                    scrollable: true,
                    title: Text(
                      lt(
                        'O‘zgartirish va uzaytirish',
                        'Changes and extensions',
                        'Изменения и продление',
                      ),
                    ),
                    content: Text(
                      lt(
                        'Bu buyurtmaning sanasi, hayvonlari, xizmati va narxi saqlangan. O‘zgartirish yoki uzaytirish uchun yangi narx taklifi va alohida so‘rov kerak. Yangi so‘rov eskisini avtomatik bekor qilmaydi. Boshlanishidan oldin mavjud bekor qilish qoidasi amal qiladi; xizmat boshlangan bo‘lsa yordamga murojaat qiling.',
                        'This booking keeps its agreed dates, pets, service and price. Changes or extensions require a new quote and a separate request. A new request does not automatically cancel the old booking. The existing cancellation policy applies before the service starts; contact support after it starts.',
                        'Даты, питомцы, услуга и цена этого заказа зафиксированы. Для изменений или продления нужны новый расчёт и отдельный запрос. Новый запрос не отменяет старый заказ автоматически. До начала услуги действует правило отмены; после начала обратитесь в поддержку.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(lt('Yopish', 'Close', 'Закрыть')),
                      ),
                    ],
                  ),
                ),
                child: Text(
                  lt(
                    'O‘zgartirish va uzaytirish qoidasi',
                    'Change and extension policy',
                    'Правила изменения и продления',
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('bookingConversation'),
                onPressed: _openingChat || locked ? null : openChat,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  lt(
                    'Buyurtma bo‘yicha yozishish',
                    'Chat about this booking',
                    'Переписка по заказу',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                key: const ValueKey('bookingSupport'),
                onPressed: locked
                    ? null
                    : () => navigate(
                        MaterialPageRoute<void>(
                          builder: (_) => SupportThreadPage(
                            api: c.api,
                            bookingId: widget.id,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.support_agent),
                label: Text(
                  lt(
                    'Buyurtma bo‘yicha yordam',
                    'Booking support',
                    'Помощь по заказу',
                  ),
                ),
              ),
              if ([
                'accepted',
                'active',
                'disputed',
                'cancelled',
              ].contains(b['status']))
                TextButton.icon(
                  key: const ValueKey('bookingDispute'),
                  onPressed: locked
                      ? null
                      : () async {
                          await navigate(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  BookingDisputePage(api: c.api, id: widget.id),
                            ),
                          );
                          await c.load();
                        },
                  icon: const Icon(Icons.report_outlined),
                  label: Text(
                    lt(
                      'Nizo / kelmaslik',
                      'Dispute / no-show',
                      'Спор / неявка',
                    ),
                  ),
                ),
              if (b['status'] == 'completed')
                TextButton.icon(
                  key: const ValueKey('bookingReview'),
                  onPressed: locked
                      ? null
                      : () => navigate(
                          MaterialPageRoute<void>(
                            builder: (_) => BookingReviewPage(
                              api: c.api,
                              bookingId: widget.id,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.star_outline),
                  label: Text(
                    lt('Buyurtma sharhi', 'Booking review', 'Отзыв о заказе'),
                  ),
                ),
              if ([
                'accepted',
                'active',
                'completed',
                'disputed',
                'cancelled',
              ].contains(b['status']))
                TextButton.icon(
                  key: const ValueKey('bookingCare'),
                  onPressed: locked
                      ? null
                      : () => navigate(
                          MaterialPageRoute<void>(
                            builder: (_) => BookingCarePage(
                              api: c.api,
                              bookingId: widget.id,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.pets),
                  label: Text(
                    lt(
                      'Kundalik parvarish va ko‘rsatmalar',
                      'Daily care and instructions',
                      'Ежедневный уход и инструкции',
                    ),
                  ),
                ),
              Text(
                '${bookingTime(s['startsAt'])} — ${bookingTime(s['endsAt'])}',
              ),
              Text(
                '${lt('Hisoblangan kun', 'Billable days', 'Оплачиваемые дни')}: ${p['billable_days']}',
              ),
              for (final pet in s['pets'] as List) ...[
                ListTile(
                  leading: const Icon(Icons.pets),
                  title: Text('${pet['name'] ?? pet['type']}'),
                  subtitle: Text('${pet['notes'] ?? ''}'),
                ),
                PetSafetySummary(pet: Map<String, dynamic>.from(pet)),
                for (final kind in ['photo', 'passport'])
                  if (pet[kind == 'photo' ? 'hasPhoto' : 'hasPassport'] == true)
                    BookingAnimalImage(
                      api: c.api,
                      bookingId: widget.id,
                      petId: pet['id'],
                      kind: kind,
                    ),
              ],
              Text('${s['address']['address']}'),
              if ('${s['instructions']}'.isNotEmpty) Text(s['instructions']),
              const Divider(),
              Text(
                '${lt('Xizmat jami', 'Service total', 'Стоимость услуги')}: ${bookingMoney(p['service_total_minor'])}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                lt(
                  'Xizmat uchun mijoz enagaga bevosita to‘laydi.',
                  'Customer pays the sitter directly.',
                  'Клиент платит няне напрямую.',
                ),
              ),
              if (b['myRole'] == 'sitter') ...[
                Text(
                  '${lt('Komissiya', 'Commission', 'Комиссия')}: ${p['commission_bps'] / 100}% — ${bookingMoney(p['commission_minor'])}',
                ),
                if (b['status'] == 'pending') ...[
                  FilledButton(
                    key: const ValueKey('acceptBooking'),
                    onPressed: locked ? null : () => act('accept'),
                    child: Text(lt('Qabul qilish', 'Accept', 'Принять')),
                  ),
                  OutlinedButton(
                    onPressed: locked ? null : () => act('reject'),
                    child: Text(lt('Rad etish', 'Reject', 'Отклонить')),
                  ),
                ],
              ],
              if (['accepted', 'active'].contains(b['status'])) ...[
                for (final action in [
                  b['status'] == 'accepted' ? 'start' : 'complete',
                ])
                  if ((b['confirmations']?[action]?['mine'] ?? false) == true)
                    Text(
                      lt(
                        'Siz tasdiqladingiz. Ikkinchi tomon tasdig‘i kutilmoqda.',
                        'You confirmed. Waiting for the other party.',
                        'Вы подтвердили. Ожидается подтверждение второй стороны.',
                      ),
                    )
                  else
                    FilledButton(
                      key: ValueKey('confirmBooking-$action'),
                      onPressed: locked ? null : () => act(action),
                      child: Text(
                        action == 'start'
                            ? lt(
                                'Xizmat boshlandi',
                                'Service has started',
                                'Услуга началась',
                              )
                            : lt(
                                'Xizmat yakunlandi',
                                'Service has finished',
                                'Услуга завершена',
                              ),
                      ),
                    ),
              ],
              if (['pending', 'accepted'].contains(b['status']))
                OutlinedButton(
                  key: const ValueKey('cancelBooking'),
                  onPressed: locked ? null : () => act('cancel'),
                  child: Text(lt('Bekor qilish', 'Cancel', 'Отменить')),
                ),
              if (c.pending != null) ...[
                Text(
                  lt(
                    'Oldingi urinish natijasi aniqlashtirilmoqda.',
                    'The previous attempt needs confirmation.',
                    'Результат предыдущей попытки требует проверки.',
                  ),
                ),
                FilledButton(
                  key: const ValueKey('retryBookingAction'),
                  onPressed: c.sending
                      ? null
                      : () => c.act(c.pending!['action']),
                  child: Text(
                    lt(
                      'O‘sha amalni qayta tekshirish',
                      'Retry the same action',
                      'Повторить то же действие',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: c.sending ? null : discard,
                  child: Text(
                    lt(
                      'Urinishni tozalash',
                      'Clear attempt',
                      'Очистить попытку',
                    ),
                  ),
                ),
              ],
              const Divider(),
              Text(lt('Holat tarixi', 'Status history', 'История статусов')),
              for (final event in b['history'] as List)
                ListTile(
                  title: Text(
                    event['action'] == 'start'
                        ? lt(
                            'Boshlash tasdig‘i',
                            'Start confirmation',
                            'Подтверждение начала',
                          )
                        : event['action'] == 'complete'
                        ? lt(
                            'Yakunlash tasdig‘i',
                            'Completion confirmation',
                            'Подтверждение завершения',
                          )
                        : bookingStateLabel(event['status']),
                  ),
                  subtitle: Text(
                    '${bookingTime(event['created'])}\n${event['reason']}',
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class BookingAnimalImage extends StatelessWidget {
  const BookingAnimalImage({
    super.key,
    required this.api,
    required this.bookingId,
    required this.petId,
    required this.kind,
  });
  final CustomerApi api;
  final String bookingId, petId, kind;
  @override
  Widget build(BuildContext context) => PrivateApiImage(
    api: api,
    path: '/bookings/$bookingId/pets/${Uri.encodeComponent(petId)}/$kind',
    label: kind == 'photo'
        ? lt('Hayvon rasmini ko‘rish', 'View pet photo', 'Фото питомца')
        : lt('Pasportni ko‘rish', 'View passport', 'Паспорт питомца'),
  );
}
