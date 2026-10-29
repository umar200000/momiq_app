import 'booking_draft_recovery.dart';
import 'booking_source_boundary.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../support/support_page.dart' show SupportImage;
import '../../wallet/data/receipt_image.dart';
import '../data/booking_dispute_controller.dart';
import 'bookings_page.dart' show bookingTime, bookingMoney;

class BookingDisputePage extends StatelessWidget {
  const BookingDisputePage({
    super.key,
    required this.api,
    required this.id,
    this.controller,
  });
  final CustomerApi api;
  final String id;
  final BookingDisputeController? controller;
  @override
  Widget build(BuildContext context) => BookingSourceBoundary(
    api: api,
    valid:
        controller == null ||
        (identical(controller!.api, api) &&
            controller!.id == id &&
            controller!.live),
    child: _BookingDisputePage(
      key: ValueKey((api, id, controller)),
      api: api,
      id: id,
      controller: controller,
    ),
  );
}

class _BookingDisputePage extends StatefulWidget {
  const _BookingDisputePage({
    super.key,
    required this.api,
    required this.id,
    this.controller,
  });
  final CustomerApi api;
  final String id;
  final BookingDisputeController? controller;
  @override
  State<_BookingDisputePage> createState() => _BookingDisputePageState();
}

class _BookingDisputePageState extends State<_BookingDisputePage>
    with WidgetsBindingObserver, BookingOwnedDialogs<_BookingDisputePage> {
  late final c =
      widget.controller ?? BookingDisputeController(widget.api, widget.id);
  final text = TextEditingController();
  String? image;
  bool picking = false;
  Timer? timer;
  bool get live => mounted && c.live;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    startTimer();
  }

  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (live && !picking && (ModalRoute.of(context)?.isCurrent ?? true)) {
        c.load();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load();
      startTimer();
    } else {
      timer?.cancel();
    }
  }

  Future<void> load() async {
    if (!live) return;
    await c.load();
    if (!live) return;
    if (c.pending != null) {
      setState(() {
        text.text = c.pending!['text'];
        image = c.pending!['image'];
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    text.dispose();
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void notice(String value) {
    if (live) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> pick() async {
    if (!live || picking || c.busy || c.pending != null) return;
    setState(() => picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        requestFullMetadata: false,
      );
      if (file != null && live) {
        if (await file.length() > 3 * 1024 * 1024) {
          throw const FormatException('size');
        }
        if (!live) return;
        final bytes = await file.readAsBytes();
        if (!live) return;
        await validateReceiptImage(bytes);
        if (live && c.live) setState(() => image = base64Encode(bytes));
      }
    } catch (_) {
      notice(
        lt(
          'Rasm ochilmadi. PNG/JPEG/WebP, 3 MB gacha.',
          'Could not open image. PNG/JPEG/WebP, up to 3 MB.',
          'Фото не открыто. PNG/JPEG/WebP, до 3 МБ.',
        ),
      );
    } finally {
      if (live) setState(() => picking = false);
    }
  }

  Future<void> send() async {
    if (!live || picking || c.busy) return;
    if (c.pending == null && text.text.trim().isEmpty) {
      notice(
        lt(
          'Holatni tushuntirib yozing.',
          'Describe what happened.',
          'Опишите ситуацию.',
        ),
      );
      return;
    }
    if (c.pending == null && c.data?['case'] == null) {
      final confirmed = await showOwnedDialog<bool>(
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
            lt('Nizo ochilsinmi?', 'Open a dispute?', 'Открыть спор?'),
          ),
          content: Text(
            lt(
              'Buyurtmani boshlash/yakunlash admin qarorigacha to‘xtatiladi. Murojaat 48 soat ichida ko‘rib chiqilishi kerak. Pul avtomatik qaytarilmaydi.',
              'Starting/completing the booking will pause until an admin decision. Review is due within 48 hours. No automatic refund.',
              'Начало/завершение заказа будет приостановлено до решения администратора. Срок рассмотрения — 48 часов. Автоматического возврата нет.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(lt('Ortga', 'Back', 'Назад')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(lt('Nizo ochish', 'Open dispute', 'Открыть спор')),
            ),
          ],
        ),
      );
      if (confirmed != true || !live || !c.live) return;
    }
    final sent = await c.send(text.text, image);
    if (live && sent) {
      setState(() {
        text.clear();
        image = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.live) return bookingSourceExpired();
      final data = c.data, caseData = data?['case'];
      final allowed =
          data?['canReportNoShow'] == true ||
          data?['canReportService'] == true ||
          data?['canAddEvidence'] == true;
      final enabled =
          c.live &&
          !c.busy &&
          !picking &&
          c.pending == null &&
          c.error == null &&
          allowed;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            lt('Nizo va kelmaslik', 'Dispute and no-show', 'Спор и неявка'),
          ),
          actions: [
            IconButton(
              onPressed: c.busy ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              lt(
                'Momiq mijozning enagaga bergan xizmat pulini qaytarmaydi. Qarorga ko‘ra faqat enagadan yechilgan komissiya ichki balansga tiklanadi.',
                'Momiq does not refund service money paid directly to the sitter. Only charged commission may be restored to the sitter’s internal balance after a decision.',
                'Momiq не возвращает оплату услуги, переданную няне. По решению возвращается только списанная комиссия на внутренний баланс няни.',
              ),
            ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.invalidDraft)
              BookingDraftRecovery(onClear: c.busy ? null : c.discard),
            if (c.error != null)
              Text(
                lt(
                  'Yuklash/yuborish amalga oshmadi. Yangilang yoki ayni so‘rovni qayta yuboring.',
                  'Could not load/send. Refresh or retry the same request.',
                  'Не удалось загрузить/отправить. Обновите или повторите тот же запрос.',
                ),
              ),
            if (data?['stage'] == 'contact_reminder' && caseData == null)
              Text(
                lt(
                  '15 daqiqa o‘tdi. Avval chat orqali bog‘laning. 30 daqiqadan keyin kelmaslik murojaati ochiladi.',
                  '15 minutes have passed. Try contacting them in chat. A no-show report becomes available after 30 minutes.',
                  'Прошло 15 минут. Свяжитесь через чат. Сообщить о неявке можно через 30 минут.',
                ),
              ),
            if (data != null &&
                caseData == null &&
                !allowed &&
                data['stage'] != 'contact_reminder')
              Text(
                data['bookingStatus'] == 'accepted'
                    ? lt(
                        'Kelmaslik uchun boshlanishdan 30 daqiqa o‘tishi kerak.',
                        'No-show reports require 30 minutes after the scheduled start.',
                        'Для сообщения о неявке должно пройти 30 минут после начала.',
                      )
                    : lt(
                        'Bu holatda yangi nizo ochilmaydi. Buyurtma bo‘yicha Yordam orqali murojaat qilishingiz mumkin.',
                        'A new dispute cannot be opened in this state. You can contact booking support.',
                        'В этом состоянии новый спор открыть нельзя. Обратитесь в поддержку по заказу.',
                      ),
              ),
            if (caseData != null) ...[
              Text(
                caseData['status'] == 'open'
                    ? lt(
                        'Admin ko‘rib chiqmoqda',
                        'Under admin review',
                        'На рассмотрении',
                      )
                    : lt(
                        'Qaror chiqarilgan',
                        'Decision issued',
                        'Решение принято',
                      ),
              ),
              Text(
                '${lt('Ko‘rib chiqish muddati', 'Review deadline', 'Срок рассмотрения')}: ${bookingTime(caseData['deadline'])}',
              ),
              if (caseData['overdue'] == true)
                Text(
                  lt(
                    '48 soatlik muddat o‘tgan. Bu avtomatik qaror yoki qaytim emas.',
                    'The 48-hour deadline has passed. This is not an automatic decision or refund.',
                    'Срок 48 часов истёк. Это не означает автоматическое решение или возврат.',
                  ),
                ),
              if (caseData['reason'] != null) Text(caseData['reason']),
              if (caseData['status'] == 'resolved')
                Text(switch (caseData['outcome']) {
                  'not_started' => lt(
                    'Xizmat boshlanmagan; buyurtma bekor qilingan.',
                    'Service did not start; booking cancelled.',
                    'Услуга не началась; заказ отменён.',
                  ),
                  'continue' => lt(
                    'Buyurtma avvalgi holatiga qaytarilgan.',
                    'Booking restored to its previous state.',
                    'Заказ возвращён в прежнее состояние.',
                  ),
                  'cancel_service' => lt(
                    'Boshlangan xizmat bekor qilingan.',
                    'The started service was cancelled.',
                    'Начатая услуга отменена.',
                  ),
                  _ => '',
                }),
              if (caseData['status'] == 'resolved')
                Text(
                  '${lt('Komissiya qaytimi', 'Commission refund', 'Возврат комиссии')}: ${bookingMoney(caseData['refundMinor'])}',
                ),
            ],
            if (data?['nextCursor'] != null)
              TextButton(
                onPressed: c.busy ? null : () => c.load(more: true),
                child: Text(
                  lt(
                    'Oldingi dalillar',
                    'Earlier evidence',
                    'Предыдущие материалы',
                  ),
                ),
              ),
            for (final item in data?['items'] ?? [])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['role'] == 'admin'
                            ? lt(
                                'Momiq qarori',
                                'Momiq decision',
                                'Решение Momiq',
                              )
                            : lt(
                                'Sizning dalilingiz',
                                'Your evidence',
                                'Ваши материалы',
                              ),
                      ),
                      Text(item['text']),
                      Text(bookingTime(item['created'])),
                      if (item['hasImage'] == true)
                        SupportImage(
                          api: widget.api,
                          path: '${c.path}/evidence/${item['id']}/image',
                        ),
                    ],
                  ),
                ),
              ),
            if (allowed || c.pending != null) ...[
              Text(
                lt(
                  'Izoh va rasmni faqat siz hamda operator ko‘radi. Admin qarori ikkala tomonga ko‘rinadi.',
                  'Only you and the operator see your evidence. Admin decisions are visible to both parties.',
                  'Ваши материалы видны только вам и оператору. Решение видно обеим сторонам.',
                ),
              ),
              TextField(
                key: const ValueKey('disputeText'),
                controller: text,
                enabled: enabled,
                maxLength: 4000,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: lt(
                    'Holat va dalil',
                    'Situation and evidence',
                    'Ситуация и доказательства',
                  ),
                ),
              ),
              if (image != null)
                Image.memory(
                  base64Decode(image!),
                  height: 140,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                ),
              TextButton.icon(
                onPressed: enabled ? pick : null,
                icon: const Icon(Icons.image),
                label: Text(
                  lt('Rasm biriktirish', 'Attach image', 'Прикрепить фото'),
                ),
              ),
              if (image != null)
                TextButton(
                  onPressed: enabled
                      ? () => setState(() => image = null)
                      : null,
                  child: Text(
                    lt('Rasmni olib tashlash', 'Remove image', 'Убрать фото'),
                  ),
                ),
              FilledButton(
                key: const ValueKey('submitDispute'),
                onPressed:
                    c.live &&
                        !c.busy &&
                        !picking &&
                        (enabled || c.pending != null)
                    ? send
                    : null,
                child: Text(
                  c.pending != null
                      ? lt(
                          'Ayni so‘rovni qayta yuborish',
                          'Retry same request',
                          'Повторить тот же запрос',
                        )
                      : caseData == null
                      ? lt('Nizo ochish', 'Open dispute', 'Открыть спор')
                      : lt(
                          'Dalil yuborish',
                          'Send evidence',
                          'Отправить материалы',
                        ),
                ),
              ),
              if (c.pending != null)
                TextButton(
                  onPressed: c.busy ? null : c.discard,
                  child: Text(
                    lt(
                      'Qayta yuborish qoralamasini tozalash (nizoni yopmaydi)',
                      'Clear retry draft (does not close the dispute)',
                      'Очистить черновик повтора (не закрывает спор)',
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
