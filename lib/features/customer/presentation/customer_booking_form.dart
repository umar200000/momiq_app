import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../../onboarding/data/profile_photo_source.dart';
import 'customer_passport_photo.dart';
import 'customer_availability.dart';
import '../../listings/data/listing_store.dart' show CareLocation;
import '../../listings/presentation/care_location_page.dart';
import 'package:flutter/material.dart';
import 'customer_widgets.dart';
import 'customer_account.dart';
import 'customer_bookings.dart';

class CustomerBookingForm extends StatefulWidget {
  const CustomerBookingForm({
    super.key,
    required this.store,
    required this.sitter,
    this.photoSource,
  });
  final CustomerStore store;
  final CJson sitter;
  final ProfilePhotoSource? photoSource;
  @override
  State<CustomerBookingForm> createState() => _CustomerBookingFormState();
}

class _CustomerBookingFormState extends State<CustomerBookingForm> {
  int _step = 0;
  final Set<String> _petIds = {};
  final Map<String, String> _passports = {};
  late final _photos = widget.photoSource ?? ProfilePhotoSource();
  bool _pickingPhoto = false;
  List<CJson> get pets => widget.store
      .list('pets')
      .where(
        (p) =>
            _petIds.contains(p['id']) &&
            allowedCustomerPetTypes(widget.sitter).contains(p['type']),
      )
      .toList();
  int get available => widget.store.availablePlaces(
    widget.sitter,
    from: _dates?.start,
    to: _dates?.end,
  );
  void _togglePet(String id) {
    if (_petIds.contains(id)) {
      setState(() {
        _petIds.remove(id);
      });
    } else if (pets.length >= available) {
      cNotice(
        context,
        available == 0
            ? (widget.sitter['service'] == 1
                  ? 'Enaga boshqa mijozda band.'
                  : 'Enagada bo‘sh joy yo‘q.')
            : 'Ko‘pi bilan $available ta hayvon tanlash mumkin.',
      );
    } else {
      setState(() {
        _petIds.add(id);
      });
    }
  }

