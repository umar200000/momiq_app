import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../data/booking_review_controller.dart';

class BookingReviewPage extends StatefulWidget {
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
  State<BookingReviewPage> createState() => _BookingReviewPageState();
}

class _BookingReviewPageState extends State<BookingReviewPage> {
  late final c =
      widget.controller ??
      BookingReviewController(widget.api, widget.bookingId);
  final text = TextEditingController();
  int stars = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await c.load();
    if (!mounted) return;
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

  Future<void> submit(String action) async {
    if (c.pending == null) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
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
      if (accepted != true || !mounted) return;
    }
    final existing = c.data?['review'];
    await c.submit(
      action == 'save' ? stars : existing['stars'],
      action == 'save' ? text.text : existing['text'],
      action: action,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
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
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (c.busy) const LinearProgressIndicator(),
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
