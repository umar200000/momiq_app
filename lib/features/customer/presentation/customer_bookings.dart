import 'customer_passport_photo.dart';
import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'customer_widgets.dart';
import 'customer_account.dart';

String bookingStatus(String status) => ct(switch (status) {
  'active' => 'Parvarishda',
  'completed' => 'Tugatilgan',
  'cancelled' => 'Bekor qilingan',
  _ => 'Kutilmoqda',
});

class CustomerOrders extends StatefulWidget {
  const CustomerOrders({super.key, required this.store});
  final CustomerStore store;
  @override
  State<CustomerOrders> createState() => _CustomerOrdersState();
}

class _CustomerOrdersState extends State<CustomerOrders> {
  int _tab = 0;
  bool matches(CJson b, int tab) => tab == 0
      ? b['status'] == 'active'
      : tab == 1
      ? b['status'] == 'pending'
      : ['completed', 'cancelled'].contains(b['status']);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final all = widget.store.list('bookings');
      final selected = all.where((b) => matches(b, _tab));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      key: ValueKey('customerOrderTab-$i'),
                      label: Text(
                        '${ct(['Faol', 'Kutilmoqda', 'Tarix'][i])} ${all.where((b) => matches(b, i)).length}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (selected.isEmpty) cCard(cText('Hozircha bo‘sh')),
          for (final b in selected)
            cCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CustomerPetArt(
                        pet: Map<String, dynamic>.from(b['pet']),
                        size: 76,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cText(bookingPetNames(b), size: 23, bold: true),
                            cText(
                              bookingStatus(b['status']),
                              color: listingGold,
                              size: 13,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  cRow(
                    Icons.person_outline,
                    customerSitter(b['sitter'])['name'],
                  ),
                  cRow(
                    Icons.calendar_today_outlined,
                    '${shortDate(b['from'])} — ${shortDate(b['to'])}',
                  ),
                  cText(
                    '${priceText(bookingTotal(b))} so‘m',
                    size: 19,
                    bold: true,
                  ),
                  if (b['status'] == 'active')
                    cButton(
                      'Bugungi parvarish',
                      () => cPush(context, CustomerCareReport(booking: b)),
                    ),
                ],
              ),
              onTap: () => cPush(
                context,
                CustomerBookingDetail(store: widget.store, id: b['id']),
              ),
            ),
        ],
      );
    },
  );
}

class CustomerBookingDetail extends StatelessWidget {
  const CustomerBookingDetail({
    super.key,
    required this.store,
    required this.id,
  });
  final CustomerStore store;
  final String id;
  Future<void> _cancel(BuildContext context) async {
    final reason = await cPush<String>(context, const CustomerCancelPage());
    if (reason != null && context.mounted) {
      await cAction(context, () => store.cancel(id, reason));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final b = store.list('bookings').firstWhere((b) => b['id'] == id);
      final sitter = customerSitter(b['sitter']);
      return CustomerPage(
        title: 'Buyurtma tafsilotlari',
        children: [
          cText(id, size: 12),
          const SizedBox(height: 8),
          cCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cText(
                  bookingStatus(b['status']),
                  bold: true,
                  color: listingGold,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CustomerPetArt(
                      pet: Map<String, dynamic>.from(b['pet']),
                      size: 78,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cText(bookingPetNames(b), size: 22, bold: true),
                          cText(sitter['name'], size: 13),
                        ],
                      ),
                    ),
                  ],
                ),
                cRow(Icons.home_outlined, ct(customerServices[b['service']])),
                cRow(
                  Icons.calendar_month_outlined,
                  '${shortDate(b['from'])} — ${shortDate(b['to'])}',
                ),
                cRow(Icons.location_on_outlined, b['address']['address']),
              ],
            ),
          ),
          if (['active', 'completed'].contains(b['status']))
            cCard(
              cRow(Icons.checklist_outlined, 'Bugungi parvarish'),
              onTap: () => cPush(context, CustomerCareReport(booking: b)),
            ),
          cButton(
            'Enaga bilan yozishish',
            () =>
                cPush(context, CustomerChatPage(store: store, sitter: sitter)),
            icon: Icons.chat_bubble_outline,
          ),
          for (final pet in bookingPets(b))
            if (b['petPassports']?[pet['id']] != null)
              cCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cText(
                      '${customerPetName(pet)} · Hayvon pasporti',
                      bold: true,
                    ),
                    const SizedBox(height: 12),
                    CustomerPassportPhoto(photo: b['petPassports'][pet['id']]),
                  ],
                ),
              ),
          cCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cText(
                  '${priceText(b['price'])} so‘m × ${bookingPets(b).length} hayvon / kun',
                ),
                const SizedBox(height: 8),
                cText(
                  'Jami ${priceText(bookingTotal(b))} so‘m',
                  size: 23,
                  bold: true,
                ),
              ],
            ),
          ),
          if (b['status'] == 'completed')
            cButton(
              b['review'] == null ? 'Baho va fikr' : 'Fikrni tahrirlash',
              () =>
                  cPush(context, CustomerReviewPage(store: store, booking: b)),
            ),
          if (['pending', 'active'].contains(b['status']))
            cButton(
              'Bekor qilish',
              store.busy ? null : () => _cancel(context),
              secondary: true,
            ),
          if (b['status'] == 'cancelled')
            cCard(cText(b['cancelReason'] ?? 'Bekor qilingan')),
          cButton(
            'Yordam',
            () => cPush(context, CustomerHelpPage(store: store)),
            secondary: true,
          ),
        ],
      );
    },
  );
}

