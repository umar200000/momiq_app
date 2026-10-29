import 'booking_source_boundary.dart';
import 'dart:convert';
import '../../../core/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../customer/data/customer_store.dart';
import '../../customer/presentation/customer_account.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../onboarding/data/profile_photo_source.dart';
import '../data/booking_composer.dart';
import 'bookings_page.dart';

class BookingRequestPage extends StatelessWidget {
  const BookingRequestPage({
    super.key,
    required this.store,
    required this.sitter,
    this.composer,
    this.photoSource,
    this.detailBuilder,
  });
  final CustomerStore store;
  final CJson sitter;
  final BookingComposer? composer;
  final ProfilePhotoSource? photoSource;
  final Widget Function(String id)? detailBuilder;
  @override
  Widget build(BuildContext context) {
    final api = store.api;
    if (api == null) return bookingSourceExpired();
    return BookingSourceBoundary(
      api: api,
      valid:
          composer == null ||
          (identical(composer!.api, api) &&
              composer!.listingId == sitter['id'] &&
              composer!.live),
      child: _BookingRequestPage(
        key: ValueKey((store, api, sitter['id'], composer, photoSource)),
        store: store,
        sitter: sitter,
        composer: composer,
        photoSource: photoSource,
        detailBuilder: detailBuilder,
      ),
    );
  }
}

class _BookingRequestPage extends StatefulWidget {
  const _BookingRequestPage({
    super.key,
    required this.store,
    required this.sitter,
    this.composer,
    this.photoSource,
    this.detailBuilder,
  });
  final CustomerStore store;
  final CJson sitter;
  final BookingComposer? composer;
  final ProfilePhotoSource? photoSource;
  final Widget Function(String id)? detailBuilder;
  @override
  State<_BookingRequestPage> createState() => _BookingRequestPageState();
}

