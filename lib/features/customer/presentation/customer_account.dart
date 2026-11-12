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
import '../../../core/widgets/owned_dialogs.dart';
import '../data/customer_api.dart';
import 'customer_session_boundary.dart' show RebuildOnSessionChange;

class CustomerPetsPage extends StatefulWidget {
  const CustomerPetsPage({super.key, required this.store, this.select = false});
  final CustomerStore store;
  final bool select;
  @override
  State<CustomerPetsPage> createState() => _CustomerPetsPageState();
}

class _CustomerPetsPageState extends State<CustomerPetsPage>
    with
        OwnedDialogs<CustomerPetsPage>,
        RebuildOnSessionChange<CustomerPetsPage> {
  final _sessionVersion = CustomerApi.sessionVersion;
  final _source = CustomerApi.active;
  CustomerStore get store => widget.store;
  bool get select => widget.select;
  bool _confirming = false, _refreshing = false, _unconfirmed = false;
  bool get _current =>
      mounted &&
      store.isCurrentSession &&
      CustomerApi.sessionVersion == _sessionVersion &&
      identical(CustomerApi.active, _source);
  bool _owns(CustomerStore source) =>
      _current &&
      identical(store, source) &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void onSessionChanged() {
    dismissOwnedRoutes();
    super.onSessionChanged();
  }

  @override
  void didUpdateWidget(CustomerPetsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, store) || oldWidget.select != select) {
      dismissOwnedRoutes();
      _unconfirmed = false;
    }
  }

  Future<void> _refresh() async {
    final source = store;
    if (!_owns(source) || _refreshing || store.busy) return;
    setState(() => _refreshing = true);
    try {
      final refreshed = await source.refreshRemote();
      if (_owns(source)) setState(() => _unconfirmed = !refreshed);
    } catch (_) {
      if (_owns(source)) setState(() => _unconfirmed = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _archive(CJson pet, bool archived) async {
    final source = store;
    if (!_owns(source) ||
        _confirming ||
        _unconfirmed ||
        _refreshing ||
        store.busy ||
        select) {
      return;
    }
    final revision = source.revision;
    _confirming = true;
    bool? accepted;
    try {
      accepted = await showOwnedDialog<bool>(
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
            archived
                ? lt(
                    'Hayvonni arxivlash',
                    'Archive pet',
                    'Архивировать питомца',
                  )
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
    } finally {
      _confirming = false;
    }
    if (accepted != true || !_owns(source) || select) return;
    try {
      await source.archivePet(pet['id'], archived, expectedRevision: revision);
    } catch (_) {
      // Keep recovery on its own page even if a newer route is above it.
      if (_current && identical(store, source)) {
        setState(() => _unconfirmed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => !_current
        ? CustomerPage(
            title: 'Mening hayvonlarim',
            children: [
              Text(
                lt(
                  'Hisobingizga qayta kiring.',
                  'Sign in again.',
                  'Войдите снова.',
                ),
              ),
            ],
          )
        : CustomerPage(
            title: 'Mening hayvonlarim',
            bottom: cButton(
              'Hayvon qo‘shish',
              () => cPush(context, CustomerPetForm(store: store)),
              id: 'addCustomerPet',
              icon: Icons.add,
            ),
            children: [
              if (_unconfirmed)
                cCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lt(
                          'Amal tasdiqlanmadi. Hayvon holatini yangilab tekshiring.',
                          'The action was not confirmed. Refresh to check the pet’s status.',
                          'Действие не подтверждено. Обновите данные и проверьте статус питомца.',
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('refreshPetStatus'),
                        onPressed: _refreshing ? null : _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(lt('Yangilash', 'Refresh', 'Обновить')),
                      ),
                    ],
                  ),
                ),
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
                                cText(
                                  customerPetName(pet),
                                  bold: true,
                                  size: 21,
                                ),
                                cText(customerPetDescription(pet), size: 13),
                                TextButton.icon(
                                  onPressed: () => cPush(
                                    context,
                                    CustomerPetForm(store: store, pet: pet),
                                  ),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
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
                          onPressed:
                              store.busy ||
                                  _unconfirmed ||
                                  _refreshing ||
                                  !_current
                              ? null
                              : () => _archive(pet, true),
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(lt('Arxivlash', 'Archive', 'В архив')),
                        ),
                    ],
                  ),
                  onTap: select
                      ? () => Navigator.pop(context, pet)
                      : () => cPush(
                          context,
                          CustomerPetForm(store: store, pet: pet),
                        ),
                ),
              if (store.list('pets').isEmpty) cText('Hozircha bo‘sh'),
              if (!select && store.archivedPets.isNotEmpty)
                ExpansionTile(
                  key: const ValueKey('archivedPets'),
                  title: Text(
                    lt(
                      'Arxivdagi hayvonlar',
                      'Archived pets',
                      'Питомцы в архиве',
                    ),
                  ),
                  children: [
                    for (final pet in store.archivedPets)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(customerPetName(pet)),
                            TextButton(
                              key: ValueKey('restorePet-${pet['id']}'),
                              onPressed:
                                  store.busy ||
                                      _unconfirmed ||
                                      _refreshing ||
                                      !_current
                                  ? null
                                  : () => _archive(pet, false),
                              child: Text(
                                lt('Tiklash', 'Restore', 'Восстановить'),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
  );
}

/// Draft controllers belong to the account and record that opened the form.
/// Rebinding the widget must not transplant those values into another record.
abstract class _CustomerFormState<T extends StatefulWidget> extends State<T>
    with OwnedDialogs<T>, RebuildOnSessionChange<T> {
  CustomerStore get formStore;
  Object? get formTarget;
  late final CustomerStore _sourceStore;
  late final CustomerApi? _sourceApi, _activeApi;
  late final int _session;
  late final Object? _sourceTarget;

  @override
  void initState() {
    super.initState();
    _sourceStore = formStore;
    _sourceApi = formStore.api;
    _activeApi = CustomerApi.active;
    _session = CustomerApi.sessionVersion;
    _sourceTarget = formTarget;
  }

  bool get formCurrent =>
      mounted &&
      formStore.isCurrentSession &&
      identical(_sourceStore, formStore) &&
      identical(_sourceApi, formStore.api) &&
      identical(_activeApi, CustomerApi.active) &&
      _session == CustomerApi.sessionVersion &&
      _sourceTarget == formTarget;
  bool get formForeground =>
      formCurrent && ModalRoute.of(context)?.isCurrent != false;

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!formCurrent) dismissOwnedRoutes();
  }

  @override
  void onSessionChanged() {
    dismissOwnedRoutes();
    super.onSessionChanged();
  }

  Widget get unavailableForm => CustomerPage(
    title: lt('Forma yangilandi', 'Form changed', 'Форма изменилась'),
    children: [
      Text(
        lt(
          'Hisob yoki tahrirlanayotgan ma’lumot o‘zgargan. Sahifani qayta oching.',
          'The account or record being edited has changed. Reopen the page.',
          'Аккаунт или редактируемые данные изменились. Откройте страницу заново.',
        ),
      ),
    ],
  );

  void showSaveError(Object error) {
    if (!formForeground) return;
    cNotice(
      context,
      error is CustomerApiException
          ? error.message
          : lt(
              'Saqlash tasdiqlanmadi. Kiritilgan ma’lumotlar shu formada saqlandi.',
              'The save was not confirmed. Your entries remain in this form.',
              'Сохранение не подтверждено. Введённые данные остались в форме.',
            ),
    );
  }
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

class _CustomerPetFormState extends _CustomerFormState<CustomerPetForm> {
  @override
  CustomerStore get formStore => widget.store;
  @override
  Object? get formTarget => widget.pet?['id'];
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
    if (!formForeground || _picking || _saving) return;
    setState(() => _picking = true);
    try {
      final source = await showOwnedSheet<ImageSource>(
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
      if (source == null || !formForeground) return;
      final bytes = await _photos.pickProfile(source: source);
      if (formCurrent && bytes != null) {
        setState(() => _photo = base64Encode(bytes));
      }
    } catch (_) {
      if (mounted && formForeground) cNotice(context, 'Rasm ochilmadi.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!formForeground || _saving || _picking) return;
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
      if (mounted && formForeground) Navigator.pop(context, id);
    } catch (e) {
      showSaveError(e);
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
  Widget build(BuildContext context) => !formCurrent
      ? unavailableForm
      : CustomerPage(
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
                      onPressed: _picking || _saving ? null : _pick,
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

class _CustomerProfileFormState
    extends _CustomerFormState<CustomerProfileForm> {
  @override
  CustomerStore get formStore => widget.store;
  @override
  Object? get formTarget => widget.registration;
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
    if (!formForeground || _picking || _saving) return;
    setState(() => _picking = true);
    try {
      final source = await showOwnedSheet<ImageSource>(
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
      if (!formForeground || source == null) return;
      final bytes = await _photos.pickProfile(source: source);
      if (mounted && formCurrent && bytes != null) {
        if (bytes.length > 3 * 1024 * 1024) {
          if (!formForeground) return;
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
      if (mounted && formForeground) cNotice(context, 'Rasm ochilmadi.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!formForeground ||
        _saving ||
        _picking ||
        !_form.currentState!.validate()) {
      return;
    }
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
      if (!mounted || !formForeground) return;
      if (widget.registration) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const CustomerHomePage()),
          (_) => false,
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      showSaveError(e);
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
  Widget build(BuildContext context) => !formCurrent
      ? unavailableForm
      : CustomerPage(
          title: widget.registration
              ? lt('Ro‘yxatdan o‘tish', 'Registration', 'Регистрация')
              : 'Profilni tahrirlash',
          bottom: cButton(
            widget.registration
                ? lt('Ro‘yxatdan o‘tish', 'Register', 'Зарегистрироваться')
                : 'Saqlash',
            _saving || _picking ? null : _save,
            id: widget.registration
                ? 'registerCustomer'
                : 'saveCustomerProfile',
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
                        lt(
                          'Rasmni olib tashlash',
                          'Remove photo',
                          'Удалить фото',
                        ),
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
  bool _current(BuildContext context) =>
      context.mounted &&
      store.isCurrentSession &&
      ModalRoute.of(context)?.isCurrent != false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, CustomerApi.sessionChanges]),
    builder: (context, _) => !store.isCurrentSession
        ? CustomerPage(
            title: 'Manzillarim',
            children: [
              Text(
                lt(
                  'Hisobingizga qayta kiring.',
                  'Sign in again.',
                  'Войдите снова.',
                ),
              ),
            ],
          )
        : CustomerPage(
            title: 'Manzillarim',
            bottom: cButton('Manzil qo‘shish', () {
              if (_current(context)) {
                cPush(context, CustomerAddressForm(store: store));
              }
            }, icon: Icons.add),
            children: [
              if (store.list('addresses').isEmpty)
                cCard(cText('Hozircha bo‘sh')),
              for (final a in store.list('addresses'))
                cCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cText(a['label'], bold: true, size: 19, translate: false),
                      cRow(
                        Icons.location_on_outlined,
                        a['address'],
                        translate: false,
                      ),
                      if ((a['apartment'] ?? '').toString().isNotEmpty)
                        cText(
                          "${lt('Kirish ko‘rsatmasi', 'Entry instructions', 'Как попасть внутрь')}: ${a['apartment']}",
                          size: 13,
                          translate: false,
                        ),
                      TextButton.icon(
                        onPressed: () {
                          if (_current(context)) {
                            cPush(
                              context,
                              CustomerAddressForm(store: store, address: a),
                            );
                          }
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(ct('Tahrirlash')),
                      ),
                    ],
                  ),
                  onTap: () {
                    if (!_current(context)) return;
                    if (select) {
                      Navigator.pop(context, a);
                    } else {
                      cPush(
                        context,
                        CustomerAddressForm(store: store, address: a),
                      );
                    }
                  },
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

class _CustomerAddressFormState
    extends _CustomerFormState<CustomerAddressForm> {
  @override
  CustomerStore get formStore => widget.store;
  @override
  Object? get formTarget => widget.address?['id'];
  late final int? _revision;
  late final _label = TextEditingController(
    text: widget.address?['label'] ?? lt('Uyim', 'Home', 'Дом'),
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
    if (!formForeground || _saving) return;
    final value = await pickCareLocation(context, _location);
    if (value != null && formCurrent) setState(() => _location = value);
  }

  Future<void> _delete() async {
    if (!formForeground || _saving) return;
    final address = widget.address;
    if (address == null) return;
    setState(() => _saving = true);
    try {
      final confirmed = await showOwnedDialog<bool>(
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(
            lt('Manzil o‘chirilsinmi?', 'Delete address?', 'Удалить адрес?'),
          ),
          content: Text(
            lt(
              'Bu manzil yangi bronlar uchun ro‘yxatdan o‘chiriladi.',
              'This address will be removed from the list for new bookings.',
              'Адрес будет удалён из списка для новых заказов.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(lt('Ortga', 'Back', 'Назад')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(lt('O‘chirish', 'Delete', 'Удалить')),
            ),
          ],
        ),
      );
      if (!formForeground || confirmed != true) return;
      await widget.store.update((data) {
        (data['addresses'] as List).removeWhere(
          (item) => item['id'] == address['id'],
        );
      }, expectedRevision: _revision);
      if (!formCurrent) return;
      if (widget.store
          .list('addresses')
          .any((item) => item['id'] == address['id'])) {
        throw StateError(
          lt(
            'Manzil o‘chirilmadi',
            'Address was not deleted',
            'Адрес не удалён',
          ),
        );
      }
      if (mounted && formForeground) Navigator.pop(context);
    } catch (e) {
      showSaveError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!formForeground || _saving) return;
    if (_location == null || _label.text.trim().isEmpty) {
      cNotice(context, 'Manzil va uning nomini kiriting.');
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
      if (mounted && formForeground) Navigator.pop(context);
    } catch (e) {
      showSaveError(e);
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
  Widget build(BuildContext context) => !formCurrent
      ? unavailableForm
      : CustomerPage(
          title: 'Manzilni belgilang',
          bottom: cButton('Saqlash', _saving ? null : _save, loading: _saving),
          children: [
            CareLocationPreview(location: _location, onTap: _map),
            cButton(
              'Xaritadan tanlash',
              _saving ? null : _map,
              secondary: true,
              icon: Icons.map_outlined,
            ),
            const SizedBox(height: 18),
            cField(_label, 'Manzil nomi'),
            cField(
              _flat,
              lt(
                'Xonadon va kirish ko‘rsatmasi (ixtiyoriy)',
                'Apartment and entry instructions (optional)',
                'Квартира и инструкции по входу (необязательно)',
              ),
            ),
            if (widget.address != null)
              cButton(
                lt('Manzilni o‘chirish', 'Delete address', 'Удалить адрес'),
                _saving ? null : _delete,
                secondary: true,
                icon: Icons.delete_outline,
              ),
          ],
        );
}

class CustomerSettingsPage extends StatefulWidget {
  const CustomerSettingsPage({super.key, required this.store});
  final CustomerStore store;
  @override
  State<CustomerSettingsPage> createState() => _CustomerSettingsPageState();
}

class _CustomerSettingsPageState extends State<CustomerSettingsPage>
    with RebuildOnSessionChange<CustomerSettingsPage> {
  final _session = CustomerApi.sessionVersion;
  final _api = CustomerApi.active;
  bool _current(CustomerStore source) =>
      mounted &&
      source.isCurrentSession &&
      identical(widget.store, source) &&
      CustomerApi.sessionVersion == _session &&
      identical(CustomerApi.active, _api);

  Future<void> _save(
    CustomerStore source,
    void Function(CJson) change, {
    String? language,
  }) async {
    if (!_current(source) ||
        source.busy ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    try {
      await source.update(change);
      // Account listeners can invalidate the session as the save finishes.
      if (!_current(source)) return;
      if (language != null) await AppLanguage.select(language);
    } catch (_) {
      if (mounted &&
          _current(source) &&
          ModalRoute.of(context)?.isCurrent != false) {
        cNotice(
          context,
          lt(
            'Amal bajarilmadi. Qayta urinib ko‘ring.',
            'Action failed. Please retry.',
            'Не удалось выполнить. Повторите.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([AppLanguage.current, widget.store]),
    builder: (context, _) {
      final source = widget.store;
      if (!_current(source)) {
        return CustomerPage(
          title: 'Til',
          children: [
            Text(
              lt(
                'Hisobingizga qayta kiring.',
                'Sign in again.',
                'Войдите снова.',
              ),
            ),
          ],
        );
      }
      return CustomerPage(
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
                onTap: source.busy
                    ? null
                    : () => _save(
                        source,
                        (d) => d['language'] = l.$1,
                        language: l.$1,
                      ),
              ),
            ),
          if (source.busy) const LinearProgressIndicator(),
          cText('Bildirishnomalar', size: 20, bold: true),
          const SizedBox(height: 12),
          for (final n in [
            ('orders', 'Buyurtmalar'),
            ('chat', 'Chatlar'),
            ('video', 'Video hisobotlar'),
          ])
            cCard(
              SwitchListTile(
                key: ValueKey('customerNotice-${n.$1}'),
                title: Text(ct(n.$2)),
                value: source.notifications[n.$1] as bool,
                onChanged: source.busy
                    ? null
                    : (v) => _save(
                        source,
                        (d) => (d['notifications'] as Map)[n.$1] = v,
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
      );
    },
  );
}

class CustomerHelpPage extends StatelessWidget {
  const CustomerHelpPage({super.key, required this.store});
  final CustomerStore store;
  @override
  Widget build(BuildContext context) => SupportPage(api: store.api);
}