  late DateTimeRange? _dates = widget.store.availablePlaces(widget.sitter) == 0
      ? DateTimeRange(
          start: widget.store.firstAvailableDate(widget.sitter),
          end: widget.store.firstAvailableDate(widget.sitter),
        )
      : null;
  CJson? _address;
  bool _saving = false;
  int get days => _dates == null ? 0 : careDays(_dates!.start, _dates!.end);
  Future<void> _pickPassport(String petId) async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: listingSurface,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('passport-camera'),
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(ct('Kamera')),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                key: const ValueKey('passport-gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(ct('Galereya')),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
      final bytes = await _photos.pickProfile(source: source);
      if (bytes != null && mounted) {
        setState(() => _passports[petId] = base64Encode(bytes));
      }
    } catch (_) {
      if (mounted) cNotice(context, 'Rasm olinmadi. Qayta urinib ko‘ring.');
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _datesPick() async {
    final now = calendarDate(DateTime.now());
    final v = await showDateRangePicker(
      context: context,
      firstDate: widget.store.firstAvailableDate(widget.sitter),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDateRange: _dates,
      helpText: ct('Parvarish sanalari'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: DatePickerThemeData(
            rangePickerHeaderHeadlineStyle: TextStyle(
              fontFamily: 'Quicksand',
              fontSize: MediaQuery.sizeOf(context).width <= 360 ? 16 : 20,
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (v != null && mounted) setState(() => _dates = v);
  }

  Future<void> _next() async {
    if (_saving) return;
    if (pets.length > available || available == 0) {
      cNotice(
        context,
        widget.sitter['service'] == 1
            ? 'Enaga band yoki 3 tadan ortiq hayvon tanlangan. Sanalar va hayvonlar sonini tekshiring.'
            : 'Bo‘sh joy: $available ta. Hayvonlar sonini yoki sanalarni o‘zgartiring.',
      );
      if (_step > 1) setState(() => _step = 1);
      return;
    }
    if (_step == 0 && pets.isEmpty) {
      cNotice(context, 'Hayvonni tanlang.');
      return;
    }
    if (_step == 1 &&
        (_dates == null ||
            (widget.sitter['service'] == 1 && _address == null))) {
      cNotice(context, 'Sanalar va manzilni tanlang.');
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await widget.store.book(
        sitterId: widget.sitter['id'],
        petIds: pets.map((p) => p['id'] as String).toList(),
        petPassports: {
          for (final p in pets)
            if (_passports.containsKey(p['id']))
              p['id'] as String: _passports[p['id']]!,
        },
        from: _dates!.start,
        to: _dates!.end,
        address:
            _address ??
            {
              'latitude': 41.2995,
              'longitude': 69.2726,
              'address': 'Toshkent, Oybek ko‘chasi, 12',
            },
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CustomerBookingSuccess(store: widget.store, id: id),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        cNotice(
          context,
          'So‘rov saqlanmadi. Sanalar va ma’lumotlarni tekshiring.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving) {
          setState(() {
            _step--;
          });
        }
      },
      child: CustomerPage(
        title: [
          'Hayvonni tanlang',
          'Parvarish sanalari',
          'Hayvon pasporti',
          'Buyurtmani tekshiring',
        ][_step],
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            cButton(
              _step == 3 ? 'So‘rov yuborish' : 'Davom etish',
              _saving || _pickingPhoto ? null : _next,
              id: 'bookingNext',
            ),
          ],
        ),
        children: [
          cText('${_step + 1} / 4', color: listingGold, bold: true),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_step + 1) / 4,
            color: listingGold,
            backgroundColor: listingBorder,
          ),
          const SizedBox(height: 20),
          if (_step == 0 || _step == 1 || _step == 3)
            CustomerAvailability(
              store: widget.store,
              sitter: widget.sitter,
              from: _dates?.start,
              to: _dates?.end,
              selected: pets.length,
            ),
          if (_step == 0) ...[
            if (_dates != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: cText(
                  'Buyurtma boshlanishi: ${shortDate(_dates!.start.toIso8601String())}',
                  bold: true,
                ),
              ),
            if (_dates != null)
              cButton('Sanalarni o‘zgartirish', _datesPick, secondary: true),
            cText(
              widget.sitter['service'] == 2
                  ? 'Faqat bitta hayvonni tanlang.'
                  : widget.sitter['service'] == 1
                  ? 'Uyingizga chaqirish uchun 3 tagacha hayvon tanlang. Narx har bir hayvon uchun hisoblanadi.'
                  : 'Bo‘sh joylar sonigacha hayvon tanlang. Narx har bir hayvon uchun hisoblanadi.',
              size: 13,
            ),
            const SizedBox(height: 12),
            if (!widget.store
                .list('pets')
                .any(
                  (p) => allowedCustomerPetTypes(
                    widget.sitter,
                  ).contains(p['type']),
                ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: cText(
                  lt(
                    'Hozircha hayvon yo‘q. Hayvon qo‘shing.',
                    'No pets yet. Add a pet.',
                    'Пока нет животных. Добавьте питомца.',
                  ),
                ),
              ),
            cCard(
              cRow(
                Icons.home_outlined,
                '${ct(customerServices[widget.sitter['service']])}\n${widget.sitter['name']}',
              ),
            ),
            for (final p
                in widget.store
                    .list('pets')
                    .where(
                      (p) => allowedCustomerPetTypes(
                        widget.sitter,
                      ).contains(p['type']),
                    ))
              cCard(
                Row(
                  children: [
                    CustomerPetArt(pet: p, size: 74),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cText(customerPetName(p), size: 20, bold: true),
                          cText(customerPetDescription(p), size: 13),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('editBookingPet-${p['id']}'),
                      tooltip: ct('Tahrirlash'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => cPush(
                        context,
                        CustomerPetForm(
                          store: widget.store,
                          pet: p,
                          allowedTypes: allowedCustomerPetTypes(widget.sitter),
                        ),
                      ),
                    ),
                    Icon(
                      _petIds.contains(p['id'])
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      color: listingGold,
                    ),
                  ],
                ),
                onTap: () => _togglePet(p['id']),
              ),
            cButton(
              'Hayvon qo‘shish',
              () async {
                final id = await cPush<String>(
                  context,
                  CustomerPetForm(
                    store: widget.store,
                    allowedTypes: allowedCustomerPetTypes(widget.sitter),
                  ),
                );
                if (mounted && id != null) _togglePet(id);
              },
              secondary: true,
              icon: Icons.add,
            ),
          ],
          if (_step == 1) ...[
            cCard(
              Column(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    size: 54,
                    color: listingGold,
                  ),
                  const SizedBox(height: 16),
                  cText(
                    _dates == null
                        ? 'Boshlanish va tugash kunini tanlang'
                        : '${shortDate(_dates!.start.toIso8601String())} — ${shortDate(_dates!.end.toIso8601String())}',
                    bold: true,
                  ),
                  cButton(
                    'Sanalarni tanlash',
                    _datesPick,
                    id: 'pickBookingDates',
                  ),
                  if (_dates != null) cText('Jami $days kun', bold: true),
                ],
              ),
            ),
            if (widget.sitter['service'] == 1)
              cCard(
                Column(
                  children: [
                    cRow(
                      Icons.location_on_outlined,
                      _address?['address'] ?? 'Mijozning uy manzili',
                    ),
                    cButton('Manzilni tanlang', () async {
                      final value = await pickCareLocation(
                        context,
                        _address == null
                            ? null
                            : CareLocation.fromJson(_address!),
                      );
                      if (value != null && mounted) {
                        setState(() => _address = value.toJson());
                      }
                    }, secondary: true),
                  ],
                ),
              ),
          ],
          if (_step == 2) ...[
            cText(
              'Pasport rasmi ixtiyoriy. Rasm qo‘shmasdan ham davom etishingiz mumkin.',
              size: 14,
            ),
            const SizedBox(height: 16),
            for (final p in pets)
              cCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CustomerPetArt(pet: p),
                        const SizedBox(width: 14),
                        Expanded(
                          child: cText(
                            customerPetName(p),
                            size: 20,
                            bold: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    cText('Hayvon pasporti (ixtiyoriy)', bold: true),
                    if (_passports[p['id']] != null) ...[
                      const SizedBox(height: 12),
                      CustomerPassportPhoto(photo: _passports[p['id']]!),
                    ],
                    cButton(
                      _passports[p['id']] == null
                          ? 'Pasport rasmini qo‘shish'
                          : 'Rasmni almashtirish',
                      _pickingPhoto ? null : () => _pickPassport(p['id']),
                      secondary: true,
                      icon: Icons.add_a_photo_outlined,
                      id: "passport-${p['id']}",
                    ),
                    if (_passports[p['id']] != null)
                      TextButton(
                        onPressed: _pickingPhoto
                            ? null
                            : () => setState(() => _passports.remove(p['id'])),
                        child: Text(ct('Rasmni olib tashlash')),
                      ),
                  ],
                ),
              ),
          ],
          if (_step == 3) ...[
            cCard(
              Row(
                children: [
                  SitterPortrait(index: widget.sitter['photo']),
                  const SizedBox(width: 12),
                  Expanded(
                    child: cText(widget.sitter['name'], size: 20, bold: true),
                  ),
                ],
              ),
            ),
            for (final selectedPet in pets)
              cCard(
                Row(
                  children: [
                    CustomerPetArt(pet: selectedPet),
                    const SizedBox(width: 12),
                    Expanded(
                      child: cText(
                        customerPetName(selectedPet),
                        size: 20,
                        bold: true,
                      ),
                    ),
                  ],
                ),
              ),
            cCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cRow(
                    Icons.home_outlined,
                    ct(customerServices[widget.sitter['service']]),
                  ),
                  cRow(
                    Icons.calendar_month_outlined,
                    '${shortDate(_dates!.start.toIso8601String())} — ${shortDate(_dates!.end.toIso8601String())}',
                  ),
                  cRow(
                    Icons.location_on_outlined,
                    _address?['address'] ?? 'Toshkent, Oybek ko‘chasi, 12',
                  ),
                  cRow(
                    Icons.videocam_outlined,
                    'Enaga har kuni 2 ta video yuborishi shart: ertalab 06:00–12:00 va kechqurun 18:00–00:00.',
                  ),
                  const Divider(),
                  cText(
                    '${priceText(widget.sitter['price'])} so‘m × ${pets.length} hayvon × $days kun',
                  ),
                  const SizedBox(height: 10),
                  cText(
                    'Jami ${priceText(widget.sitter['price'] * pets.length * days)} so‘m',
                    size: 23,
                    bold: true,
                  ),
                ],
              ),
            ),
            cText(
              'So‘rov enaga tasdiqlaganidan keyin qabul qilinadi.',
              size: 13,
            ),
            cText(
              lt(
                'Mock buyurtma. Haqiqiy to‘lov olinmaydi.',
                'Mock booking. No payment is collected.',
                'Демо-заказ. Оплата не взимается.',
              ),
              size: 12,
            ),
          ],
        ],
      ),
    ),
  );
}

class CustomerBookingSuccess extends StatelessWidget {
  const CustomerBookingSuccess({
    super.key,
    required this.store,
    required this.id,
  });
  final CustomerStore store;
  final String id;
  @override
  Widget build(BuildContext context) => CustomerPage(
    title: 'So‘rov yuborildi',
    children: [
      const SizedBox(height: 24),
      Image.asset('assets/images/service_cat.png', height: 160),
      const Icon(Icons.check_circle_outline, color: listingGold, size: 64),
      const SizedBox(height: 18),
      Center(child: cText('So‘rovingiz yuborildi', size: 24, bold: true)),
      const SizedBox(height: 10),
      Center(child: cText('Enaga javobini kuting.')),
      const SizedBox(height: 24),
      cCard(cRow(Icons.schedule, 'Kutilmoqda · $id')),
      cButton(
        'Buyurtmani ko‘rish',
        () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CustomerBookingDetail(store: store, id: id),
          ),
        ),
      ),
      cButton(
        'Bosh sahifaga',
        () => Navigator.of(context).popUntil((route) => route.isFirst),
        secondary: true,
      ),
    ],
  );
}
