import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/localization/app_language.dart';
import '../../listings/presentation/listing_style.dart';

class SitterProfilePage extends StatefulWidget {
  const SitterProfilePage({
    super.key,
    required this.section,
    required this.firstName,
    required this.lastName,
    this.avatar,
  });
  final int section;
  final String firstName, lastName;
  final Uint8List? avatar;
  @override
  State<SitterProfilePage> createState() => _SitterProfilePageState();
}

class _SitterProfilePageState extends State<SitterProfilePage> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.firstName);
  late final _last = TextEditingController(text: widget.lastName);
  final _years = TextEditingController();
  final _about = TextEditingController();
  final _message = TextEditingController();
  Uint8List? _photo;
  bool _loading = true,
      _saving = false,
      _orders = true,
      _chat = true,
      _care = true;
  List<bool> _days = [true, true, true, true, true, false, false];
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0),
      _end = const TimeOfDay(hour: 18, minute: 0);
  String tr(String uz, String en, String ru) => lt(uz, en, ru);
  String get title => [
    tr('Profilni tahrirlash', 'Edit profile', 'Редактировать профиль'),
    tr('Ish jadvali', 'Availability', 'График работы'),
    tr('Mijozlar fikrlari', 'Client reviews', 'Отзывы клиентов'),
    tr('Bildirishnomalar', 'Notifications', 'Уведомления'),
    tr('Yordam', 'Help', 'Помощь'),
    tr('Til', 'Language', 'Язык'),
  ][widget.section];
  @override
  void initState() {
    super.initState();
    _photo = widget.avatar;
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _years.text = p.getString('mock.profile.years') ?? '';
      _about.text = p.getString('mock.profile.about') ?? '';
      final days = p.getStringList('mock.profile.days');
      if (days?.length == 7) _days = days!.map((v) => v == 'true').toList();
      _orders = p.getBool('mock.notify.orders') ?? true;
      _chat = p.getBool('mock.notify.chat') ?? true;
      _care = p.getBool('mock.notify.care') ?? true;
      final a = p.getInt('mock.profile.start') ?? 540;
      final b = p.getInt('mock.profile.end') ?? 1080;
      _start = TimeOfDay(hour: a ~/ 60, minute: a % 60);
      _end = TimeOfDay(hour: b ~/ 60, minute: b % 60);
    } catch (_) {
      if (mounted) {
        _notice(
          tr(
            'Yuklanmadi. Qayta urinib ko‘ring.',
            'Could not load. Please retry.',
            'Не удалось загрузить. Повторите.',
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _notice(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? true)) return;
    if (widget.section == 1 &&
        _days.any((v) => v) &&
        _start.hour * 60 + _start.minute >= _end.hour * 60 + _end.minute) {
      _notice(
        tr(
          'Tugash vaqti boshlanishdan keyin bo‘lsin.',
          'End time must be after start time.',
          'Время окончания должно быть позже начала.',
        ),
      );
      return;
    }
    if (widget.section == 4) {
      _notice(
        tr(
          'Murojaatlar xizmati hali ulanmagan.',
          'Support is not connected yet.',
          'Служба поддержки пока не подключена.',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final p = await SharedPreferences.getInstance();
      final results = <bool>[];
      if (widget.section == 0) {
        results.add(
          await p.setString('mock.profile.first', _first.text.trim()),
        );
        results.add(await p.setString('mock.profile.last', _last.text.trim()));
        results.add(
          await p.setString('mock.profile.years', _years.text.trim()),
        );
        results.add(
          await p.setString('mock.profile.about', _about.text.trim()),
        );
        if (_photo != null) {
          results.add(
            await p.setString('mock.profile.avatar', base64Encode(_photo!)),
          );
        }
      } else if (widget.section == 1) {
        results.add(
          await p.setStringList(
            'mock.profile.days',
            _days.map((v) => '$v').toList(),
          ),
        );
        results.add(
          await p.setInt(
            'mock.profile.start',
            _start.hour * 60 + _start.minute,
          ),
        );
        results.add(
          await p.setInt('mock.profile.end', _end.hour * 60 + _end.minute),
        );
      } else if (widget.section == 3) {
        results.add(await p.setBool('mock.notify.orders', _orders));
        results.add(await p.setBool('mock.notify.chat', _chat));
        results.add(await p.setBool('mock.notify.care', _care));
      }
      if (results.any((ok) => !ok)) throw StateError('Save failed');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        _notice(
          tr(
            'Saqlanmadi. Qayta urinib ko‘ring.',
            'Could not save. Retry.',
            'Не удалось сохранить. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 80,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      if (mounted) {
        _notice(
          tr(
            'Rasm ochilmadi.',
            'Could not open photo.',
            'Не удалось открыть фото.',
          ),
        );
      }
    }
  }

  Widget field(
    TextEditingController controller,
    String label,
    String key, {
    int lines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: listingSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return tr('To‘ldiring', 'Required', 'Обязательное поле');
        }
        if (number &&
            (int.tryParse(value) == null ||
                int.parse(value) < 0 ||
                int.parse(value) > 80)) {
          return tr(
            '0–80 oralig‘ida kiriting',
            'Enter 0–80',
            'Введите от 0 до 80',
          );
        }
        return null;
      },
    ),
  );
  Widget tile(Widget child) => Card(
    color: listingSurface,
    margin: const EdgeInsets.only(bottom: 12),
    child: child,
  );
  @override
  void dispose() {
    for (final c in [_first, _last, _years, _about, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppLanguage.current,
    builder: (context, language, _) => MomiqScaffold(
      backgroundColor: listingBackground,
      appBar: AppBar(backgroundColor: listingBackground, title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (widget.section == 0) ...[
                      Center(
                        child: InkWell(
                          onTap: _saving ? null : _pickPhoto,
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 46,
                                backgroundColor: listingSurface,
                                backgroundImage: _photo == null
                                    ? null
                                    : MemoryImage(_photo!),
                                child: _photo == null
                                    ? const Icon(Icons.person_outline, size: 42)
                                    : null,
                              ),
                              TextButton.icon(
                                onPressed: _saving ? null : _pickPhoto,
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(
                                  tr(
                                    'Rasmni almashtirish',
                                    'Change photo',
                                    'Изменить фото',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      field(
                        _first,
                        tr('Ism', 'First name', 'Имя'),
                        'profileFirst',
                      ),
                      field(
                        _last,
                        tr('Familiya', 'Last name', 'Фамилия'),
                        'profileLast',
                      ),
                      field(
                        _years,
                        tr(
                          'Tajriba yili',
                          'Years of experience',
                          'Стаж в годах',
                        ),
                        'profileYears',
                        number: true,
                      ),
                      field(
                        _about,
                        tr(
                          'Tajriba haqida',
                          'About your experience',
                          'Об опыте',
                        ),
                        'profileAbout',
                        lines: 4,
                      ),
                    ],
                    if (widget.section == 1) ...[
                      Text(
                        tr(
                          'Qaysi kunlari ishlaysiz?',
                          'Which days do you work?',
                          'В какие дни вы работаете?',
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < 7; i++)
                        tile(
                          SwitchListTile(
                            key: ValueKey('workDay-$i'),
                            title: Text(
                              [
                                tr('Dushanba', 'Monday', 'Понедельник'),
                                tr('Seshanba', 'Tuesday', 'Вторник'),
                                tr('Chorshanba', 'Wednesday', 'Среда'),
                                tr('Payshanba', 'Thursday', 'Четверг'),
                                tr('Juma', 'Friday', 'Пятница'),
                                tr('Shanba', 'Saturday', 'Суббота'),
                                tr('Yakshanba', 'Sunday', 'Воскресенье'),
                              ][i],
                            ),
                            value: _days[i],
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _days[i] = v),
                          ),
                        ),
                      for (final start in [true, false])
                        tile(
                          ListTile(
                            title: Text(
                              start
                                  ? tr('Boshlanish', 'Start', 'Начало')
                                  : tr('Tugash', 'End', 'Окончание'),
                            ),
                            trailing: Text(
                              (start ? _start : _end).format(context),
                            ),
                            onTap: _saving
                                ? null
                                : () async {
                                    final value = await showTimePicker(
                                      context: context,
                                      initialTime: start ? _start : _end,
                                    );
                                    if (value != null && mounted) {
                                      setState(() {
                                        if (start) {
                                          _start = value;
                                        } else {
                                          _end = value;
                                        }
                                      });
                                    }
                                  },
                          ),
                        ),
                    ],
                    if (widget.section == 2)
                      Text(
                        tr(
                          'Hali sharh yo‘q',
                          'No reviews yet',
                          'Отзывов пока нет',
                        ),
                      ),
                    if (widget.section == 3) ...[
                      tile(
                        SwitchListTile(
                          key: const ValueKey('notifyOrders'),
                          title: Text(
                            tr(
                              'Yangi buyurtmalar',
                              'New bookings',
                              'Новые заказы',
                            ),
                          ),
                          value: _orders,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _orders = v),
                        ),
                      ),
                      tile(
                        SwitchListTile(
                          title: Text(
                            tr(
                              'Chat xabarlari',
                              'Chat messages',
                              'Сообщения чата',
                            ),
                          ),
                          value: _chat,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _chat = v),
                        ),
                      ),
                      tile(
                        SwitchListTile(
                          title: Text(
                            tr(
                              'Parvarish eslatmalari',
                              'Care reminders',
                              'Напоминания об уходе',
                            ),
                          ),
                          value: _care,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _care = v),
                        ),
                      ),
                      Text(
                        tr(
                          'Push xabarlar hali ulanmagan.',
                          'Push notifications are not connected yet.',
                          'Push-уведомления пока не подключены.',
                        ),
                      ),
                    ],
                    if (widget.section == 4) ...[
                      tile(
                        ExpansionTile(
                          title: Text(
                            tr(
                              'E’lon qanday yaratiladi?',
                              'How do I create a listing?',
                              'Как создать объявление?',
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                tr(
                                  'E’lon berish bo‘limida xizmatni tanlang va majburiy maydonlarni to‘ldiring.',
                                  'Choose a service in Listings and fill in the required fields.',
                                  'Выберите услугу в объявлениях и заполните обязательные поля.',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      tile(
                        ExpansionTile(
                          title: Text(
                            tr(
                              'Parvarish vazifalari qayerda?',
                              'Where are care tasks?',
                              'Где задачи по уходу?',
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                tr(
                                  'Bosh sahifada Bugungi parvarish kartasini bosing.',
                                  'Tap Today’s care on the home page.',
                                  'Нажмите «Уход сегодня» на главной.',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      field(
                        _message,
                        tr('Murojaatingiz', 'Your request', 'Ваше обращение'),
                        'supportMessage',
                        lines: 4,
                      ),
                    ],
                    if (widget.section == 5) ...[
                      for (final item in [
                        ('uz', 'O‘zbekcha'),
                        ('ru', 'Русский'),
                        ('en', 'English'),
                      ])
                        tile(
                          ListTile(
                            key: ValueKey('language-${item.$1}'),
                            title: Text(item.$2),
                            trailing: Icon(
                              language == item.$1
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: listingGold,
                            ),
                            onTap: () async {
                              await AppLanguage.select(item.$1);
                            },
                          ),
                        ),
                    ],
                    if ([0, 1, 3, 4].contains(widget.section)) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const ValueKey('saveProfileSection'),
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: listingGold,
                          minimumSize: const Size(0, 50),
                        ),
                        child: Text(
                          _saving
                              ? tr('Saqlanmoqda…', 'Saving…', 'Сохранение…')
                              : tr('Saqlash', 'Save', 'Сохранить'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    ),
  );
}