class CustomerCancelPage extends StatefulWidget {
  const CustomerCancelPage({super.key});
  @override
  State<CustomerCancelPage> createState() => _CustomerCancelPageState();
}

class _CustomerCancelPageState extends State<CustomerCancelPage> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomerPage(
    title: 'Bekor qilish',
    bottom: cButton('Bekor qilish', () {
      if (_reason.text.trim().isEmpty) {
        cNotice(context, 'Sababni yozing.');
        return;
      }
      Navigator.pop(context, _reason.text.trim());
    }, id: 'confirmCustomerCancel'),
    children: [
      cCard(
        cText(
          'Buyurtmani bekor qilishni tasdiqlaysizmi?',
          size: 20,
          bold: true,
        ),
      ),
      cField(_reason, 'Sababni yozing', lines: 4, id: 'cancelReason'),
    ],
  );
}

class CustomerReviewPage extends StatefulWidget {
  const CustomerReviewPage({
    super.key,
    required this.store,
    required this.booking,
  });
  final CustomerStore store;
  final CJson booking;
  @override
  State<CustomerReviewPage> createState() => _CustomerReviewPageState();
}

class _CustomerReviewPageState extends State<CustomerReviewPage> {
  late int _stars = widget.booking['review']?['stars'] ?? 5;
  late final _text = TextEditingController(
    text: widget.booking['review']?['text'] ?? '',
  );
  bool _saving = false;
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.store.update((d) {
        final b = (d['bookings'] as List).firstWhere(
          (v) => v['id'] == widget.booking['id'],
        );
        if (b['status'] != 'completed') throw StateError('Not completed');
        b['review'] = {
          'stars': _stars,
          'text': _text.text.trim(),
          'date': DateTime.now().toIso8601String(),
        };
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) cNotice(context, 'Fikr saqlanmadi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomerPage(
    title: 'Baho va fikr',
    bottom: cButton('Fikrni yuborish', _saving ? null : _save),
    children: [
      cCard(
        cRow(
          Icons.person_outline,
          customerSitter(widget.booking['sitter'])['name'],
        ),
      ),
      cText('Parvarish qanday o‘tdi?', size: 23, bold: true),
      const SizedBox(height: 20),
      Row(
        children: [
          for (var i = 1; i <= 5; i++)
            Expanded(
              child: IconButton(
                tooltip: '$i',
                onPressed: () => setState(() => _stars = i),
                icon: Icon(
                  i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: listingGold,
                  size: 36,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      cField(_text, 'Fikringiz (ixtiyoriy)', lines: 5),
    ],
  );
}

class CustomerCareReport extends StatefulWidget {
  const CustomerCareReport({super.key, required this.booking});
  final CJson booking;
  @override
  State<CustomerCareReport> createState() => _CustomerCareReportState();
}

class _CustomerCareReportState extends State<CustomerCareReport> {
  late DateTime _date;
  int _petIndex = 0;
  DateTime get first => calendarDate(DateTime.parse(widget.booking['from']));
  DateTime get last => calendarDate(DateTime.parse(widget.booking['to']));
  @override
  void initState() {
    super.initState();
    final now = calendarDate(DateTime.now());
    _date = now.isBefore(first)
        ? first
        : now.isAfter(last)
        ? last
        : now;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final pets = bookingPets(b);
    final selectedPet = pets[_petIndex];
    final ins = bookingPetCare(b, selectedPet);
    final meals = List<String>.from(ins['meals'] ?? const <String>[]);
    final rows = <(IconData, String, String, bool)>[
      for (var i = 0; i < meals.length; i++)
        (Icons.restaurant_outlined, '${i + 1}-ovqat', meals[i], false),
      if (ins['medicine'] == true)
        (Icons.medication_outlined, 'Dori berish', ins['medicineTime'], false),
      if (ins['walk'] == true)
        (Icons.pets_outlined, 'Sayr', ins['walkTime'], false),
    ];
    final complete = rows.where((r) => r.$4).length;
    return CustomerPage(
      title: 'Bugungi parvarish',
      children: [
        if (pets.length > 1)
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < pets.length; i++)
                ChoiceChip(
                  label: Text(customerPetName(pets[i])),
                  selected: _petIndex == i,
                  onSelected: (_) => setState(() => _petIndex = i),
                ),
            ],
          ),
        Row(
          children: [
            IconButton(
              onPressed: _date.isAfter(first)
                  ? () => setState(
                      () => _date = _date.subtract(const Duration(days: 1)),
                    )
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: cText(shortDate(_date.toIso8601String()), bold: true),
              ),
            ),
            IconButton(
              onPressed: _date.isBefore(last)
                  ? () => setState(
                      () => _date = _date.add(const Duration(days: 1)),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        cCard(
          Row(
            children: [
              CustomerPetArt(pet: selectedPet),
              const SizedBox(width: 16),
              cText(customerPetName(selectedPet), bold: true, size: 22),
            ],
          ),
        ),
        cCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cText('$complete / ${rows.length + 2} bajarildi', bold: true),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: complete / (rows.length + 2),
                color: listingGold,
                backgroundColor: listingBorder,
              ),
            ],
          ),
        ),
        for (final r in rows)
          cCard(
            Row(
              children: [
                Icon(
                  r.$4 ? Icons.check_circle_outline : Icons.schedule_outlined,
                  color: r.$4 ? const Color(0xFF567547) : listingGold,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cText(r.$2, bold: true),
                      cText(r.$4 ? 'Bajarildi' : 'Kutilmoqda', size: 12),
                    ],
                  ),
                ),
                cText(r.$3, size: 13),
              ],
            ),
          ),
        cText('Video hisobotlar', bold: true, size: 22),
        const SizedBox(height: 14),
        for (final morning in [true, false])
          cCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cRow(
                  morning ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
                  morning ? 'Ertalabki video' : 'Kechki video',
                ),
                cText(morning ? '06:00–12:00' : '18:00–00:00', size: 13),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: listingBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.videocam_outlined,
                        size: 38,
                        color: listingGold,
                      ),
                      const SizedBox(height: 8),
                      cText('Hali yuborilmagan', size: 13),
                    ],
                  ),
                ),
              ],
            ),
          ),
        cText('Hisobotlar xizmati hali ulanmagan.', size: 12),
      ],
    );
  }
}

