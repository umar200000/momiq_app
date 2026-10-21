import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../data/listing_store.dart';
import 'care_location_page.dart';
import 'listing_style.dart';
import 'service_form_page.dart';

class ListingsPanel extends StatefulWidget {
  const ListingsPanel({
    super.key,
    this.store,
    this.locationPicker = pickCareLocation,
  });
  final ListingStore? store;
  final LocationPicker locationPicker;
  @override
  State<ListingsPanel> createState() => _ListingsPanelState();
}

class _ListingsPanelState extends State<ListingsPanel> {
  late final _store = widget.store ?? ListingStore.instance;
  bool _loading = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await _store.load();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(ServiceType type) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ServiceFormPage(
          type: type,
          store: _store,
          locationPicker: widget.locationPicker,
        ),
      ),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lt('E’lon saqlandi', 'Listing saved', 'Объявление сохранено'),
          ),
        ),
      );
    }
  }

  Future<void> _toggle(ServiceType type, bool active) async {
    if (active && _store.conflictsFor(type).isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: _store,
          builder: (context, _) => AlertDialog(
            backgroundColor: formSurface,
            title: Text(
              lt('Faol xizmatlar', 'Active services', 'Активные услуги'),
              style: profileText(20, bold: true),
            ),
            content: SingleChildScrollView(
              child: _store.conflictsFor(type).isEmpty
                  ? Text(
                      lt(
                        'Endi xizmatni yoqishingiz mumkin.',
                        'You can activate this service now.',
                        'Теперь можно включить услугу.',
                      ),
                    )
                  : ConflictNotice(store: _store, type: type),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(lt('Yopish', 'Close', 'Закрыть')),
              ),
              FilledButton(
                onPressed: _store.busy || _store.conflictsFor(type).isNotEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(lt('Faollashtirish', 'Activate', 'Включить')),
              ),
            ],
          ),
        ),
      );
      if (proceed != true || !mounted) return;
    }
    try {
      await _store.setActive(type, active);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              problemText(
                error is ListingException
                    ? error.problem
                    : ListingProblem.storage,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed) {
      return serviceSurface(
        Column(
          children: [
            Text(
              lt(
                'E’lonlarni yuklab bo‘lmadi.',
                'Could not load listings.',
                'Не удалось загрузить объявления.',
              ),
            ),
            TextButton(
              onPressed: _load,
              child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
            ),
          ],
        ),
      );
    }
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_store.busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lt('E’lon berish', 'Post a service', 'Объявление'),
                  style: profileText(23, bold: true),
                ),
                const SizedBox(height: 3),
                Text(
                  lt(
                    'Saqlangan e’lonlar hisobingizga bog‘lanadi va administratorga ko‘rinadi.',
                    'Saved listings are linked to your account and visible to the administrator.',
                    'Сохранённые объявления привязаны к вашему аккаунту и видны администратору.',
                  ),
                  style: profileText(13),
                ),
              ],
            ),
          ),
          for (final type in ServiceType.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _serviceCard(type, _store[type]),
            ),
        ],
      ),
    );
  }

  Widget _serviceCard(ServiceType type, ServiceListing? listing) => Container(
    key: ValueKey('service-${type.name}'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: listingSurface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: listing == null
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: ServiceMark(type: type),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            serviceTitle(type),
                            style: profileText(14, bold: true),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: AppColors.chocolate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(switch (type) {
                      ServiceType.boarding => lt(
                        'Uyda mehrli parvarish xizmati.',
                        'Caring for pets at your home.',
                        'Забота о питомцах у себя дома.',
                      ),
                      ServiceType.homeVisit => lt(
                        'Mijozning uyida parvarish xizmati ko‘rsating.',
                        'Care for pets at the client’s home.',
                        'Ухаживайте за питомцами у клиента дома.',
                      ),
                      ServiceType.personal => lt(
                        'Doimiy va individual parvarish xizmati.',
                        'Dedicated, individual care.',
                        'Постоянный индивидуальный уход.',
                      ),
                    }, style: profileText(11)),
                    const SizedBox(height: 9),
                    FilledButton(
                      key: ValueKey('create-${type.name}'),
                      style: serviceButtonStyle().copyWith(
                        minimumSize: const WidgetStatePropertyAll(
                          Size(double.infinity, 36),
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        ),
                      ),
                      onPressed: () => _edit(type),
                      child: Text(
                        lt(
                          'E’lon yaratish',
                          'Create listing',
                          'Создать объявление',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      serviceTitle(type),
                      style: profileText(17, bold: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    listing.active
                        ? lt('Faol', 'Active', 'Вкл.')
                        : lt('Nofaol', 'Inactive', 'Выкл.'),
                    style: profileText(11).copyWith(color: listingAccent),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 42,
                    height: 32,
                    child: FittedBox(
                      child: Switch(
                        key: ValueKey('active-${type.name}'),
                        value: listing.active,
                        activeTrackColor: listingGold,
                        activeThumbColor: Colors.white,
                        onChanged: _store.busy
                            ? null
                            : (value) => _toggle(type, value),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 135,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (listing.pets.length == 1)
                            ServicePetPhoto(
                              pet: listing.pets.first,
                              height: 132,
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: ServicePetPhoto(
                                    pet: PetType.dog,
                                    height: 110,
                                  ),
                                ),
                                Expanded(
                                  child: ServicePetPhoto(
                                    pet: PetType.cat,
                                    height: 110,
                                  ),
                                ),
                              ],
                            ),
                          const Positioned(
                            right: 0,
                            top: 26,
                            child: Icon(
                              Icons.favorite_border_rounded,
                              color: Color(0xFFDEC19A),
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _info(
                          Icons.pets_outlined,
                          listing.pets.map(petTitle).join(' · '),
                        ),
                        if (type == ServiceType.boarding)
                          _info(
                            Icons.groups_outlined,
                            lt(
                              'Bir vaqtda ${listing.capacity} ta',
                              'Up to ${listing.capacity} pets',
                              'Одновременно: ${listing.capacity}',
                            ),
                          ),
                        _info(
                          Icons.toll_outlined,
                          '${priceText(listing.dailyPrice)} ${lt('so‘m / kun', 'UZS / day', 'сум / день')}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: ValueKey('edit-${type.name}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: listingAccent,
                    side: const BorderSide(color: listingAccent, width: 1.2),
                    minimumSize: const Size(double.infinity, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _store.busy ? null : () => _edit(type),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: Text(
                    lt('Tahrirlash', 'Edit listing', 'Редактировать'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
  );

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: AppColors.chocolate),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: profileText(11, bold: true),
          ),
        ),
      ],
    ),
  );
}
