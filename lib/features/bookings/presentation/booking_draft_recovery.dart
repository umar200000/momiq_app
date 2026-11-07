import 'package:flutter/material.dart';
import '../../listings/presentation/listing_style.dart' show lt;

/// A malformed local retry is never automatically deleted or submitted.
class BookingDraftRecovery extends StatelessWidget {
  const BookingDraftRecovery({super.key, required this.onClear});
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        lt(
          'Saqlangan qoralamani o‘qib bo‘lmadi. Uni qayta yubora olmaymiz. Qoralamani tozalash serverdagi yozuvni o‘chirmaydi; keyin holat yangilanadi.',
          'The saved draft could not be read and cannot be resent. Clearing it does not delete any server entry; the page will then refresh.',
          'Сохранённый черновик не удалось прочитать и нельзя отправить повторно. Очистка не удалит запись на сервере; затем данные обновятся.',
        ),
      ),
      TextButton(
        key: const ValueKey('clearInvalidBookingDraft'),
        onPressed: onClear,
        child: Text(
          lt(
            'Buzilgan qoralamani tozalash',
            'Clear unreadable draft',
            'Очистить повреждённый черновик',
          ),
        ),
      ),
    ],
  );
}
