import '../../bookings/presentation/booking_request_page.dart';
import 'dart:async';
import '../../chat/presentation/conversation_page.dart';
import 'package:momiq_app/core/widgets/button_progress.dart';
import 'customer_availability.dart';
import 'customer_reviews.dart';
import '../../support/support_page.dart';
import 'customer_home_design.dart';
import 'package:flutter/material.dart';
import '../../listings/data/listing_store.dart' show CareLocation;
import '../../listings/presentation/care_location_preview.dart';
import 'customer_widgets.dart';
import '../../listings/presentation/external_map_picker.dart';

class SitterCard extends StatelessWidget {
  const SitterCard({
    super.key,
    required this.store,
    required this.sitter,
    this.onReturn,
  });
  final CustomerStore store;
  final CJson sitter;
  final VoidCallback? onReturn;
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
                        ? '≈ ${(sitter['distance'] as num).toStringAsFixed(1)} km'
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
    onTap: () async {
      await cPush(context, SitterDetailPage(store: store, sitter: sitter));
      if (context.mounted) onReturn?.call();
    },
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

class _CustomerSearchPageState extends State<CustomerSearchPage>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  late int? _service = widget.service;
  DateTime? _startsAt, _endsAt;
  Timer? _searchTimer;
  CJson _filter = {
    'pet': '',
    'min': 0,
    'max': null,
    'distance': null,
    'rating': false,
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      await widget.store.refreshSitters(
        location: widget.store.feedLocation,
        startsAt: _startsAt,
        endsAt: _endsAt,
        filters: {
          if (_service != null)
            'service': ['boarding', 'homeVisit', 'personal'][_service!],
          if (_filter['pet'] != '')
            'pet': _filter['pet'] == 'It' ? 'dog' : 'cat',
          'minPrice': '${_filter['min']}',
          if (_filter['max'] != null) 'maxPrice': '${_filter['max']}',
          'animals': '${_filter['animals'] ?? 1}',
          if (_filter['verified'] == true) 'verified': '1',
          if (_filter['rating'] == true) 'minRating': '4.8',
          if (_filter['distance'] != null && widget.store.feedLocation != null)
            'maxDistance': '${_filter['distance']}',
          if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
          if (widget.favoritesOnly) 'favorites': '1',
        },
      );
    } catch (_) {
      // Store owns the retryable error state; no unhandled async failure.
    }
  }

  void _clear() {
    _searchTimer?.cancel();
    setState(() {
      _startsAt = _endsAt = null;
      _search.clear();
      _service = null;
      _filter = {
        'pet': '',
        'min': 0,
        'max': null,
        'distance': null,
        'rating': false,
      };
    });
    _refresh();
  }

  Future<void> _dates() async {
    if (widget.store.feedLoading) return;
    final result = await cPush<List<DateTime>>(
      context,
      const DiscoveryDatesPage(),
    );
    if (!mounted || result == null) return;
    setState(() {
      _startsAt = result[0];
      _endsAt = result[1];
    });
    await _refresh();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  Future<void> _filters() async {
    final next = await cPush<CJson>(
      context,
      CustomerFilterPage(
        initial: _filter,
        hasLocation: widget.store.feedLocation != null,
      ),
    );
    if (next != null && mounted) {
      setState(() => _filter = next);
      _refresh();
    }
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
                (_filter['max'] == null || s['price'] <= _filter['max']) &&
                (_filter['distance'] == null ||
                    s['distance'] is! num ||
                    s['distance'] <= _filter['distance']) &&
                (_filter['rating'] != true || s['rating'] >= 4.8),
          )
          .toList();
      return CustomerPage(
        title: widget.favoritesOnly ? 'Saqlangan enagalar' : 'Enagalar',
        actions: [
          IconButton(
            key: const ValueKey('refreshSearch'),
            onPressed: widget.store.feedLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
          ),
          IconButton(
            onPressed: _filters,
            icon: const Icon(Icons.tune_rounded),
            tooltip: ct('Filtrlar'),
          ),
        ],
        children: [
          cText('Hudud: Toshkent', bold: true),
          cText(
            widget.store.feedLocation == null
                ? 'Joylashuvsiz Toshkent bo‘yicha qidiruv. Masofa hisoblanmaydi.'
                : 'Yaqin enagalar avval. Masofa taxminiy, to‘g‘ri chiziq bo‘yicha; yo‘l uzunligi emas.',
            size: 12,
          ),
          if (widget.store.feedLocation != null)
            TextButton(
              key: const ValueKey('searchWithoutLocation'),
              onPressed: () {
                widget.store.feedLocation = null;
                setState(() => _filter['distance'] = null);
                _refresh();
              },
              child: const Text('Joylashuvsiz Toshkent bo‘yicha qidirish'),
            ),
          TextField(
            key: const ValueKey('customerSearch'),
            controller: _search,
            maxLength: 100,
            onChanged: (_) {
              setState(() {});
              _searchTimer?.cancel();
              _searchTimer = Timer(const Duration(milliseconds: 300), () {
                if (mounted) _refresh();
              });
            },
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
                onSelected: (_) {
                  setState(() => _service = null);
                  _refresh();
                },
              ),
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  label: Text(ct(customerServices[i])),
                  selected: _service == i,
                  onSelected: (_) {
                    setState(() => _service = i);
                    _refresh();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('searchDates'),
            onPressed: widget.store.feedLoading ? null : _dates,
            icon: const Icon(Icons.date_range),
            label: Text(
              _startsAt == null
                  ? 'Kelish va ketish sanasini tanlash'
                  : '${discoveryTime(_startsAt!)} — ${discoveryTime(_endsAt!)}',
            ),
          ),
          if (_startsAt != null)
            cText(
              'Jadval bo‘yicha mos enagalar. Bo‘sh joy va qabul bron vaqtida qayta tekshiriladi. Toshkent vaqti.',
              size: 12,
            ),
          TextButton(
            key: const ValueKey('clearSearchFilters'),
            onPressed: widget.store.feedLoading ? null : _clear,
            child: Text(
              lt(
                'Qidiruv va filtrlarni tozalash',
                'Clear search and filters',
                'Сбросить поиск и фильтры',
              ),
            ),
          ),
          if (widget.store.feedLoading)
            const Center(child: CircularProgressIndicator())
          else if (widget.store.feedError != null)
            cCard(
              Column(
                children: [
                  cText(
                    lt(
                      'Enagalar yuklanmadi. Qayta urinib ko‘ring.',
                      'Could not load sitters. Please retry.',
                      'Не удалось загрузить ситтеров. Повторите.',
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('retrySearch'),
                    onPressed: _refresh,
                    child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
                  ),
                ],
              ),
            )
          else ...[
            if (results.isEmpty)
              cCard(
                cText(
                  widget.favoritesOnly
                      ? lt(
                          'Hozir mos va xizmatga tayyor saqlangan enaga yo‘q.',
                          'No saved sitter is currently eligible and matches your filters.',
                          'Сейчас нет доступных сохранённых ситтеров по вашим фильтрам.',
                        )
                      : 'Hech narsa topilmadi',
                ),
              ),
            for (final sitter in results)
              SitterCard(
                store: widget.store,
                sitter: sitter,
                onReturn: _refresh,
              ),
            CatalogMoreButton(store: widget.store),
          ],
        ],
      );
    },
  );
}

