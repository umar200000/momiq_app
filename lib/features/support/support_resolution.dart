import 'package:flutter/material.dart';
import '../listings/presentation/listing_style.dart' show lt;

/// Historical server snapshot, never an instruction to restore content.
class SupportResolution extends StatelessWidget {
  const SupportResolution({super.key, required this.value});
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final root = value;
    final snapshot = root is Map ? root['snapshot'] : null;
    if (snapshot is! Map ||
        !const ['listing', 'review'].contains(snapshot['kind']) ||
        snapshot['available'] is! bool ||
        (snapshot['kind'] == 'review' &&
            snapshot['available'] == true &&
            (snapshot['hidden'] is! bool || snapshot['withdrawn'] is! bool))) {
      return Text(
        lt(
          'Qaror nusxasi o‘qilmadi. Murojaatni yangilang.',
          'The decision snapshot could not be read. Refresh the request.',
          'Не удалось прочитать копию решения. Обновите обращение.',
        ),
      );
    }
    final decision = snapshot['decision'];
    final reason = decision is Map ? decision['reason'] : null;
    final revision = snapshot['sourceRevision'];
    String status;
    if (snapshot['available'] == false) {
      status = lt(
        'Manba mavjud emas',
        'Source unavailable',
        'Источник недоступен',
      );
    } else if (snapshot['kind'] == 'review') {
      status = snapshot['hidden'] == true
          ? lt(
              'Moderatsiya yashirgan',
              'Hidden by moderation',
              'Скрыто модерацией',
            )
          : lt(
              'Moderatsiya cheklovi yo‘q',
              'No moderation restriction',
              'Нет ограничения модерации',
            );
    } else {
      status = switch (snapshot['status']) {
        'approved' => lt('Tasdiqlangan', 'Approved', 'Одобрено'),
        'rejected' => lt('Rad etilgan', 'Rejected', 'Отклонено'),
        'suspended' => lt('To‘xtatilgan', 'Suspended', 'Приостановлено'),
        'pending' => lt(
          'Ko‘rib chiqilmoqda',
          'Pending review',
          'На рассмотрении',
        ),
        'draft' => lt('Qoralama', 'Draft', 'Черновик'),
        'archived' => lt('Arxivlangan', 'Archived', 'В архиве'),
        _ => lt('Holat noma’lum', 'Status unknown', 'Статус неизвестен'),
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          lt(
            'Yopish paytidagi qaror',
            'Decision at closure',
            'Решение на момент закрытия',
          ),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(status),
        if (snapshot['kind'] == 'review' && snapshot['withdrawn'] == true)
          Text(
            lt('Muallif yashirgan', 'Withdrawn by author', 'Скрыто автором'),
          ),
        if (revision is int && revision >= 0)
          Text(
            '${lt('Manba versiyasi', 'Source version', 'Версия источника')}: $revision',
          ),
        if (reason is String && reason.trim().isNotEmpty) Text(reason),
        Text(
          lt(
            'Bu saqlangan nusxa. Murojaatni yopish kontentni avtomatik tiklamaydi.',
            'This is a saved snapshot. Closing the request does not automatically restore content.',
            'Это сохранённая копия. Закрытие обращения не восстанавливает контент автоматически.',
          ),
        ),
      ],
    );
  }
}
