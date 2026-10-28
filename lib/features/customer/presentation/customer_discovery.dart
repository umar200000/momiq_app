import '../../bookings/presentation/booking_request_page.dart';
import '../../chat/presentation/conversation_page.dart';
import 'package:momiq_app/core/widgets/button_progress.dart';
import 'customer_availability.dart';
import 'customer_reviews.dart';
import 'customer_home_design.dart';
import 'package:flutter/material.dart';
import '../../listings/data/listing_store.dart' show CareLocation;
import '../../listings/presentation/care_location_preview.dart';
import 'customer_widgets.dart';
import '../../listings/presentation/external_map_picker.dart';

class SitterCard extends StatelessWidget {
  const SitterCard({super.key, required this.store, required this.sitter});
  final CustomerStore store;
  final CJson sitter;
  @override
  Widget build(BuildContext context) => cCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipOval(child: SitterPortrait(index: sitter['photo'], size: 48)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cText(sitter['name'], bold: true, size: 17),
                  const SizedBox(height: 6),
                  cRating(customerReviewSummary(store, sitter)),
                  cText(
                    sitter['distance'] is num
                        ? '${(sitter['distance'] as num).toStringAsFixed(1)} km'
                        : 'Masofa aniqlanmagan',
                    size: 12,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Saqlash',
              onPressed: store.busy
                  ? null
                  : () => cAction(context, () => store.favorite(sitter['id'])),
              icon: ButtonProgress(
                loading: store.busy,
                child: Icon(
                  store.favorites.contains(sitter['id'])
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: listingGold,
                ),
              ),
            ),
          ],
        ),
        CustomerHomePhotos(sitter: sitter),
        const SizedBox(height: 12),
        cRow(Icons.home_outlined, ct(customerServices[sitter['service']])),
        cRow(
          Icons.pets_outlined,
          (sitter['pets'] as List).map((v) => ct(v as String)).join(' · '),
        ),
        CustomerAvailability(store: store, sitter: sitter),
        if (sitter['testOnly'] == true)
          cText('Test e’lon · MyID tekshiruvi yo‘q', size: 12),
        cText(
          '${priceText(sitter['price'])} so‘m / hayvon / kun',
          size: 18,
          bold: true,
        ),
      ],
    ),
    onTap: () => cPush(context, SitterDetailPage(store: store, sitter: sitter)),
  );
}

class CustomerSearchPage extends StatefulWidget {
  const CustomerSearchPage({
    super.key,
    required this.store,
    this.service,
    this.favoritesOnly = false,
  });
  final CustomerStore store;
  final int? service;
  final bool favoritesOnly;
  @override
  State<CustomerSearchPage> createState() => _CustomerSearchPageState();
}