class CatalogMoreButton extends StatelessWidget {
  const CatalogMoreButton({super.key, required this.store});
  final CustomerStore store;
  @override
  Widget build(BuildContext context) {
    if (store.feedNextCursor == null ||
        store.feedLoading ||
        store.feedError != null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (store.feedMoreError != null)
          cText('Keyingi sahifa yuklanmadi. Qayta urinib ko‘ring.', size: 13),
        TextButton(
          key: const ValueKey('moreSitters'),
          onPressed: store.feedLoadingMore ? null : store.loadMoreSitters,
          child: store.feedLoadingMore
              ? const CircularProgressIndicator()
              : const Text('Yana enagalarni ko‘rsatish'),
        ),
      ],
    );
  }
}

String discoveryTime(DateTime value) {
  final local = value.toUtc().add(const Duration(hours: 5));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
}

class DiscoveryDatesPage extends StatefulWidget {
  const DiscoveryDatesPage({super.key});
  @override
  State<DiscoveryDatesPage> createState() => _DiscoveryDatesPageState();
}

class _DiscoveryDatesPageState extends State<DiscoveryDatesPage> {
  DateTime? start, end;
  Future<void> pick(bool first) async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final old =
        (first ? start : end)?.toUtc().add(const Duration(hours: 5)) ?? now;
    final day = await showDatePicker(
      context: context,
      initialDate: old.isBefore(now) ? now : old,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: old.hour, minute: old.minute),
      helpText: 'Toshkent vaqti',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    final value = DateTime.utc(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 5));
    setState(() {
      if (first) {
        start = value;
      } else {
        end = value;
      }
    });
  }

  void apply() {
    if (start == null ||
        end == null ||
        !start!.isAfter(DateTime.now().toUtc()) ||
        !end!.isAfter(start!) ||
        end!.difference(start!) > const Duration(days: 365)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kelajakdagi kelish va undan keyingi ketish vaqtini tanlang (365 kungacha).',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, [start!, end!]);
  }

  @override
  Widget build(BuildContext context) => CustomerPage(
    title: 'Kelish va ketish vaqti',
    children: [
      cText(
        'Toshkent vaqti. Tunab qolish mumkin; enaganing jadvali faqat kelish va ketish vaqtlariga qo‘llanadi.',
      ),
      for (final first in [true, false])
        ListTile(
          key: ValueKey(first ? 'discoveryStart' : 'discoveryEnd'),
          title: Text(first ? 'Kelish' : 'Ketish'),
          subtitle: Text(
            (first ? start : end) == null
                ? 'Sana va vaqtni tanlang'
                : discoveryTime((first ? start : end)!),
          ),
          trailing: const Icon(Icons.calendar_month),
          onTap: () => pick(first),
        ),
      FilledButton(
        key: const ValueKey('applyDiscoveryDates'),
        onPressed: apply,
        child: const Text('Enagalarni ko‘rsatish'),
      ),
    ],
  );
}