class CustomerChatList extends StatefulWidget {
  const CustomerChatList({super.key, required this.store});
  final CustomerStore store;
  @override
  State<CustomerChatList> createState() => _CustomerChatListState();
}

class _CustomerChatListState extends State<CustomerChatList> {
  String _query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final all = widget.store.list('messages');
      final ids = {
        'hoji',
        'nilufar',
        ...all.map((m) => m['sitter'] as String),
      }.toList();
      DateTime lastTime(String id) =>
          all.where((m) => m['sitter'] == id).isEmpty
          ? DateTime(2000)
          : DateTime.parse(all.lastWhere((m) => m['sitter'] == id)['time']);
      ids.sort((a, b) => lastTime(b).compareTo(lastTime(a)));
      final visible = ids
          .where(
            (id) => '${customerSitter(id)['name']}'.toLowerCase().contains(
              _query.toLowerCase(),
            ),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cText('Enagalar bilan suhbatlaringiz', size: 14),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('customerChatSearch'),
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              hintText: ct('Suhbatlarni qidirish'),
              prefixIcon: const Icon(Icons.search_rounded, color: listingGold),
              filled: true,
              fillColor: listingSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 22),
          cText('Suhbatlar · ${visible.length}', bold: true, size: 17),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            cCard(
              Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 42,
                    color: listingGold,
                  ),
                  const SizedBox(height: 12),
                  cText('Suhbat topilmadi', bold: true),
                  cText('Enaganing ismi bilan qidirib ko‘ring.', size: 13),
                ],
              ),
            ),
          for (final id in visible)
            Builder(
              builder: (context) {
                final sitter = customerSitter(id);
                final messages = all.where((m) => m['sitter'] == id).toList();
                final last = messages.isEmpty ? null : messages.last;
                return cCard(
                  Row(
                    children: [
                      ClipOval(
                        child: SitterPortrait(index: sitter['photo'], size: 54),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sitter['name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4B2C1C),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              last == null
                                  ? ct('Suhbatni boshlash')
                                  : '${last['mine'] == true ? 'Siz: ' : ''}${last['image'] != null ? 'Rasm' : last['text']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF8C7965),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 7),
                            cText(
                              customerServices[sitter['service']],
                              size: 11,
                              color: listingGold,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          if (last != null)
                            cText(_chatTime(last['time']), size: 10),
                          const SizedBox(height: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: listingGold,
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => cPush(
                    context,
                    CustomerChatPage(store: widget.store, sitter: sitter),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

String _chatTime(String value) {
  final time = DateTime.parse(value).toLocal();
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class CustomerChatPage extends StatefulWidget {
  const CustomerChatPage({
    super.key,
    required this.store,
    required this.sitter,
  });
  final CustomerStore store;
  final CJson sitter;
  @override
  State<CustomerChatPage> createState() => _CustomerChatPageState();
}

class _CustomerChatPageState extends State<CustomerChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    final message = _text.text;
    setState(() => _sending = true);
    try {
      await widget.store.send(widget.sitter['id'], message);
      if (mounted) {
        _text.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) cNotice(context, 'Xabar saqlanmadi.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        imageQuality: 75,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await widget.store.saveItem('messages', {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'sitter': widget.sitter['id'],
        'mine': true,
        'text': '',
        'image': base64Encode(bytes),
        'time': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      if (mounted) cNotice(context, 'Rasm yuborilmadi.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => MomiqScaffold(
      backgroundColor: listingBackground,
      appBar: AppBar(
        backgroundColor: listingBackground,
        title: Row(
          children: [
            SitterPortrait(index: widget.sitter['photo'], size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cText(widget.sitter['name'], bold: true, size: 16),
                  cText(
                    customerServices[widget.sitter['service']],
                    size: 11,
                    color: listingGold,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.store.syncError != null)
              MaterialBanner(
                content: Text(widget.store.syncError!),
                actions: [
                  TextButton(
                    onPressed: widget.store.refreshRemote,
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: cText(
                widget.store.remote
                    ? 'Enaga bilan suhbat'
                    : 'Suhbat · xabarlar hozircha qurilmada saqlanadi',
                size: 11,
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (!widget.store
                      .list('messages')
                      .any((m) => m['sitter'] == widget.sitter['id']))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: cCard(
                        Column(
                          children: [
                            Image.asset(
                              'assets/images/service_cat.png',
                              height: 100,
                            ),
                            const SizedBox(height: 16),
                            cText('Suhbatni boshlang', size: 22, bold: true),
                            const SizedBox(height: 8),
                            cText(
                              'Hayvoningiz va parvarish tafsilotlarini enaga bilan kelishib oling.',
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final m
                      in widget.store
                          .list('messages')
                          .where((m) => m['sitter'] == widget.sitter['id']))
                    Align(
                      alignment: m['mine'] == true
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .78,
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: m['mine'] == true
                              ? const Color(0xFFF1D28E)
                              : listingSurface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(
                              m['mine'] == true ? 20 : 5,
                            ),
                            bottomRight: Radius.circular(
                              m['mine'] == true ? 5 : 20,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m['image'] != null)
                              GestureDetector(
                                onTap: () => showDialog<void>(
                                  context: context,
                                  builder: (context) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.memory(
                                        base64Decode(m['image']),
                                      ),
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    base64Decode(m['image']),
                                    width: 220,
                                  ),
                                ),
                              ),
                            if (m['text'] != '') cText(m['text']),
                            const SizedBox(height: 5),
                            cText(_chatTime(m['time']), size: 10),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: listingSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: listingBorder),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : _attach,
                    tooltip: 'Rasm yuborish',
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: listingGold,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('customerChatInput'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Xabar yozing...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: listingGold),
                    icon: const Icon(Icons.send_outlined),
                    key: const ValueKey('customerChatSend'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
