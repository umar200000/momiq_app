import 'package:flutter/material.dart';
import 'customer_widgets.dart';

class CustomerAvailability extends StatelessWidget {
  const CustomerAvailability({
    super.key,
    required this.store,
    required this.sitter,
    this.from,
    this.to,
    this.selected,
  });
  final CustomerStore store;
  final CJson sitter;
  final DateTime? from, to;
  final int? selected;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (sitter['availabilityKnown'] == true &&
          sitter['freeCapacity'] is int &&
          sitter['freeCapacity'] >= 0 &&
          sitter['freeCapacity'] <= 30) {
        final free = sitter['freeCapacity'] as int;
        final interval = sitter['availabilityInterval'] as Map?;
        String local(Object? value) {
          final time = DateTime.tryParse(
            '$value',
          )?.toUtc().add(const Duration(hours: 5));
          if (time == null) return '';
          String two(int n) => n.toString().padLeft(2, '0');
          return '${two(time.day)}.${two(time.month)} ${two(time.hour)}:${two(time.minute)}';
        }

        return Padding(
          key: ValueKey('availability-${sitter['id']}'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cText(
                free == 0
                    ? lt(
                        'Tanlangan vaqtda bo‘sh joy yo‘q',
                        'No availability for the selected dates',
                        'На выбранные даты нет свободных мест',
                      )
                    : sitter['service'] == 1
                    ? lt(
                        'Tanlangan vaqtda boshqa tashrif bilan band emas',
                        'No overlapping visit for the selected dates',
                        'На выбранные даты нет другого визита',
                      )
                    : lt(
                        'Tanlangan vaqtda $free ta bo‘sh joy',
                        '$free ${free == 1 ? 'place' : 'places'} available for the selected dates',
                        'Свободных мест на выбранные даты: $free',
                      ),
                bold: true,
                size: 13,
              ),
              if (interval != null)
                cText(
                  '${local(interval['startsAt'])} — ${local(interval['endsAt'])} (${lt('Toshkent', 'Tashkent', 'Ташкент')})',
                  size: 12,
                ),
              cText(
                lt(
                  'Qabul qilishda qayta tekshiriladi; bu joyni band qilmaydi.',
                  'Checked again on acceptance; this does not reserve a place.',
                  'Повторно проверяется при принятии заказа; место не бронируется.',
                ),
                size: 12,
              ),
            ],
          ),
        );
      }
      // Missing/invalid server capacity must not become a local promise of space.
      {
        final availability = sitter['availability'] as Map?;
        final schedule = availability?['schedule'] as Map?;
        final closed = List<String>.from(availability?['closedDates'] ?? []);
        String time(int minutes) =>
            '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
        final days = [
          lt('Du', 'Mon', 'Пн'),
          lt('Se', 'Tue', 'Вт'),
          lt('Ch', 'Wed', 'Ср'),
          lt('Pa', 'Thu', 'Чт'),
          lt('Ju', 'Fri', 'Пт'),
          lt('Sh', 'Sat', 'Сб'),
          lt('Ya', 'Sun', 'Вс'),
        ];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cText(
                lt(
                  'Mavjud sanalar hali tasdiqlanmagan',
                  'Availability has not been confirmed yet',
                  'Доступность дат пока не подтверждена',
                ),
                size: 13,
              ),
              if (availability != null) ...[
                const SizedBox(height: 6),
                cText(
                  schedule == null
                      ? lt(
                          'Olib kelish/ketish soati cheklanmagan; bronni enaga tasdiqlaydi.',
                          'No arrival/departure hours specified; the sitter must accept the booking.',
                          'Часы передачи и возврата не ограничены; заказ подтверждает няня.',
                        )
                      : '${lt('Olib kelish/ketish', 'Arrival/departure', 'Передача/возврат')}: ${[for (var i = 0; i < 7; i++)
                          if ((schedule['days'] as List)[i] == true) days[i]].join(', ')} · ${time(schedule['start'])}–${time(schedule['end'])} (${lt('Toshkent', 'Tashkent', 'Ташкент')})',
                  size: 12,
                ),
                cText(
                  lt(
                    'Tunda qolish mumkin. Yakuniy mavjudlik bron vaqtida tekshiriladi.',
                    'Overnight stays are allowed. Availability is checked when booking.',
                    'Можно оставаться на ночь. Доступность проверяется при бронировании.',
                  ),
                  size: 12,
                ),
                if (closed.isNotEmpty)
                  cText(
                    '${lt('Yangi bron boshlanmaydi', 'New bookings cannot start on', 'Новые заказы не могут начинаться')}: ${closed.join(', ')}',
                    size: 12,
                  ),
              ],
            ],
          ),
        );
      }
    },
  );
}
