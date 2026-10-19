import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import '../data/map_access.dart';
import 'map_requirements_panel.dart';
import 'package:flutter/material.dart';
import 'price_input_formatter.dart';
import '../../../core/theme/app_colors.dart';
import 'care_location_preview.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import '../data/listing_store.dart';
import 'care_location_page.dart';
import 'listing_style.dart';

class ServiceFormPage extends StatefulWidget {
  const ServiceFormPage({
    super.key,
    required this.type,
    required this.store,
    this.locationPicker = pickCareLocation,
    this.accessProbe,
  });
  final ServiceType type;
  final ListingStore store;
  final LocationPicker locationPicker;
  final MapAccessProbe? accessProbe;
  @override
  State<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends State<ServiceFormPage> {
  final _price = TextEditingController();
  late final _access = MapAccessController(probe: widget.accessProbe);
  bool _askedForAccess = false;
  void _accessChanged() {
    if (!mounted) return;
    setState(() {});
    if (_access.ready) {
      _askedForAccess = false;
      return;
    }
    if (_access.state == null || _askedForAccess || _choosingLocation) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _askedForAccess ||
          _access.ready ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _askedForAccess = true;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: listingSurface,
          content: SingleChildScrollView(
            child: MapRequirementsPanel(controller: _access),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(lt('Davom etish', 'Continue', 'Продолжить')),
            ),
          ],
        ),
      );
    });
  }

  final Set<PetType> _pets = {};
  int _capacity = 1;
  CareLocation? _location;
  late final ServiceListing? _original;
  bool _saving = false;
  bool _choosingLocation = false;
  String? _error;
  bool get _visiting => widget.type == ServiceType.homeVisit;
  ServiceListing get _draft => ServiceListing(
    type: widget.type,
    pets: _pets,
    dailyPrice: int.tryParse(_price.text.replaceAll(' ', '')) ?? 0,
    capacity: widget.type == ServiceType.boarding ? _capacity : null,
    location: _visiting ? null : _location,
    active: _original?.active ?? true,
  );

  @override
  void initState() {
    super.initState();
    if (!_visiting) {
      _access.addListener(_accessChanged);
      _access.start();
    }
    _original = widget.store[widget.type];
    if (_original != null) {
      _pets.addAll(_original.pets);
      _price.text = priceText(_original.dailyPrice);
      _capacity = _original.capacity ?? 1;
      _location = _original.location;
    }
  }

  @override
  void dispose() {
    _access.removeListener(_accessChanged);
    _access.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || widget.store.busy) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(_draft);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = problemText(
            error is ListingException ? error.problem : ListingProblem.storage,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickLocation() async {
    if (_choosingLocation) return;
    _choosingLocation = true;
    FocusScope.of(context).unfocus();
    try {
      if (!await _access.refresh() || !mounted) return;
      final selected = await widget.locationPicker(context, _location);
      if (mounted && selected != null) setState(() => _location = selected);
    } finally {
      _choosingLocation = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => MomiqScaffold(
      backgroundColor: listingBackground,
      appBar: AppBar(
        backgroundColor: listingBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.chocolate,
        centerTitle: true,
        title: Text(
          serviceTitle(widget.type),
          style: profileText(17, bold: true),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: serviceSurface(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionLabel(
                      lt(
                        'Hayvonni tanlang *',
                        'Choose a pet *',
                        'Выберите животное *',
                      ),
                      hint: _visiting
                          ? lt(
                              'Birini yoki ikkalasini tanlang',
                              'Choose one or both',
                              'Можно выбрать обоих',
                            )
                          : lt(
                              'Faqat bittasini tanlang',
                              'Choose one only',
                              'Выберите только одного',
                            ),
                    ),
                    Row(
                      children: [
                        Expanded(child: _petChoice(PetType.dog)),
                        const SizedBox(width: 12),
                        Expanded(child: _petChoice(PetType.cat)),
                      ],
                    ),
                    if (widget.type == ServiceType.boarding) ...[
                      const SizedBox(height: 20),
                      sectionLabel(
                        lt(
                          'Bir vaqtda nechta hayvon? *',
                          'Pets at the same time *',
                          'Сколько животных одновременно? *',
                        ),
                      ),
                      Row(
                        children: [
                          for (
                            var count = 1;
                            count <= widget.store.maxCapacity;
                            count++
                          ) ...[
                            if (count > 1) const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: Material(
                                  color: _capacity == count
                                      ? listingGold
                                      : const Color(0xFFFCF9F5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: _capacity == count
                                          ? listingGold
                                          : listingBorder,
                                    ),
                                  ),
                                  child: InkWell(
                                    key: ValueKey('capacity-$count'),
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () =>
                                        setState(() => _capacity = count),
                                    child: Center(
                                      child: Text(
                                        '$count',
                                        style: profileText(14, bold: true)
                                            .copyWith(
                                              color: _capacity == count
                                                  ? Colors.white
                                                  : AppColors.chocolate,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (!_visiting) ...[
                      const SizedBox(height: 20),
                      sectionLabel(
                        lt(
                          'Parvarish manzili *',
                          'Care location *',
                          'Адрес ухода *',
                        ),
                      ),
                      if (!_access.ready)
                        MapRequirementsPanel(controller: _access)
                      else
                        CareLocationPreview(
                          location: _location,
                          onTap: _pickLocation,
                        ),
                    ],
                    const SizedBox(height: 20),
                    sectionLabel(
                      lt('Kunlik narx *', 'Daily price *', 'Цена за день *'),
                    ),
                    TextField(
                      key: const ValueKey('dailyPrice'),
                      controller: _price,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [PriceInputFormatter()],
                      onChanged: (_) => setState(() => _error = null),
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      style: profileText(18, bold: true),
                      decoration: InputDecoration(
                        hintText: '80 000',
                        hintStyle: profileText(
                          18,
                        ).copyWith(color: const Color(0xFFB5A99B)),
                        suffixText: lt('so‘m / kun', 'UZS / day', 'сум / день'),
                        suffixStyle: profileText(11),
                        filled: true,
                        fillColor: const Color(0xFFFCF9F5),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: listingBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: listingBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: listingGold,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    if (_draft.active &&
                        widget.store.conflictsFor(widget.type).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ConflictNotice(store: widget.store, type: widget.type),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFF9E402F)),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      lt(
                        '* Majburiy maydonlar',
                        '* Required fields',
                        '* Обязательные поля',
                      ),
                      style: profileText(10),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('saveListing'),
                      style: serviceButtonStyle(),
                      onPressed:
                          _saving ||
                              widget.store.busy ||
                              widget.store.validate(_draft) != null
                          ? null
                          : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _original == null
                                  ? lt(
                                      'E’lon yaratish',
                                      'Create listing',
                                      'Создать объявление',
                                    )
                                  : lt('Saqlash', 'Save changes', 'Сохранить'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _petChoice(PetType pet) {
    final selected = _pets.contains(pet);
    return Semantics(
      selected: selected,
      button: true,
      label: petTitle(pet),
      child: Material(
        color: const Color(0xFFFCF9F5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected ? listingAccent : listingBorder,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('pet-${pet.name}'),
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() {
            if (_visiting && selected) {
              _pets.remove(pet);
            } else {
              if (!_visiting) _pets.clear();
              _pets.add(pet);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
            child: Column(
              children: [
                ServicePetPhoto(pet: pet, height: 95),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: selected ? listingAccent : formBorder,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        petTitle(pet),
                        style: profileText(13, bold: selected),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ConflictNotice extends StatelessWidget {
  const ConflictNotice({super.key, required this.store, required this.type});
  final ListingStore store;
  final ServiceType type;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE8C5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_rounded, size: 20, color: listingAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                lt(
                  'Boshqa faol e’lonlarni avval o‘chiring.',
                  'Turn off other active services first.',
                  'Сначала отключите другие активные услуги.',
                ),
                style: profileText(
                  11,
                  bold: true,
                ).copyWith(color: listingAccent),
              ),
            ),
          ],
        ),
      ),
      for (final conflict in store.conflictsFor(type))
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: listingBorder),
          ),
          child: Row(
            children: [
              ServiceMark(type: conflict.type, size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceTitle(conflict.type),
                      style: profileText(11, bold: true),
                    ),
                    Text(
                      lt(
                        'Bu xizmat allaqachon faol.',
                        'This service is active.',
                        'Эта услуга уже активна.',
                      ),
                      style: profileText(9),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                child: FittedBox(
                  child: Switch(
                    key: ValueKey('conflict-${conflict.type.name}'),
                    value: true,
                    activeThumbColor: Colors.white,
                    activeTrackColor: listingGold,
                    onChanged: store.busy
                        ? null
                        : (_) async {
                            try {
                              await store.setActive(conflict.type, false);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      problemText(ListingProblem.storage),
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
