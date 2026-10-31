import '../../support/support_page.dart';
import 'pet_safety.dart';
import '../../onboarding/data/profile_photo_source.dart';
import 'customer_home_page.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/localization/app_language.dart';
import '../../listings/data/listing_store.dart' show CareLocation;
import '../../listings/presentation/care_location_page.dart';
import '../../listings/presentation/care_location_preview.dart';
import 'customer_widgets.dart';

class CustomerPetsPage extends StatelessWidget {
  const CustomerPetsPage({super.key, required this.store, this.select = false});
  final CustomerStore store;
  final bool select;
  Future<void> _archive(BuildContext context, CJson pet, bool archived) async {
    final revision = store.revision;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          archived
              ? lt('Hayvonni arxivlash', 'Archive pet', 'Архивировать питомца')
              : lt('Hayvonni tiklash', 'Restore pet', 'Восстановить питомца'),
        ),
        content: Text(
          archived
              ? lt(
                  'Hayvon yangi buyurtma tanlovidan yashiriladi. Eski buyurtmalar va tarix saqlanadi.',
                  'The pet will be hidden from new bookings. Existing bookings and history are kept.',
                  'Питомец будет скрыт при создании новых заказов. Текущие заказы и история сохранятся.',
                )
              : lt(
                  'Hayvon yana yangi buyurtmalarda tanlanadi.',
                  'The pet will be available for new bookings again.',
                  'Питомца снова можно будет выбрать для нового заказа.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Ortga', 'Back', 'Назад')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              archived
                  ? lt('Arxivlash', 'Archive', 'В архив')
                  : lt('Tiklash', 'Restore', 'Восстановить'),
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    try {
      await store.archivePet(pet['id'], archived, expectedRevision: revision);
    } catch (error) {
      if (context.mounted) cNotice(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => CustomerPage(
      title: 'Mening hayvonlarim',
      bottom: cButton(
        'Hayvon qo‘shish',
        () => cPush(context, CustomerPetForm(store: store)),
        id: 'addCustomerPet',
        icon: Icons.add,
      ),
      children: [
        for (final pet in store.list('pets'))
          cCard(
            Column(
              children: [
                Row(
                  children: [
                    CustomerPetArt(pet: pet, size: 82),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cText(customerPetName(pet), bold: true, size: 21),
                          cText(customerPetDescription(pet), size: 13),
                          TextButton.icon(
                            onPressed: () => cPush(
                              context,
                              CustomerPetForm(store: store, pet: pet),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(ct('Tahrirlash')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ('${pet['notes'] ?? ''}'.trim().isNotEmpty)
                  cRow(Icons.notes_outlined, '${pet['notes']}'),
                if (!select)
                  TextButton.icon(
                    key: ValueKey('archivePet-${pet['id']}'),
                    onPressed: store.busy
                        ? null
                        : () => _archive(context, pet, true),
                    icon: const Icon(Icons.archive_outlined),
                    label: Text(lt('Arxivlash', 'Archive', 'В архив')),
                  ),
              ],
            ),
            onTap: select
                ? () => Navigator.pop(context, pet)
                : () => cPush(context, CustomerPetForm(store: store, pet: pet)),
          ),
        if (store.list('pets').isEmpty) cText('Hozircha bo‘sh'),
        if (!select && store.archivedPets.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('archivedPets'),
            title: Text(
              lt('Arxivdagi hayvonlar', 'Archived pets', 'Питомцы в архиве'),
            ),
            children: [
              for (final pet in store.archivedPets)
                ListTile(
                  title: Text(customerPetName(pet)),
                  trailing: TextButton(
                    key: ValueKey('restorePet-${pet['id']}'),
                    onPressed: store.busy
                        ? null
                        : () => _archive(context, pet, false),
                    child: Text(lt('Tiklash', 'Restore', 'Восстановить')),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

class CustomerPetForm extends StatefulWidget {
  const CustomerPetForm({
    super.key,
    required this.store,
    this.pet,
    this.allowedTypes = const ['It', 'Mushuk', 'Boshqa'],
    this.photoSource,
  });
  final List<String> allowedTypes;
  final ProfilePhotoSource? photoSource;
  final CustomerStore store;
  final CJson? pet;
  @override
  State<CustomerPetForm> createState() => _CustomerPetFormState();
}

class _CustomerPetFormState extends State<CustomerPetForm> {
  late final int? _revision;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _age = TextEditingController(),
      _breed = TextEditingController(),
      _notes = TextEditingController(),
      _otherType = TextEditingController();
  final _safety = {
    for (final field in petSafetyFields) field: TextEditingController(),
  };
  String? _type;
  String _sex = '';
  bool _picking = false;
  String? _requiredError;
  late final _photos = widget.photoSource ?? ProfilePhotoSource();
  String? _photo;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _revision = widget.store.revision;
    _type = widget.allowedTypes.length == 1 ? widget.allowedTypes.single : null;
    final p = widget.pet;
    if (p != null) {
      _name.text = p['name'] ?? '';
      _age.text = p['age'] ?? '';
      _breed.text = p['breed'] ?? '';
      _notes.text = p['notes'] ?? '';
      for (final field in petSafetyFields) {
        _safety[field]!.text = p[field] as String? ?? '';
      }
      if (widget.allowedTypes.contains(p['type'])) _type = p['type'];
      _otherType.text = p['otherType'] ?? '';
      _sex = p['sex'] ?? '';
      _photo = p['photo'];
    }
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: listingSurface,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final source in ImageSource.values)
                ListTile(
                  key: ValueKey('petPhoto-${source.name}'),
                  leading: Icon(
                    source == ImageSource.camera
                        ? Icons.camera_alt_outlined
                        : Icons.photo_library_outlined,
                  ),
                  title: Text(
                    source == ImageSource.camera
                        ? lt('Kamera', 'Camera', 'Камера')
                        : lt('Galereya', 'Gallery', 'Галерея'),
                  ),
                  onTap: () => Navigator.pop(context, source),
                ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;
      final bytes = await _photos.pickProfile(source: source);
      if (mounted && bytes != null) {
        setState(() => _photo = base64Encode(bytes));
      }
    } catch (_) {
      if (mounted) cNotice(context, 'Rasm ochilmadi.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking) return;
    if (_photo == null ||
        _photo!.isEmpty ||
        !widget.allowedTypes.contains(_type)) {
      setState(
        () => _requiredError = lt(
          'Rasm va hayvon turini tanlang.',
          'Select a photo and pet type.',
          'Выберите фото и вид животного.',
        ),
      );
      cNotice(context, _requiredError!);
      return;
    }
    if (!_form.currentState!.validate()) return;
    final age = int.tryParse(_age.text);
    if (_age.text.trim().isNotEmpty && (age == null || age < 0 || age > 100)) {
      cNotice(context, 'Yoshni 0–100 oralig‘ida kiriting.');
      return;
    }
    setState(() => _saving = true);
    try {
      final id =
          widget.pet?['id'] ?? 'pet-${DateTime.now().microsecondsSinceEpoch}';
      await widget.store.saveItem('pets', {
        'id': id,
        'name': _name.text.trim(),
        'age': _age.text,
        'type': _type,
        'otherType': _type == 'Boshqa' ? _otherType.text.trim() : '',
        'sex': _sex,
        'breed': _breed.text.trim(),
        'notes': _notes.text.trim(),
        for (final field in petSafetyFields) field: _safety[field]!.text.trim(),
        'photo': _photo,
      }, expectedRevision: _revision);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) cNotice(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _age,
      _breed,
      _notes,
      _otherType,
      ..._safety.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomerPage(
    title: widget.pet == null ? 'Hayvon qo‘shish' : 'Tahrirlash',
    bottom: cButton(
      'Saqlash',
      _saving || _picking ? null : _save,
      id: 'saveCustomerPet',
      loading: _saving,
    ),
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CustomerPetArt(
                pet: {'photo': _photo, 'type': _type},
                size: 110,
              ),
            ),
            Center(
              child: TextButton.icon(
                key: const ValueKey('pickCustomerPetPhoto'),
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(ct('Rasmni almashtirish')),
              ),
            ),
            if (_requiredError != null)
              cText(_requiredError!, color: Colors.red),
            cText(
              lt(
                'Rasm va hayvon turi majburiy. Qolgan maydonlar ixtiyoriy.',
                'Photo and pet type are required. Other fields are optional.',
                'Фото и вид животного обязательны. Остальные поля необязательны.',
              ),
              size: 12,
            ),
            const SizedBox(height: 12),
            cText('Hayvon turi', bold: true),
            Wrap(
              spacing: 8,
              children: [
                for (final t in widget.allowedTypes)
                  ChoiceChip(
                    label: Text(ct(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            if (_type == 'Boshqa')
              cField(
                _otherType,
                lt('Qaysi hayvon?', 'Animal type', 'Какое животное?'),
                id: 'customerPetOtherType',
                required: true,
              ),
            const SizedBox(height: 18),
            cField(_name, 'Ismi', id: 'customerPetName'),
            cField(_age, 'Yoshi', id: 'customerPetAge', number: true),
            Wrap(
              spacing: 8,
              children: [
                for (final v in ['Erkak', 'Urg‘ochi'])
                  ChoiceChip(
                    label: Text(ct(v)),
                    selected: _sex == v,
                    onSelected: (selected) =>
                        setState(() => _sex = selected ? v : ''),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            cField(_breed, 'Zoti'),
            cField(_notes, 'Xususiyatlari', lines: 3),
            PetSafetyFields(controllers: _safety),
          ],
        ),
      ),
    ],
  );
}

class CustomerProfileForm extends StatefulWidget {
  const CustomerProfileForm({
    super.key,
    required this.store,
    this.registration = false,
    this.photoSource,
  });
  final bool registration;
  final ProfilePhotoSource? photoSource;
  final CustomerStore store;
  @override
  State<CustomerProfileForm> createState() => _CustomerProfileFormState();
}

class _CustomerProfileFormState extends State<CustomerProfileForm> {
  late final int? _revision;
  @override
  void initState() {
    super.initState();
    _revision = widget.store.revision;
  }

  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(
    text: widget.store.profile['first'] ?? '',
  );
  late final _last = TextEditingController(
    text: widget.store.profile['last'] ?? '',
  );
  late String? _photo = widget.store.profile['photo'];
  bool _saving = false;
  bool _picking = false;
  late final _photos = widget.photoSource ?? ProfilePhotoSource();
  Future<void> _photoPick() async {
    if (_picking || _saving) return;
    setState(() => _picking = true);
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final source in ImageSource.values)
                ListTile(
                  key: ValueKey('profilePhoto-${source.name}'),
                  leading: Icon(
                    source == ImageSource.camera
                        ? Icons.camera_alt_outlined
                        : Icons.photo_library_outlined,
                  ),
                  title: Text(
                    source == ImageSource.camera
                        ? lt('Kamera', 'Camera', 'Камера')
                        : lt('Galereya', 'Gallery', 'Галерея'),
                  ),
                  onTap: () => Navigator.pop(context, source),
                ),
            ],
          ),
        ),
      );
      if (!mounted || source == null) return;
      final bytes = await _photos.pickProfile(source: source);
      if (mounted && bytes != null) {
        if (bytes.length > 3 * 1024 * 1024) {
          cNotice(
            context,
            lt(
              'Rasm 3 MB dan kichik bo‘lishi kerak.',
              'Photo must be under 3 MB.',
              'Фото должно быть меньше 3 МБ.',
            ),
          );
          return;
        }
        setState(() => _photo = base64Encode(bytes));
      }
    } catch (_) {
      if (mounted) cNotice(context, 'Rasm ochilmadi.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.store.update(
        (d) => d['profile'] = {
          'first': _first.text.trim(),
          'last': _last.text.trim(),
          'photo': _photo,
        },
        expectedRevision: _revision,
      );
      if (!mounted) return;
      if (widget.registration) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const CustomerHomePage()),
          (_) => false,
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) cNotice(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomerPage(
    title: widget.registration
        ? lt('Ro‘yxatdan o‘tish', 'Registration', 'Регистрация')
        : 'Profilni tahrirlash',
    bottom: cButton(
      widget.registration
          ? lt('Ro‘yxatdan o‘tish', 'Register', 'Зарегистрироваться')
          : 'Saqlash',
      _saving || _picking ? null : _save,
      id: widget.registration ? 'registerCustomer' : 'saveCustomerProfile',
      loading: _saving,
    ),
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: listingSurface,
              backgroundImage: _photo == null
                  ? null
                  : MemoryImage(base64Decode(_photo!)),
              child: _photo == null
                  ? const Icon(Icons.person_outline, size: 50)
                  : null,
            ),
            TextButton.icon(
              key: const ValueKey('pickCustomerProfilePhoto'),
              onPressed: _picking || _saving ? null : _photoPick,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(
                widget.registration
                    ? lt(
                        'Profil rasmi (ixtiyoriy)',
                        'Profile photo (optional)',
                        'Фото профиля (необязательно)',
                      )
                    : ct('Rasmni almashtirish'),
              ),
            ),
            if (_photo != null)
              TextButton(
                key: const ValueKey('removeCustomerProfilePhoto'),
                onPressed: _picking || _saving
                    ? null
                    : () => setState(() => _photo = null),
                child: Text(
                  lt('Rasmni olib tashlash', 'Remove photo', 'Удалить фото'),
                ),
              ),
            if (widget.registration)
              cText(
                lt(
                  'Rasmsiz ham ro‘yxatdan o‘tishingiz mumkin.',
                  'You can register without a photo.',
                  'Можно зарегистрироваться без фото.',
                ),
                size: 12,
              ),
            const SizedBox(height: 24),
            cField(
              _first,
              'Ism',
              required: true,
              limit: 100,
              id: 'customerFirst',
            ),
            cField(
              _last,
              'Familiya',
              required: true,
              limit: 100,
              id: 'customerLast',
            ),
          ],
        ),
      ),
    ],
  );
}

class CustomerAddressesPage extends StatelessWidget {
  const CustomerAddressesPage({
    super.key,
    required this.store,
    this.select = false,
  });
  final CustomerStore store;
  final bool select;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => CustomerPage(
      title: 'Manzillarim',
      bottom: cButton(
        'Manzil qo‘shish',
        () => cPush(context, CustomerAddressForm(store: store)),
        icon: Icons.add,
      ),
      children: [
        if (store.list('addresses').isEmpty) cCard(cText('Hozircha bo‘sh')),
        for (final a in store.list('addresses'))
          cCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cText(a['label'], bold: true, size: 19),
                cRow(Icons.location_on_outlined, a['address']),
                if ('${a['apartment']}'.isNotEmpty)
                  cText('Xonadon ${a['apartment']}', size: 13),
                TextButton.icon(
                  onPressed: () => cPush(
                    context,
                    CustomerAddressForm(store: store, address: a),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(ct('Tahrirlash')),
                ),
              ],
            ),
            onTap: select
                ? () => Navigator.pop(context, a)
                : () => cPush(
                    context,
                    CustomerAddressForm(store: store, address: a),
                  ),
          ),
      ],
    ),
  );
}

class CustomerAddressForm extends StatefulWidget {
  const CustomerAddressForm({super.key, required this.store, this.address});
  final CustomerStore store;
  final CJson? address;
  @override
  State<CustomerAddressForm> createState() => _CustomerAddressFormState();
}

class _CustomerAddressFormState extends State<CustomerAddressForm> {
  late final int? _revision;
  late final _label = TextEditingController(
    text: widget.address?['label'] ?? 'Uyim',
  );
  late final _flat = TextEditingController(
    text: widget.address?['apartment'] ?? '',
  );
  CareLocation? _location;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _revision = widget.store.revision;
    if (widget.address != null) {
      _location = CareLocation.fromJson(widget.address!);
    }
  }

  Future<void> _map() async {
    final value = await pickCareLocation(context, _location);
    if (value != null && mounted) setState(() => _location = value);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_location == null || _label.text.trim().isEmpty) {
      cNotice(context, 'Manzilni xaritadan belgilang va nomini kiriting.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.store.saveItem('addresses', {
        'id':
            widget.address?['id'] ??
            'address-${DateTime.now().microsecondsSinceEpoch}',
        ..._location!.toJson(),
        'label': _label.text.trim(),
        'apartment': _flat.text.trim(),
      }, expectedRevision: _revision);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) cNotice(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _flat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomerPage(
    title: 'Manzilni belgilang',
    bottom: cButton('Saqlash', _saving ? null : _save, loading: _saving),
    children: [
      CareLocationPreview(location: _location, onTap: _map),
      cButton(
        'Xaritadan tanlash',
        _map,
        secondary: true,
        icon: Icons.map_outlined,
      ),
      const SizedBox(height: 18),
      cField(_label, 'Manzil nomi'),
      cField(_flat, 'Xonadon (ixtiyoriy)'),
    ],
  );
}

class CustomerSettingsPage extends StatefulWidget {
  const CustomerSettingsPage({super.key, required this.store});
  final CustomerStore store;
  @override
  State<CustomerSettingsPage> createState() => _CustomerSettingsPageState();
}

class _CustomerSettingsPageState extends State<CustomerSettingsPage> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([AppLanguage.current, widget.store]),
    builder: (context, _) => CustomerPage(
      title: 'Til',
      children: [
        cText('Til', size: 20, bold: true),
        const SizedBox(height: 12),
        for (final l in [
          ('uz', 'O‘zbekcha'),
          ('ru', 'Русский'),
          ('en', 'English'),
        ])
          cCard(
            ListTile(
              key: ValueKey('customerLanguage-${l.$1}'),
              title: Text(l.$2),
              trailing: Icon(
                AppLanguage.current.value == l.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: listingGold,
              ),
              onTap: widget.store.busy
                  ? null
                  : () => cAction(context, () async {
                      await widget.store.update((d) => d['language'] = l.$1);
                      await AppLanguage.select(l.$1);
                    }),
            ),
          ),
        if (widget.store.busy) const LinearProgressIndicator(),
        cText('Bildirishnomalar', size: 20, bold: true),
        const SizedBox(height: 12),
        for (final n in [
          ('orders', 'Buyurtmalar'),
          ('chat', 'Chatlar'),
          ('video', 'Video hisobotlar'),
        ])
          cCard(
            SwitchListTile(
              title: Text(ct(n.$2)),
              value: widget.store.notifications[n.$1] as bool,
              onChanged: widget.store.busy
                  ? null
                  : (v) => cAction(
                      context,
                      () => widget.store.update(
                        (d) => (d['notifications'] as Map)[n.$1] = v,
                      ),
                    ),
            ),
          ),
        cText(
          lt(
            'Bu sozlamalar kelajakdagi push xabarlari uchun saqlanadi. Hozir telefoningizga push yuborilmaydi. Ilova ichidagi buyurtma, chat, parvarish va to‘lov xabarlari tarixi bu tugmalar bilan o‘chmaydi.',
            'These preferences are saved for future push notifications. No push is sent to your phone yet. These switches do not remove booking, chat, care or payment notices from the in-app history.',
            'Эти настройки сохраняются для будущих push-уведомлений. Сейчас push на телефон не отправляются. Эти переключатели не удаляют уведомления о заказах, чате, уходе и платежах из истории в приложении.',
          ),
          size: 12,
        ),
      ],
    ),
  );
}

class CustomerHelpPage extends StatelessWidget {
  const CustomerHelpPage({super.key, required this.store});
  final CustomerStore store;
  @override
  Widget build(BuildContext context) => SupportPage(api: store.api);
}
