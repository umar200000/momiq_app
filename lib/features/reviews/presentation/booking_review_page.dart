import '../../bookings/presentation/booking_draft_recovery.dart';
import '../../bookings/presentation/booking_source_boundary.dart';
import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../data/booking_review_controller.dart';
import '../../support/support_page.dart';

class BookingReviewPage extends StatelessWidget {
  const BookingReviewPage({
    super.key,
    required this.api,
    required this.bookingId,
    this.controller,
  });
  final CustomerApi api;
  final String bookingId;
  final BookingReviewController? controller;
  @override
  Widget build(BuildContext context) => BookingSourceBoundary(
    api: api,
    valid:
        controller == null ||
        (identical(controller!.api, api) &&
            controller!.id == bookingId &&
            controller!.live),
    child: _BookingReviewPage(
      key: ValueKey((api, bookingId, controller)),
      api: api,
      bookingId: bookingId,
      controller: controller,
    ),
  );
}

class _BookingReviewPage extends StatefulWidget {
  const _BookingReviewPage({
    super.key,
    required this.api,
    required this.bookingId,
    this.controller,
  });
  final CustomerApi api;
  final String bookingId;
  final BookingReviewController? controller;
  @override
  State<_BookingReviewPage> createState() => _BookingReviewPageState();
}