class _BookingRequestPageState extends State<_BookingRequestPage>
    with BookingOwnedDialogs<_BookingRequestPage> {
  bool get live => mounted && c.live && identical(widget.store.api, c.api);

  Future<T?> navigate<T>(Route<T> route) async {
    if (!live || !(ModalRoute.of(context)?.isCurrent ?? true)) return null;
    return Navigator.of(context).push(route);
  }

  late final c =
      widget.composer ??
      BookingComposer(widget.store.api!, widget.sitter['id']);
  late final photos = widget.photoSource ?? ProfilePhotoSource();
  final instructions = TextEditingController();
  final pets = <String>{};
  final passports = <String, String>{};
  DateTime? start, end;
  String? addressId;
  int step = 0;
  bool picking = false;
  List<CJson> get choices => widget.store
      .list('pets')
      .where((p) => allowedCustomerPetTypes(widget.sitter).contains(p['type']))
      .toList();
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    if (!live) return;
    await c.load();
    if (!live || !c.ready) return;
    final d = c.draft;
    pets.addAll((d['petIds'] as List? ?? []).cast<String>());
    if (d['startsAt'] is String) start = DateTime.tryParse(d['startsAt']);
    if (d['endsAt'] is String) end = DateTime.tryParse(d['endsAt']);
    addressId = d['addressId'];
    instructions.text = d['instructions'] ?? '';
    passports.addAll(Map<String, String>.from(d['petPassports'] ?? {}));
    if (c.pending == null) {
      final eligibleIds = choices.map((p) => p['id']).toSet();
      final removed = pets.any((id) => !eligibleIds.contains(id));
      pets.retainAll(eligibleIds);
      if (removed) await c.saveDraft(fields());
      if (!live) return;
    }
    if (c.quote != null || c.pending != null) step = 3;
    setState(() {});
  }

  @override
  void dispose() {
    if (widget.composer == null) c.dispose();
    instructions.dispose();
    super.dispose();
  }

  CJson fields() => {
    'petIds': pets.toList()..sort(),
    if (start != null) 'startsAt': start!.toUtc().toIso8601String(),
    if (end != null) 'endsAt': end!.toUtc().toIso8601String(),
    if (widget.sitter['service'] == 1 && addressId != null)
      'addressId': addressId,
    'instructions': instructions.text.trim(),
    'petPassports': {
      for (final p in pets)
        if (passports.containsKey(p)) p: passports[p],
    },
  };
  void notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> pickTime(bool from) async {
    if (!live || c.busy || picking || c.pending != null) return;
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final old =
        (from ? start : end)?.toUtc().add(const Duration(hours: 5)) ?? now;
    final day = await showOwnedDatePicker(
      initialDate: old.isBefore(now) ? now : old,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (day == null || !live) return;
    final time = await showOwnedDialog<TimeOfDay>(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: TimePickerDialog(
          initialTime: TimeOfDay(hour: old.hour, minute: old.minute),
          helpText: lt('Toshkent vaqti', 'Tashkent time', 'Время Ташкента'),
        ),
      ),
    );
    if (time == null || !live) return;
    final value = DateTime.utc(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 5));
    setState(() {
      if (from) {
        start = value;
      } else {
        end = value;
      }
    });
  }

  Future<void> pickPassport(String id) async {
    if (!live || picking || c.busy || c.pending != null) return;
    setState(() => picking = true);
    try {
      final source = await showOwnedSheet<ImageSource>(
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(lt('Kamera', 'Camera', 'Камера')),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                title: Text(lt('Galereya', 'Gallery', 'Галерея')),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null || !live) return;
      final bytes = await photos.pickProfile(source: source);
      if (bytes != null && live) {
        if (bytes.length > 3 * 1024 * 1024) {
          throw StateError('Rasm 3 MB dan kichik bo‘lishi kerak');
        }
        setState(() => passports[id] = base64Encode(bytes));
      }
    } catch (e) {
      if (live) notice(e.toString());
    } finally {
      if (live) setState(() => picking = false);
    }
  }

  Future<void> next() async {
    if (!live || c.busy || picking || !c.ready) return;
    if (c.pending != null || step == 3) {
      if (await c.submit() &&
          mounted &&
          live &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                widget.detailBuilder?.call(c.result!['id']) ??
                BookingDetailPage(api: c.api, id: c.result!['id']),
          ),
        );
      }
      return;
    }
    if (pets.isEmpty) {
      notice(lt('Hayvonni tanlang', 'Select a pet', 'Выберите питомца'));
      return;
    }
    if (widget.sitter['service'] == 2 && pets.length != 1) {
      notice(
        lt(
          'Shaxsiy enaga faqat bitta hayvon uchun',
          'Personal care is for one pet',
          'Персональная няня только для одного питомца',
        ),
      );
      return;
    }
    if (step >= 1 &&
        (start == null ||
            end == null ||
            !end!.isAfter(start!) ||
            !start!.isAfter(DateTime.now()))) {
      notice(
        lt(
          'Kelajakdagi boshlanish va tugash vaqtini tanlang',
          'Choose valid future start and end times',
          'Выберите корректное время начала и окончания',
        ),
      );
      return;
    }
    if (step >= 1 && widget.sitter['service'] == 1 && addressId == null) {
      notice(
        lt(
          'Saqlangan manzilni tanlang',
          'Choose a saved address',
          'Выберите сохранённый адрес',
        ),
      );
      return;
    }
    if (!await c.saveDraft(fields()) || !live) return;
    if (step == 2 && !await c.getQuote()) return;
    if (live) setState(() => step++);
  }

  Future<void> clearAttempt() async {
    if (!live || c.busy || picking) return;
    final confirm = await showOwnedDialog<bool>(
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          lt('Yangi taklif olish', 'Get a new quote', 'Получить новый расчёт'),
        ),
        content: Text(
          lt(
            'Oldingi so‘rov serverga yetgan bo‘lishi mumkin. Avval buyurtmalar ro‘yxatini tekshiring. Tozalash mavjud buyurtmani bekor qilmaydi.',
            'The previous request may have reached the server. Check your booking list first. Clearing does not cancel an existing booking.',
            'Предыдущий запрос мог дойти до сервера. Сначала проверьте список заказов. Очистка не отменяет существующий заказ.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Ortga', 'Back', 'Назад')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(lt('Davom etish', 'Continue', 'Продолжить')),
          ),
        ],
      ),
    );
    if (confirm != true || !live) return;
    try {
      await c.clearAttempt();
      if (live) setState(() => step = 2);
    } catch (e) {
      if (live) notice(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      context.dependOnInheritedWidgetOfExactType<AppLanguage>();
      if (!live) return bookingSourceExpired();
      final frozen = c.busy || picking || c.pending != null;
      final quote = c.quote?['snapshot'];
      return Scaffold(
        appBar: AppBar(
          title: Text(
            lt('Buyurtma so‘rovi', 'Booking request', 'Запрос заказа'),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${step + 1} / 4 — ${widget.sitter['name']}'),
            LinearProgressIndicator(value: (step + 1) / 4),
            if (c.busy || picking) const LinearProgressIndicator(),
            if (c.error != null)
              Text(
                c.error.toString(),
                key: const ValueKey('bookingComposeError'),
              ),
            if (!c.ready)
              TextButton(
                onPressed: c.busy ? null : initialize,
                child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
              ),
            if (step == 0) ...[
              Text(
                lt('Hayvonlarni tanlang', 'Select pets', 'Выберите питомцев'),
              ),
              for (final pet in choices)
                CheckboxListTile(
                  key: ValueKey('bookingPet-${pet['id']}'),
                  title: Text(customerPetName(pet)),
                  secondary: IconButton(
                    key: ValueKey('editBookingPet-${pet['id']}'),
                    tooltip: lt('Tahrirlash', 'Edit', 'Изменить'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: frozen
                        ? null
                        : () async {
                            await navigate(
                              MaterialPageRoute(
                                builder: (_) => CustomerPetForm(
                                  store: widget.store,
                                  pet: pet,
                                  allowedTypes: allowedCustomerPetTypes(
                                    widget.sitter,
                                  ),
                                ),
                              ),
                            );
                            if (live) setState(() {});
                          },
                  ),
                  value: pets.contains(pet['id']),
                  onChanged: frozen
                      ? null
                      : (value) => setState(
                          () => value == true
                              ? pets.add(pet['id'])
                              : pets.remove(pet['id']),
                        ),
                ),
              TextButton(
                onPressed: frozen
                    ? null
                    : () async {
                        await navigate(
                          MaterialPageRoute(
                            builder: (_) => CustomerPetForm(
                              store: widget.store,
                              allowedTypes: allowedCustomerPetTypes(
                                widget.sitter,
                              ),
                            ),
                          ),
                        );
                        if (live) setState(() {});
                      },
                child: Text(
                  lt('Hayvon qo‘shish', 'Add pet', 'Добавить питомца'),
                ),
              ),
            ],
            if (step == 1) ...[
              Text(
                lt(
                  'Har boshlangan 24 soat — 1 kun.',
                  'Each started 24 hours counts as one day.',
                  'Каждые начатые 24 часа считаются одним днём.',
                ),
              ),
              ListTile(
                key: const ValueKey('bookingStart'),
                title: Text(lt('Boshlanish', 'Start', 'Начало')),
                subtitle: Text(
                  start == null ? '—' : bookingTime(start!.toIso8601String()),
                ),
                onTap: frozen ? null : () => pickTime(true),
              ),
              ListTile(
                key: const ValueKey('bookingEnd'),
                title: Text(lt('Tugash', 'End', 'Окончание')),
                subtitle: Text(
                  end == null ? '—' : bookingTime(end!.toIso8601String()),
                ),
                onTap: frozen ? null : () => pickTime(false),
              ),
              if (widget.sitter['service'] == 1) ...[
                Text(
                  lt(
                    'Uyga tashrifda qolish davomiyligi narxni o‘zgartirmaydi.',
                    'Time spent during a home visit does not change the daily price.',
                    'Время пребывания во время визита не меняет дневную цену.',
                  ),
                ),
                TextButton(
                  onPressed: frozen
                      ? null
                      : () async {
                          final address = await navigate<CJson>(
                            MaterialPageRoute(
                              builder: (_) => CustomerAddressesPage(
                                store: widget.store,
                                select: true,
                              ),
                            ),
                          );
                          if (address != null && live) {
                            setState(() => addressId = address['id']);
                          }
                        },
                  child: Text(
                    addressId == null
                        ? lt(
                            'Manzilni tanlash',
                            'Select address',
                            'Выбрать адрес',
                          )
                        : widget.store
                              .list('addresses')
                              .firstWhere(
                                (a) => a['id'] == addressId,
                                orElse: () => {'address': '—'},
                              )['address'],
                  ),
                ),
              ],
            ],
            if (step == 2) ...[
              TextField(
                controller: instructions,
                enabled: !frozen,
                maxLength: 4000,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: lt(
                    'Parvarish ko‘rsatmalari',
                    'Care instructions',
                    'Инструкции по уходу',
                  ),
                ),
              ),
              Text(
                lt(
                  'Hayvon pasporti ixtiyoriy. Qo‘shilgan rasm shu buyurtma enagasiga ko‘rinadi.',
                  'Pet passport is optional. Attached images are shared with this booking’s sitter.',
                  'Паспорт питомца необязателен. Вложения будут доступны няне этого заказа.',
                ),
              ),
              for (final pet in choices.where((p) => pets.contains(p['id'])))
                Column(
                  children: [
                    Text(customerPetName(pet)),
                    if (passports[pet['id']] != null)
                      Image.memory(
                        base64Decode(passports[pet['id']]!),
                        height: 100,
                      ),
                    TextButton(
                      onPressed: frozen ? null : () => pickPassport(pet['id']),
                      child: Text(
                        lt(
                          'Pasport rasmini tanlash',
                          'Select passport photo',
                          'Выбрать фото паспорта',
                        ),
                      ),
                    ),
                    if (passports[pet['id']] != null)
                      TextButton(
                        onPressed: frozen
                            ? null
                            : () => setState(() => passports.remove(pet['id'])),
                        child: Text(
                          lt(
                            'Rasmni olib tashlash',
                            'Remove photo',
                            'Убрать фото',
                          ),
                        ),
                      ),
                  ],
                ),
            ],
            if (step == 3 && quote != null) ...[
              Text(
                lt(
                  'Yakuniy narx taklifi',
                  'Final price quote',
                  'Итоговый расчёт стоимости',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${bookingTime(quote['startsAt'])} — ${bookingTime(quote['endsAt'])}',
              ),
              Text(
                '${quote['pets'].length} ${lt('hayvon', 'pets', 'питомцев')} × ${quote['price']['billable_days']} ${lt('kun', 'days', 'дней')}',
              ),
              Text(
                bookingMoney(quote['price']['service_total_minor']),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                lt(
                  'Bu so‘rov. Enaga qabul qilmaguncha joy band bo‘lmaydi. Xizmat pulini enagaga bevosita to‘laysiz.',
                  'This is a request. Capacity is reserved only after the sitter accepts. You pay the sitter directly.',
                  'Это запрос. Место бронируется после принятия няней. Вы платите няне напрямую.',
                ),
              ),
              Text(
                '${lt('Taklif muddati', 'Quote expires', 'Расчёт действителен до')}: ${bookingTime(c.quote!['expiresAt'])}',
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('submitBookingStep'),
              onPressed: !c.ready || c.busy || picking ? null : next,
              child: Text(
                step == 3
                    ? (c.pending == null
                          ? lt(
                              'So‘rov yuborish',
                              'Send request',
                              'Отправить запрос',
                            )
                          : lt(
                              'O‘sha so‘rovni qayta tekshirish',
                              'Retry same request',
                              'Повторить тот же запрос',
                            ))
                    : lt('Davom etish', 'Continue', 'Продолжить'),
              ),
            ),
            if (step > 0 && c.pending == null)
              TextButton(
                onPressed: frozen ? null : () => setState(() => step--),
                child: Text(
                  lt('Oldingi bosqich', 'Previous step', 'Предыдущий шаг'),
                ),
              ),
            if (step == 3)
              TextButton(
                onPressed: c.busy ? null : clearAttempt,
                child: Text(
                  lt('Taklifni yangilash', 'Refresh quote', 'Обновить расчёт'),
                ),
              ),
          ],
        ),
      );
    },
  );
}
