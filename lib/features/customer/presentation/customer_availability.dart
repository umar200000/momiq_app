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
          sitter['freeCapacity'] is int) {
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
                sitter['service'] == 1
                    ? 'Tanlangan vaqtda boshqa tashrif bilan band emas'
                    : 'Tanlangan vaqtda $free ta bo‘sh joy',
                bold: true,
                size: 13,
              ),
              if (interval != null)
                cText(
                  '${local(interval['startsAt'])} — ${local(interval['endsAt'])} (Toshkent)',
                  size: 12,
                ),
              cText(
                'Qabul qilishda qayta tekshiriladi; bu joyni band qilmaydi.',
                size: 12,
              ),
            ],
          ),
        );
      }
      if (sitter['availabilityKnown'] != true) {
        final availability = sitter['availability'] as Map?;
        final schedule = availability?['schedule'] as Map?;
        final closed = List<String>.from(availability?['closedDates'] ?? []);
        String time(int minutes) =>
            '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
        const days = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cText('Mavjud sanalar hali tasdiqlanmagan', size: 13),
              if (availability != null) ...[
                const SizedBox(height: 6),
                cText(
                  schedule == null
                      ? 'Olib kelish/ketish soati cheklanmagan; bronni enaga tasdiqlaydi.'
                      : 'Olib kelish/ketish: ${[for (var i = 0; i < 7; i++)
                          if ((schedule['days'] as List)[i] == true) days[i]].join(', ')} · ${time(schedule['start'])}–${time(schedule['end'])} (Toshkent)',
                  size: 12,
                ),
                cText(
                  'Tunda qolish mumkin. Yakuniy mavjudlik bron vaqtida tekshiriladi.',
                  size: 12,
                ),
                if (closed.isNotEmpty)
                  cText(
                    'Yangi bron boshlanmaydi: ${closed.join(', ')}',
                    size: 12,
                  ),
              ],
            ],
          ),
        );
      }
      final capacity = sitterCapacity(sitter);
      final free = store.availablePlaces(sitter, from: from, to: to);
      final occupied = capacity - free;
      final color = free == 0
          ? const Color(0xFFA34C37)
          : const Color(0xFF557146);
      if (sitter['service'] == 1) {
        return Padding(
          key: ValueKey('availability-${sitter['id']}'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cText(
                free == 0 ? 'Band' : 'Bo‘sh',
                bold: true,
                color: color,
                size: 14,
              ),
              if (free == 0) ...[
                const SizedBox(height: 6),
                cText('Bo‘sh sana hali aniqlanmagan', size: 13),
                cText('Buyurtma berish xizmati hali ulanmagan.', size: 12),
              ],
            ],
          ),
        );
      }
      return Container(
        key: ValueKey('availability-${sitter['id']}'),
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cText(
              free == 0
                  ? 'To‘liq band · bo‘sh joy yo‘q'
                  : 'Bo‘sh · $free ta joy mavjud',
              bold: true,
              color: color,
              size: 14,
            ),
            if (free == 0) ...[
              const SizedBox(height: 6),
              cText('Bo‘sh sana hali aniqlanmagan', size: 13),
              cText('Buyurtma berish xizmati hali ulanmagan.', size: 12),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < capacity; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      i < occupied ? Icons.pets : Icons.pets_outlined,
                      size: 22,
                      color: i < occupied
                          ? listingGold
                          : color.withValues(alpha: .35),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            cText(
              'Jami $capacity ta joy · $occupied ta band · $free ta bo‘sh',
              size: 12,
            ),
            if (sitter['service'] == 2)
              cText('Shaxsiy enaga faqat 1 ta hayvon qabul qiladi.', size: 12),
            if (selected != null)
              cText('Tanlandi: $selected / $free ta', bold: true, size: 13),
          ],
        ),
      );
    },
  );
}
