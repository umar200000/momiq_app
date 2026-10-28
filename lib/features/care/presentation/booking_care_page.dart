import 'dart:async';
import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../data/booking_care_controller.dart';

const careCategories = ['food', 'water', 'walk', 'medicine', 'other'];
String careCategory(String value) => switch (value) {
  'food' => lt('Ovqat', 'Food', 'Кормление'),
  'water' => lt('Suv', 'Water', 'Вода'),
  'walk' => lt('Sayr', 'Walk', 'Прогулка'),
  'medicine' => lt('Dori', 'Medication', 'Лекарства'),
  _ => lt('Boshqa', 'Other', 'Другое'),
};
String careState(String value) => switch (value) {
  'done' => lt(
    'Bajarildi deb qayd etilgan',
    'Reported done',
    'Отмечено как выполненное',
  ),
  'skipped' => lt(
    'Bajarilmagan, sabab yozilgan',
    'Skipped with a reason',
    'Пропущено с причиной',
  ),
  _ => lt(
    'Oldingi belgi bekor qilingan',
    'Previous mark reversed',
    'Предыдущая отметка отменена',
  ),
};

class BookingCarePage extends StatefulWidget {
  const BookingCarePage({
    super.key,
    required this.api,
    required this.bookingId,
    this.controller,
  });
  final CustomerApi api;
  final String bookingId;
  final BookingCareController? controller;
  @override
  State<BookingCarePage> createState() => _BookingCarePageState();
}