class _CustomerSearchPageState extends State<CustomerSearchPage> {
  final _search = TextEditingController();
  late int? _service = widget.service;
  CJson _filter = {
    'pet': '',
    'min': 0,
    'max': 500000,
    'distance': 50.0,
    'rating': false,
  };
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _filters() async {
    final next = await cPush<CJson>(
      context,
      CustomerFilterPage(initial: _filter),
    );
    if (next != null && mounted) setState(() => _filter = next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final results = widget.store.sitters
          .where(
            (s) =>
                (!widget.favoritesOnly ||
                    widget.store.favorites.contains(s['id'])) &&
                (_service == null || s['service'] == _service) &&
                s['name'].toString().toLowerCase().contains(
                  _search.text.toLowerCase(),
                ) &&
                (_filter['pet'] == '' ||
                    (s['pets'] as List).contains(_filter['pet'])) &&
                s['price'] >= _filter['min'] &&
                s['price'] <= _filter['max'] &&
                (s['distance'] is! num ||
                    s['distance'] <= _filter['distance']) &&
                (_filter['rating'] != true || s['rating'] >= 4.8),
          )
          .toList();
      return CustomerPage(
        title: widget.favoritesOnly ? 'Saqlangan enagalar' : 'Enagalar',
        actions: [
          IconButton(
            onPressed: _filters,
            icon: const Icon(Icons.tune_rounded),
            tooltip: ct('Filtrlar'),
          ),
        ],
        children: [
          TextField(
            key: const ValueKey('customerSearch'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: ct('Enaga qidirish'),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: listingSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(lt('Barchasi', 'All', 'Все')),
                selected: _service == null,
                onSelected: (_) => setState(() => _service = null),
              ),
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  label: Text(ct(customerServices[i])),
                  selected: _service == i,
                  onSelected: (_) => setState(() => _service = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (results.isEmpty) cCard(cText('Hech narsa topilmadi')),
          for (final sitter in results)
            SitterCard(store: widget.store, sitter: sitter),
        ],
      );
    },
  );
}

class CustomerFilterPage extends StatefulWidget {
  const CustomerFilterPage({super.key, required this.initial});
  final CJson initial;
  @override
  State<CustomerFilterPage> createState() => _CustomerFilterPageState();
}

class _CustomerFilterPageState extends State<CustomerFilterPage> {
  late final _min = TextEditingController(text: '${widget.initial['min']}');
  late final _max = TextEditingController(text: '${widget.initial['max']}');
  late String _pet = widget.initial['pet'];
  late double _distance = (widget.initial['distance'] as num).toDouble();
  late bool _rating = widget.initial['rating'];
  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    final min = int.tryParse(_min.text), max = int.tryParse(_max.text);
    if (min == null || max == null || min < 0 || max < min) {
      cNotice(context, 'Narx oralig‘ini to‘g‘ri kiriting.');
      return;
    }
    Navigator.pop(context, {
      'pet': _pet,
      'min': min,
      'max': max,
      'distance': _distance,
      'rating': _rating,
    });
  }

  @override
  Widget build(BuildContext context) => CustomerPage(
    title: 'Filtrlar',
    bottom: cButton('Natijalarni ko‘rsatish', _apply),
    children: [
      cText('Hayvon turi', bold: true),
      Wrap(
        spacing: 10,
        children: [
          for (final p in ['', 'It', 'Mushuk', 'Boshqa'])
            ChoiceChip(
              label: Text(p.isEmpty ? lt('Barchasi', 'All', 'Все') : ct(p)),
              selected: _pet == p,
              onSelected: (_) => setState(() => _pet = p),
            ),
        ],
      ),
      const SizedBox(height: 24),
      cField(_min, 'Minimal narx (so‘m)', number: true),
      cField(_max, 'Maksimal narx (so‘m)', number: true),
      cText('Masofa: ${_distance.round()} km', bold: true),
      cText(
        'Masofa aniqlanmagan e’lonlar bu filtr bilan yashirilmaydi.',
        size: 12,
      ),
      Slider(
        value: _distance,
        min: 1,
        max: 50,
        divisions: 49,
        activeColor: listingGold,
        onChanged: (v) => setState(() => _distance = v),
      ),
      cCard(
        SwitchListTile(
          title: cText('Reyting 4.8 va yuqori'),
          value: _rating,
          onChanged: (v) => setState(() => _rating = v),
        ),
      ),
      cButton(
        'Tozalash',
        () => setState(() {
          _pet = '';
          _min.text = '0';
          _max.text = '500000';
          _distance = 50;
          _rating = false;
        }),
        secondary: true,
      ),
    ],
  );
}

class SitterDetailPage extends StatelessWidget {
  const SitterDetailPage({
    super.key,
    required this.store,
    required this.sitter,
  });
  final CustomerStore store;
  final CJson sitter;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => CustomerPage(
      title: 'Enaga profili',
      actions: [
        IconButton(
          onPressed: store.busy
              ? null
              : () => cAction(context, () => store.favorite(sitter['id'])),
          icon: ButtonProgress(
            loading: store.busy,
            child: Icon(
              store.favorites.contains(sitter['id'])
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: listingGold,
            ),
          ),
        ),
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          cText(
            '${priceText(sitter['price'])} so‘m / hayvon / kun',
            bold: true,
            size: 18,
          ),
          cButton(
            sitter['bookingEnabled'] == true && store.api != null
                ? 'So‘rov yuborish'
                : 'Buyurtma berish hali ochilmagan',
            sitter['bookingEnabled'] == true && store.api != null
                ? () => cPush(
                    context,
                    BookingRequestPage(store: store, sitter: sitter),
                  )
                : null,
            id: 'bookSitter',
          ),
          TextButton.icon(
            key: const ValueKey('contactSitter'),
            onPressed: () =>
                openConversation(context, sitter['id'], api: store.api),
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(
              lt('Enaga bilan yozishish', 'Message sitter', 'Написать няне'),
            ),
          ),
        ],
      ),
      children: [
        cCard(
          Row(
            children: [
              SitterPortrait(index: sitter['photo'], size: 95),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cText(sitter['name'], size: 20, bold: true),
                    cRating(customerReviewSummary(store, sitter)),
                    cText('${sitter['years']} yillik tajriba', size: 13),
                    if (sitter['testOnly'] == true)
                      cText('Test e’lon · MyID tekshiruvi yo‘q', size: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        cCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cText('Men haqimda', bold: true, size: 19),
              const SizedBox(height: 8),
              cText(sitter['about'] ?? 'Ma’lumot kiritilmagan'),
              cRow(
                Icons.home_outlined,
                ct(customerServices[sitter['service']]),
              ),
              cRow(Icons.pets_outlined, (sitter['pets'] as List).join(' · ')),
              CustomerAvailability(store: store, sitter: sitter),
            ],
          ),
        ),
        if (sitter['service'] != 1) ...[
          CustomerHomePhotos(sitter: sitter),
          const SizedBox(height: 16),
          if (sitter['location'] is Map)
            CareLocationPreview(
              location: CareLocation.fromJson(CJson.from(sitter['location'])),
              onTap: () => showExternalMapPicker(
                context,
                CareLocation.fromJson(CJson.from(sitter['location'])),
              ),
            ),
          const SizedBox(height: 16),
        ],
        CustomerReviewsSection(store: store, sitter: sitter),
      ],
    ),
  );
}
