import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/auth_features.dart';
import '../../../listings/data/listing_store.dart';
import '../../../listings/presentation/listing_style.dart';
import '../../../home/presentation/pages/sitter_home_page.dart';
import '../../../../core/localization/app_language.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/profile_photo_source.dart';
import '../widgets/onboarding_shell.dart';

class SitterRegistrationPage extends StatefulWidget {
  const SitterRegistrationPage({super.key, this.photoSource});
  final ProfilePhotoSource? photoSource;
  @override
  State<SitterRegistrationPage> createState() => _SitterRegistrationPageState();
}

class _SitterRegistrationPageState extends State<SitterRegistrationPage> {
  late final ProfilePhotoSource _photos =
      widget.photoSource ?? ProfilePhotoSource();
  final _experience = TextEditingController();
  final _identityForm = GlobalKey<FormState>();
  final _first = TextEditingController(text: myIdEnabled ? 'Hoji' : '');
  final _last = TextEditingController(text: myIdEnabled ? 'Sherhojiyiv' : '');
  final List<Uint8List> _home = [];
  Uint8List? _avatar;
  int? _years;
  HousingType _housing = ListingStore.instance.housing;
  bool _housingTouched = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    ListingStore.instance
        .load()
        .then((_) {
          if (mounted && !_housingTouched) {
            setState(() => _housing = ListingStore.instance.housing);
          }
        })
        .catchError((Object _) {
          // Submission reports storage failures; do not overwrite saved data.
        });
  }

  final bool _submitted = false;
  bool _picking = false;
  bool _choosingPhoto = false;
  final _sectionKeys = List.generate(4, (_) => GlobalKey());
  List<bool> get _valid => [
    _avatar != null,
    _years != null,
    _experience.text.trim().isNotEmpty,
    _home.length >= 3 && _home.length <= 9,
  ];
  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _pick(bool profile) async {
    if (_picking || _choosingPhoto || (!profile && _home.length >= 9)) return;
    setState(() => _choosingPhoto = true);
    FocusScope.of(context).unfocus();
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: formSurface,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('photoGallery'),
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.brown,
                ),
                title: Text(
                  context.tr('Galereya'),
                  style: profileText(17, bold: true),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              ListTile(
                key: const ValueKey('photoCamera'),
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.brown,
                ),
                title: Text(
                  context.tr('Kamera'),
                  style: profileText(17, bold: true),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
      if (!mounted || source == null) return;
      setState(() {
        _choosingPhoto = false;
        _picking = true;
      });
      if (profile) {
        final image = await _photos.pickProfile(source: source);
        if (mounted && image != null) setState(() => _avatar = image);
      } else {
        final images = await _photos.pickHome(9 - _home.length, source: source);
        if (mounted) {
          setState(() => _home.addAll(images.take(9 - _home.length)));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Rasmni ochib bo‘lmadi. Kamera yoki galereya ruxsatini tekshirib, qayta urinib ko‘ring.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
          _choosingPhoto = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_identityForm.currentState?.validate() ?? false)) {
      await Scrollable.ensureVisible(
        _identityForm.currentContext!,
        duration: const Duration(milliseconds: 250),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await ListingStore.instance.setHousing(_housing);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('mock.profile.first', _first.text.trim()) ||
          !await prefs.setString('mock.profile.last', _last.text.trim())) {
        throw StateError('Profile save failed');
      }
      if (_avatar != null &&
          !await prefs.setString(
            'mock.profile.avatar',
            base64Encode(_avatar!),
          )) {
        throw StateError('Photo save failed');
      }
      if (!mounted) return;
      // Other profile fields remain optional during the MVP preview.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => SitterHomePage(
            avatar: _avatar,
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
          ),
        ),
        (_) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(problemText(ListingProblem.storage))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration({
    String? hint,
    bool error = false,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    suffixIcon: suffix,
    filled: true,
    fillColor: formSurface,
    hintStyle: profileText(
      14,
    ).copyWith(color: AppColors.brown.withValues(alpha: .65)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: error ? Colors.red.shade700 : formBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: error ? Colors.red.shade700 : formBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: error ? Colors.red.shade700 : AppColors.gold,
        width: 1.7,
      ),
    ),
  );

  Widget _label(String text, {String? helper}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr(text), style: profileText(18, bold: true)),
        if (helper != null) ...[
          const SizedBox(height: 5),
          Text(context.tr(helper), style: profileText(13)),
        ],
      ],
    ),
  );

  Widget _section(int index, Widget child) => Container(
    key: _sectionKeys[index],
    margin: const EdgeInsets.only(bottom: 24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: _submitted && !_valid[index]
          ? Border.all(color: Colors.red.shade700)
          : null,
    ),
    padding: const EdgeInsets.all(2),
    child: child,
  );

  @override
  Widget build(BuildContext context) => OnboardingShell(
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Ro‘yxatdan o‘tish'),
                style: profileText(28, bold: true),
              ),
              const SizedBox(height: 24),
              _section(
                0,
                Center(
                  child: Column(
                    children: [
                      Semantics(
                        label: context.tr(
                          'Profil rasmini yuklash yoki almashtirish',
                        ),
                        button: true,
                        child: InkWell(
                          key: const ValueKey('profileUpload'),
                          onTap: _picking ? null : () => _pick(true),
                          borderRadius: BorderRadius.circular(60),
                          child: Stack(
                            children: [
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFDBD0C5),
                                  border: Border.all(
                                    color: _submitted && _avatar == null
                                        ? Colors.red.shade700
                                        : formBorder,
                                  ),
                                ),
                                child: _avatar == null
                                    ? const Icon(
                                        Icons.person_outline_rounded,
                                        size: 48,
                                        color: AppColors.brown,
                                      )
                                    : ClipOval(
                                        child: Image.memory(
                                          _avatar!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.gold,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_outlined,
                                    size: 20,
                                    color: AppColors.chocolate,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('Profil rasmi'),
                        style: profileText(16, bold: true),
                      ),
                    ],
                  ),
                ),
              ),
              Form(
                key: _identityForm,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _identity('Ism', _first, 'sitterFirst')),
                    const SizedBox(width: 12),
                    Expanded(child: _identity('Familiya', _last, 'sitterLast')),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(
                lt('Uy turi', 'Home type', 'Тип жилья'),
                style: profileText(18, bold: true),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final type in [
                    HousingType.house,
                    HousingType.apartment,
                  ]) ...[
                    if (type == HousingType.apartment)
                      const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        selected: _housing == type,
                        button: true,
                        child: Material(
                          color: _housing == type
                              ? const Color(0xFFFFECCE)
                              : formSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                            side: BorderSide(
                              color: _housing == type
                                  ? AppColors.gold
                                  : listingBorder,
                              width: _housing == type ? 1.4 : 1,
                            ),
                          ),
                          child: InkWell(
                            key: ValueKey('housing-${type.name}'),
                            borderRadius: BorderRadius.circular(9),
                            onTap: () => setState(() {
                              _housingTouched = true;
                              _housing = type;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 13,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    type == HousingType.house
                                        ? Icons.home_outlined
                                        : Icons.apartment_outlined,
                                    color: AppColors.brown,
                                    size: 27,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      type == HousingType.house
                                          ? lt('Hovli', 'House', 'Дом')
                                          : lt(
                                              'Kvartira',
                                              'Apartment',
                                              'Квартира',
                                            ),
                                      style: profileText(12, bold: true),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _housing == type
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 20,
                                    color: _housing == type
                                        ? AppColors.gold
                                        : formBorder,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 26),
              _section(
                1,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context.tr('Tajribangiz')),
                    TextField(
                      key: const ValueKey('experienceYears'),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      style: profileText(15),
                      decoration: _decoration(
                        hint: context.tr('Necha yildan beri?'),
                        error: _submitted && _years == null,
                      ).copyWith(suffixText: context.tr('yil')),
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: (value) =>
                          setState(() => _years = int.tryParse(value)),
                    ),
                  ],
                ),
              ),
              _section(
                2,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context.tr('Tajribangiz haqida')),
                    TextField(
                      key: const ValueKey('experienceDetails'),
                      controller: _experience,
                      minLines: 4,
                      maxLines: 7,
                      maxLength: 1500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _decoration(
                        hint: context.tr(
                          'Hayvonlarga qanday g‘amxo‘rlik qilasiz?',
                        ),
                        error: _submitted && _experience.text.trim().isEmpty,
                      ),
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              _section(
                3,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context.tr('Uy rasmlari'), helper: null),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: math.max(3, math.min(9, _home.length + 1)),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemBuilder: (context, index) => index < _home.length
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.memory(
                                    _home[index],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton.filled(
                                    key: ValueKey('removeHome-$index'),
                                    tooltip: context.tr('Rasmni olib tashlash'),
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.chocolate
                                          .withValues(alpha: .75),
                                      minimumSize: const Size(40, 40),
                                    ),
                                    onPressed: () =>
                                        setState(() => _home.removeAt(index)),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Material(
                              color: formSurface,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                key: ValueKey('homeUpload-$index'),
                                borderRadius: BorderRadius.circular(14),
                                onTap: _picking ? null : () => _pick(false),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: formBorder),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: AppColors.brown,
                                        size: 30,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${index + 1}',
                                        style: profileText(13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          context
                              .tr('photoTotal')
                              .replaceAll('{count}', _home.length.toString()),
                          key: const ValueKey('photoCount'),
                          style: profileText(13),
                        ),
                        const Spacer(),
                        if (_picking)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.gold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: formBorder),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 19,
                    color: AppColors.brown,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr(
                        'Ism va familiyani kiriting. Qolgan maydonlarni keyinroq to‘ldirishingiz mumkin.',
                      ),
                      style: profileText(13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ProfileButton(
                key: const ValueKey('registerSubmit'),
                label: context.tr('Ro‘yxatdan o‘tish'),
                onPressed: _picking || _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _identity(String label, TextEditingController controller, String id) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr(label), style: profileText(14, bold: true)),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey(id),
            controller: controller,
            readOnly: myIdEnabled,
            textCapitalization: TextCapitalization.words,
            autofillHints: [
              id == 'sitterFirst'
                  ? AutofillHints.givenName
                  : AutofillHints.familyName,
            ],
            validator: (value) => value == null || value.trim().isEmpty
                ? lt('Kiriting', 'Required', 'Заполните')
                : null,
            style: profileText(14, bold: true),
            decoration: _decoration(
              hint: context.tr(label),
              suffix: myIdEnabled
                  ? const Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                      color: AppColors.brown,
                    )
                  : null,
            ),
          ),
        ],
      );
}