class CustomerFilterPage extends StatefulWidget {
  const CustomerFilterPage({
    super.key,
    required this.initial,
    this.hasLocation = false,
  });
  final CJson initial;
  final bool hasLocation;
  @override
  State<CustomerFilterPage> createState() => _CustomerFilterPageState();
}

class _CustomerFilterPageState extends State<CustomerFilterPage> {
  late final _min = TextEditingController(text: '${widget.initial['min']}');
  late final _max = TextEditingController(
    text: '${widget.initial['max'] ?? ''}',
  );
  late String _pet = widget.initial['pet'];
  late double? _distance = (widget.initial['distance'] as num?)?.toDouble();
  late bool _rating = widget.initial['rating'];
  late int _animals = widget.initial['animals'] ?? 1;
  late bool _verified = widget.initial['verified'] == true;
  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    final min = int.tryParse(_min.text), max = int.tryParse(_max.text);
    if (min == null ||
        (_max.text.trim().isNotEmpty && max == null) ||
        min < 0 ||
        min > 999999999 ||
        (max != null && (max < min || max > 999999999))) {
      cNotice(context, 'Narx oralig‘ini to‘g‘ri kiriting.');
      return;
    }
    Navigator.pop(context, {
      'pet': _pet,
      'min': min,
      'max': max,
      'distance': widget.hasLocation ? _distance : null,
      'rating': _rating,
      'animals': _animals,
      'verified': _verified,
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
          for (final p in ['', 'It', 'Mushuk'])
            ChoiceChip(
              label: Text(p.isEmpty ? lt('Barchasi', 'All', 'Все') : ct(p)),
              selected: _pet == p,
              onSelected: (_) => setState(() => _pet = p),
            ),
        ],
      ),
      const SizedBox(height: 24),
      DropdownButtonFormField<int>(
        key: const ValueKey('filterAnimals'),
        initialValue: _animals,
        decoration: const InputDecoration(labelText: 'Hayvonlar soni'),
        items: [
          for (var i = 1; i <= 30; i++)
            DropdownMenuItem(value: i, child: Text('$i')),
        ],
        onChanged: (value) => setState(() => _animals = value ?? 1),
      ),
      SwitchListTile(
        key: const ValueKey('filterVerified'),
        title: const Text('Faqat MyID orqali tekshirilgan enagalar'),
        subtitle: const Text('TEST tasdiq shaxs tekshiruvi hisoblanmaydi.'),
        value: _verified,
        onChanged: (value) => setState(() => _verified = value),
      ),
      cField(_min, 'Minimal narx (so‘m)', number: true),
      cField(_max, 'Maksimal narx (so‘m)', number: true),
      cText(
        lt(
          'Maksimal narx bo‘sh bo‘lsa cheklanmaydi.',
          'Leave maximum price blank for no limit.',
          'Пустой максимум — без ограничения.',
        ),
        size: 12,
      ),
      cText(
        _distance == null
            ? lt('Masofa cheklanmagan', 'Any distance', 'Любое расстояние')
            : 'Masofa: ${_distance!.round()} km',
        bold: true,
      ),
      cText(
        widget.hasLocation
            ? 'Bu faqat qidiruv filtri. Toshkent ichida enaga xizmat radiusi cheklanmagan. Masofasi noma’lum e’lonlar yashirilmaydi.'
            : 'Masofa filtri uchun bosh sahifada joylashuvni yoqing. Toshkent bo‘yicha qidiruv ochiq.',
        size: 12,
      ),
      Slider(
        key: const ValueKey('filterDistance'),
        value: _distance ?? 50,
        min: 1,
        max: 50,
        divisions: 49,
        activeColor: listingGold,
        onChanged: widget.hasLocation
            ? (v) => setState(() => _distance = v)
            : null,
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
          _max.text = '';
          _distance = null;
          _rating = false;
          _animals = 1;
          _verified = false;
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
                    cText(
                      sitter['years'] == null
                          ? lt(
                              'Tajriba ko‘rsatilmagan',
                              'Experience not specified',
                              'Стаж не указан',
                            )
                          : '${sitter['years']} yillik tajriba',
                      size: 13,
                    ),
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
        if (store.remote)
          PublicContentReportButton(
            api: store.api,
            target: {'kind': 'listing', 'id': sitter['id']},
          ),
      ],
    ),
  );
}