class _BookingReviewPageState extends State<_BookingReviewPage>
    with OwnedDialogs<_BookingReviewPage> {
  late final c =
      widget.controller ??
      BookingReviewController(widget.api, widget.bookingId);
  final text = TextEditingController();
  int stars = 0;
  bool get live => mounted && c.live;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!live) return;
    await c.load();
    if (!live) return;
    final saved = c.pending ?? c.data?['review'];
    if (saved != null && saved['stars'] is int && saved['text'] is String) {
      setState(() {
        stars = saved['stars'];
        text.text = saved['text'];
      });
    }
  }

  @override
  void dispose() {
    text.dispose();
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  bool confirming = false;
  Future<void> submit(String action) async {
    if (!live || c.busy || confirming) return;
    final submittedStars = stars, submittedText = text.text;
    if (c.pending == null) {
      confirming = true;
      final accepted = await showOwnedDialog<bool>(
        builder: (context) => AlertDialog(
          scrollable: true,
          content: Text(
            action == 'save'
                ? lt(
                    'Yuborilgach matn va yulduzni tahrirlab bo‘lmaydi. Sharhni yuborasizmi?',
                    'The text and rating cannot be edited after submission. Submit this review?',
                    'После отправки текст и оценку нельзя изменить. Отправить отзыв?',
                  )
                : action == 'withdraw'
                ? lt(
                    'Sharh ommaviy ro‘yxatdan yashiriladi. Keyin ayni sharhni tiklash mumkin.',
                    'Hide the review from the public list. You can restore the same review later.',
                    'Отзыв скроется из общего списка. Позже можно восстановить тот же отзыв.',
                  )
                : lt(
                    'Ayni sharhni qayta ko‘rsatish? Moderatsiya cheklovi bo‘lsa saqlanadi.',
                    'Restore the same review? Any moderation restriction remains.',
                    'Показать тот же отзыв? Ограничение модерации сохранится.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(lt('Qaytish', 'Back', 'Назад')),
            ),
            FilledButton(
              key: const ValueKey('confirmReview'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(lt('Tasdiqlash', 'Confirm', 'Подтвердить')),
            ),
          ],
        ),
      );
      confirming = false;
      if (accepted != true || !live) return;
    }
    final existing = c.data?['review'];
    await c.submit(
      action == 'save' ? submittedStars : existing['stars'],
      action == 'save' ? submittedText : existing['text'],
      action: action,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.live) return bookingSourceExpired();
      final data = c.data, review = data?['review'];
      final editable =
          data?['canCreate'] == true &&
          c.pending == null &&
          !c.busy &&
          c.error == null &&
          c.live;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            lt('Buyurtma sharhi', 'Booking review', 'Отзыв о заказе'),
          ),
          actions: [
            IconButton(
              onPressed: c.busy ? null : load,
              tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.invalidDraft)
              BookingDraftRecovery(onClear: c.busy ? null : c.discard),
            if (c.error != null)
              Text(
                lt(
                  'Saqlash yoki yuklash amalga oshmadi. Holatni yangilang yoki ayni so‘rovni qayta yuboring.',
                  'Could not save or load. Refresh or retry the same request.',
                  'Не удалось сохранить или загрузить. Обновите или повторите тот же запрос.',
                ),
              ),
            Text(
              lt(
                'Bir tugallangan buyurtmaga bitta sharh. Yuborilgan matn va yulduz o‘zgarmaydi.',
                'One review per completed booking. Submitted text and rating cannot change.',
                'Один отзыв на завершённый заказ. Отправленные текст и оценка не изменяются.',
              ),
            ),
            if (review != null) ...[
              Text(
                '${review['stars']} / 5',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(review['text']),
              if (review['testOnly'] == true)
                Text(
                  lt(
                    'TEST sharh — umumiy reytingga kirmaydi.',
                    'TEST review — excluded from ratings.',
                    'TEST-отзыв — не учитывается в рейтинге.',
                  ),
                ),
              if (review['hidden'] == true)
                Text(
                  lt(
                    'Moderatsiya tomonidan yashirilgan.',
                    'Hidden by moderation.',
                    'Скрыт модерацией.',
                  ),
                ),
              if (review['withdrawn'] == true)
                Text(
                  lt(
                    'Siz sharhni yashirgansiz.',
                    'You withdrew this review.',
                    'Вы скрыли этот отзыв.',
                  ),
                ),
              if (data?['moderation'] != null)
                Text(data!['moderation']['reason']),
              if (data?['appealTarget'] is Map &&
                  c.live &&
                  !c.busy &&
                  c.pending == null)
                PublicContentReportButton(
                  api: widget.api,
                  target: Map<String, String>.from(data!['appealTarget']),
                ),
              if (data?['canWithdraw'] == true || data?['canRestore'] == true)
                TextButton(
                  onPressed: c.busy || c.pending != null
                      ? null
                      : () => submit(
                          data!['canRestore'] == true ? 'restore' : 'withdraw',
                        ),
                  child: Text(
                    data!['canRestore'] == true
                        ? lt(
                            'Ayni sharhni tiklash',
                            'Restore same review',
                            'Восстановить отзыв',
                          )
                        : lt(
                            'Sharhni yashirish',
                            'Hide review',
                            'Скрыть отзыв',
                          ),
                  ),
                ),
            ] else if (data != null && data['canCreate'] != true)
              Text(
                lt(
                  'Bu buyurtma uchun hozir sharh yozib bo‘lmaydi.',
                  'This booking is not eligible for a review.',
                  'Для этого заказа сейчас нельзя оставить отзыв.',
                ),
              ),
            if (data?['canCreate'] == true || c.pending != null) ...[
              Wrap(
                children: [
                  for (var rating = 1; rating <= 5; rating++)
                    IconButton(
                      key: ValueKey('reviewStar-$rating'),
                      tooltip: '$rating / 5',
                      onPressed: editable
                          ? () => setState(() => stars = rating)
                          : null,
                      icon: Icon(
                        rating <= stars ? Icons.star : Icons.star_border,
                      ),
                    ),
                ],
              ),
              TextField(
                key: const ValueKey('reviewText'),
                controller: text,
                enabled: editable,
                maxLength: 2000,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: lt(
                    'Sharh (ixtiyoriy)',
                    'Review (optional)',
                    'Отзыв (необязательно)',
                  ),
                ),
              ),
              FilledButton(
                key: const ValueKey('submitReview'),
                onPressed:
                    c.busy ||
                        !c.live ||
                        (c.pending == null && (!editable || stars == 0))
                    ? null
                    : () => submit(c.pending?['action'] ?? 'save'),
                child: Text(
                  c.pending != null
                      ? lt(
                          'Ayni so‘rovni qayta yuborish',
                          'Retry same request',
                          'Повторить тот же запрос',
                        )
                      : lt(
                          'Sharhni yuborish',
                          'Submit review',
                          'Отправить отзыв',
                        ),
                ),
              ),
            ],
            if (c.pending != null)
              TextButton(
                onPressed: c.busy ? null : c.discard,
                child: Text(
                  lt(
                    'Qayta yuborish qoralamasini tozalash',
                    'Clear retry draft',
                    'Очистить черновик повтора',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