class _BookingCarePageState extends State<BookingCarePage>
    with WidgetsBindingObserver {
  Timer? timer;
  bool foreground = true;
  late final c =
      widget.controller ?? BookingCareController(widget.api, widget.bookingId);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.load();
    timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => refreshVisible(),
    );
  }

  void refreshVisible() {
    if (mounted && foreground && (ModalRoute.of(context)?.isCurrent ?? true)) {
      c.load(day: c.data?['day'] == c.data?['today'] ? null : c.data?['day']);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refreshVisible();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> edit(
    CareJson pet, {
    String? category,
    CareJson? previous,
  }) async {
    final instructions = category == null;
    final old = instructions ? pet['instructions'] : previous;
    final values = await showDialog<CareJson>(
      context: context,
      builder: (_) => _CareEditor(
        instructions: instructions,
        category: category,
        previous: old == null ? null : CareJson.from(old['payload']),
        correction: old != null,
      ),
    );
    if (values == null || !mounted) return;
    await c.save({
      'petId': pet['id'],
      'kind': instructions ? 'instructions' : 'report',
      'day': instructions ? '' : c.data!['day'],
      'category': category ?? '',
      'revision': old?['revision'] ?? 0,
      'payload': values,
    });
  }

  Future<void> changeDay() async {
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(c.data!['day']),
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(c.data!['today']),
    );
    if (day != null && mounted) {
      await c.load(day: day.toIso8601String().split('T').first);
    }
  }

  Future<void> discard() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(
          lt(
            'Faqat qayta yuborish qoralamasi tozalanadi. Serverda saqlangan yozuv o‘chmaydi. Keyin holat yangilanadi.',
            'Clear only the retry draft. Any saved server entry remains. The page will refresh.',
            'Удаляется только черновик повтора. Сохранённая запись останется на сервере. Данные обновятся.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Qaytish', 'Back', 'Назад')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(lt('Tozalash', 'Clear', 'Очистить')),
          ),
        ],
      ),
    );
    if (answer == true) await c.discard();
  }

  Widget event(CareJson item) {
    final p = CareJson.from(item['payload']);
    final pets = (c.data?['pets'] as List? ?? []).where(
      (p) => p['id'] == item['petId'],
    );
    final name = pets.isEmpty ? '' : '${pets.first['name']} · ';
    final details = p.entries
        .where((e) => e.key != 'state' && '${e.value}'.isNotEmpty)
        .map(
          (e) =>
              '${careCategories.contains(e.key) ? careCategory(e.key) : lt('Izoh / sabab', 'Note / reason', 'Комментарий / причина')}: ${e.value}',
        )
        .join('\n');
    return ListTile(
      title: Text(
        item['kind'] == 'instructions'
            ? lt(
                'Mijoz ko‘rsatmasi',
                'Customer instructions',
                'Инструкции клиента',
              )
            : '${careCategory(item['category'])}: ${careState(p['state'])}',
      ),
      subtitle: Text(
        '$name${item['day']} · ${item['created']} (UTC) · v${item['revision']}\n$details',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final data = c.data,
          locked = c.busy || c.pending != null || c.error != null || !c.live;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            lt('Kundalik parvarish', 'Daily care', 'Ежедневный уход'),
          ),
          actions: [
            IconButton(
              onPressed: c.busy ? null : () => c.load(day: data?['day']),
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
                  'Yuklash yoki saqlash amalga oshmadi. Holatni yangilang yoki shu yozuvni qayta yuboring.',
                  'Could not load or save. Refresh or retry this entry.',
                  'Не удалось загрузить или сохранить. Обновите или повторите запись.',
                ),
                key: const ValueKey('careError'),
              ),
            if (c.pending != null) ...[
              Text(
                lt(
                  'Saqlash tasdig‘i kutilmoqda. Qayta urinish aynan shu yozuvni yuboradi.',
                  'Awaiting confirmation. Retry sends this exact entry.',
                  'Ожидается подтверждение. Повтор отправит ту же запись.',
                ),
              ),
              FilledButton(
                key: const ValueKey('careRetry'),
                onPressed: c.busy ? null : () => c.save({}),
                child: Text(lt('Qayta yuborish', 'Retry', 'Повторить')),
              ),
              TextButton(
                onPressed: c.busy ? null : discard,
                child: Text(
                  lt('Qoralamani tozalash', 'Clear draft', 'Очистить черновик'),
                ),
              ),
            ],
            if (data != null) ...[
              Text('${data['day']} · Asia/Tashkent'),
              TextButton(
                onPressed: locked ? null : changeDay,
                child: Text(lt('Boshqa kun', 'Another day', 'Другой день')),
              ),
              Text(
                lt(
                  'Bu enaga kiritgan hisobot. Belgi xizmatning mustaqil tekshirilgan tasdig‘i emas. Qayd yo‘qligi — ma’lumot hali kiritilmaganini bildiradi.',
                  'These are sitter reports, not independent verification. No entry means no report has been submitted.',
                  'Это отчёт няни, а не независимая проверка. Отсутствие записи означает, что отчёт ещё не внесён.',
                ),
              ),
              if ('${data['originalInstructions']}'.isNotEmpty)
                Text(data['originalInstructions']),
              for (final raw in data['pets'] as List)
                Builder(
                  builder: (context) {
                    final pet = CareJson.from(raw),
                        instruction = pet['instructions'];
                    final reports = (pet['reports'] as List)
                        .map((e) => CareJson.from(e))
                        .toList();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pet['name'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if ('${pet['originalNotes']}'.isNotEmpty)
                              Text(pet['originalNotes']),
                            if ('${pet['originalMedication']}'.isNotEmpty)
                              Text(
                                '${careCategory('medicine')}: ${pet['originalMedication']}',
                              ),
                            if (instruction != null) ...[
                              for (final category in careCategories)
                                if ((instruction['payload'][category] as String)
                                    .isNotEmpty)
                                  Text(
                                    '${careCategory(category)}: ${instruction['payload'][category]}',
                                  ),
                              Text(
                                '${lt('Ko‘rsatma versiyasi', 'Instruction version', 'Версия инструкций')}: ${instruction['revision']}',
                              ),
                            ],
                            if (data['canEditInstructions'] == true)
                              TextButton(
                                key: ValueKey('careInstructions-${pet['id']}'),
                                onPressed: locked ? null : () => edit(pet),
                                child: Text(
                                  lt(
                                    'Ko‘rsatma va jadval',
                                    'Instructions and schedule',
                                    'Инструкции и расписание',
                                  ),
                                ),
                              ),
                            for (final category in careCategories)
                              Builder(
                                builder: (context) {
                                  final previous = reports
                                      .where((e) => e['category'] == category)
                                      .firstOrNull;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(careCategory(category)),
                                    subtitle: Text(
                                      previous == null
                                          ? lt(
                                              'Hali qayd yo‘q',
                                              'No report yet',
                                              'Записи пока нет',
                                            )
                                          : '${careState(previous['payload']['state'])}\n${previous['payload']['note']}\n${previous['created']} (UTC)',
                                    ),
                                    trailing: data['canReport'] == true
                                        ? IconButton(
                                            key: ValueKey(
                                              'careReport-${pet['id']}-$category',
                                            ),
                                            onPressed: locked
                                                ? null
                                                : () => edit(
                                                    pet,
                                                    category: category,
                                                    previous: previous,
                                                  ),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          )
                                        : null,
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              TextButton(
                onPressed:
                    c.busy || (c.historyLoaded && c.historyCursor == null)
                    ? null
                    : c.loadHistory,
                child: Text(
                  lt(
                    'O‘zgarishlar tarixi',
                    'Change history',
                    'История изменений',
                  ),
                ),
              ),
              for (final item in c.history) event(item),
              if (c.historyLoaded && c.history.isEmpty)
                Text(lt('Tarix bo‘sh', 'No history yet', 'История пуста')),
            ],
          ],
        ),
      );
    },
  );
}

class _CareEditor extends StatefulWidget {
  const _CareEditor({
    required this.instructions,
    this.category,
    this.previous,
    required this.correction,
  });
  final bool instructions, correction;
  final String? category;
  final CareJson? previous;
  @override
  State<_CareEditor> createState() => _CareEditorState();
}

class _CareEditorState extends State<_CareEditor> {
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final key
        in widget.instructions ? [...careCategories, 'reason'] : ['note'])
      key: TextEditingController(
        text: key == 'reason' ? '' : widget.previous?[key] ?? '',
      ),
  };
  late String state = widget.previous?['state'] ?? 'done';
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.instructions
          ? lt(
              'Ko‘rsatma va jadval',
              'Instructions and schedule',
              'Инструкции и расписание',
            )
          : careCategory(widget.category!),
    ),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.instructions)
              Text(
                lt(
                  'Har bo‘limda nima va qachon qilish kerakligini yozing. Bu sana yoki narxni o‘zgartirmaydi.',
                  'Describe what to do and when. This does not change booking dates or price.',
                  'Укажите, что и когда делать. Это не меняет даты или цену заказа.',
                ),
              ),
            if (!widget.instructions)
              DropdownButtonFormField<String>(
                initialValue: state,
                items: [
                  for (final value in ['done', 'skipped', 'undone'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(careState(value)),
                    ),
                ],
                isExpanded: true,
                onChanged: (value) => setState(() => state = value!),
              ),
            for (final field in fields.entries)
              TextFormField(
                key: ValueKey('careField-${field.key}'),
                controller: field.value,
                maxLength: field.key == 'reason' ? 500 : 2000,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: careCategories.contains(field.key)
                      ? careCategory(field.key)
                      : lt(
                          'Izoh / sabab',
                          'Note / reason',
                          'Комментарий / причина',
                        ),
                ),
                validator: (value) =>
                    (field.key == 'reason' ||
                            (!widget.instructions &&
                                (state != 'done' || widget.correction))) &&
                        (value ?? '').trim().isEmpty
                    ? lt('Sabab yozing', 'Enter a reason', 'Укажите причину')
                    : null,
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(lt('Qaytish', 'Back', 'Назад')),
      ),
      FilledButton(
        key: const ValueKey('careEditorSave'),
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, {
              for (final f in fields.entries) f.key: f.value.text,
              if (!widget.instructions) 'state': state,
            });
          }
        },
        child: Text(lt('Saqlash', 'Save', 'Сохранить')),
      ),
    ],
  );
}
