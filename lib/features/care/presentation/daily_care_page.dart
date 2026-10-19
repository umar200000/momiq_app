import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import '../../onboarding/presentation/widgets/onboarding_shell.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../listings/presentation/listing_style.dart';
import '../../../core/theme/app_colors.dart';

// Preview care instructions until accepted bookings supply client care plans.
class CarePet {
  const CarePet(
    this.id,
    this.name,
    this.cat,
    this.meals, {
    this.medicine = false,
    this.walk = true,
  });
  final String id, name;
  final bool cat, medicine, walk;
  final List<String> meals;
}

const previewCarePets = [
  CarePet('MQ-0242', 'Momi', true, ['08:00', '13:00', '19:00'], medicine: true),
  CarePet('MQ-0241', 'Boni', false, ['08:00', '13:00', '19:00']),
];

class DailyCarePage extends StatefulWidget {
  const DailyCarePage({super.key, this.pets = previewCarePets, this.clock});
  final List<CarePet> pets;
  final DateTime Function()? clock;
  @override
  State<DailyCarePage> createState() => _DailyCarePageState();
}

class _DailyCarePageState extends State<DailyCarePage>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _loading = true, _busy = false;
  String _day = '';
  Map<String, dynamic> _done = {};
  Timer? _timer;
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  String dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';
  CarePet get pet => widget.pets[_index];
  String taskKey(CarePet p, String task) => '${p.id}/$task';
  int total(CarePet p) =>
      p.meals.length + (p.medicine ? 1 : 0) + (p.walk ? 1 : 0) + 2;
  int completed(CarePet p) =>
      _done.keys.where((key) => key.startsWith('${p.id}/')).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshDate());
  }

  void _refreshDate() {
    if (!mounted || _busy) return;
    if (_day != dateKey(_now)) {
      _load();
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDate();
  }

  Future<void> _load() async {
    final day = dateKey(_now);
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('momiq.care.$day');
      final value = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (mounted) {
        setState(() {
          _day = day;
          _done = value;
        });
      }
    } catch (_) {
      if (mounted) _notice('Vazifalarni yuklab bo‘lmadi. Qayta ochib ko‘ring.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
  Future<bool> _persist(Map<String, dynamic> next) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('momiq.care.$_day', jsonEncode(next))) {
      throw StateError('Save failed');
    }
    if (mounted) setState(() => _done = next);
    return true;
  }

  Future<void> _toggle(String task) async {
    if (_busy) return;
    if (_day != dateKey(_now)) {
      await _load();
      return;
    }
    setState(() => _busy = true);
    try {
      final key = taskKey(pet, task);
      final next = Map<String, dynamic>.from(_done);
      if (next.containsKey(key)) {
        next.remove(key);
      } else {
        next[key] = _now.toIso8601String();
      }
      await _persist(next);
    } catch (_) {
      if (mounted) _notice('Saqlanmadi. Qayta urinib ko‘ring.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool videoTime(bool morning) =>
      morning ? _now.hour >= 6 && _now.hour < 12 : _now.hour >= 18;
  Future<void> _video(bool morning) async {
    if (_busy) return;
    if (!videoTime(morning)) {
      _notice(
        morning
            ? 'Video 06:00–12:00 oralig‘ida qo‘shiladi.'
            : 'Video 18:00–00:00 oralig‘ida qo‘shiladi.',
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video olish'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Galereyadan tanlash'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final selectedPet = pet;
    final day = _day;
    setState(() => _busy = true);
    File? stored;
    try {
      final video = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 2),
      );
      if (video == null || !mounted) return;
      if (dateKey(_now) != day || !videoTime(morning)) {
        _notice('Video uchun belgilangan vaqt tugadi.');
        return;
      }
      final directory = await getApplicationSupportDirectory();
      final folder = await Directory(
        '${directory.path}/care_videos',
      ).create(recursive: true);
      final extension = video.path.toLowerCase().endsWith('.mov')
          ? 'mov'
          : 'mp4';
      stored = await File(video.path).copy(
        '${folder.path}/${selectedPet.id}_${morning ? 'am' : 'pm'}_${_now.microsecondsSinceEpoch}.$extension',
      );
      final next = Map<String, dynamic>.from(_done);
      next[taskKey(selectedPet, morning ? 'video-am' : 'video-pm')] = {
        'path': stored.path,
        'time': _now.toIso8601String(),
      };
      await _persist(next);
      stored = null;
      if (mounted) _notice('Video qurilmaga saqlandi.');
    } catch (_) {
      if (stored != null && await stored.exists()) await stored.delete();
      if (mounted) {
        _notice('Video saqlanmadi. Ruxsatlarni tekshirib, qayta urining.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshDate();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget label(
    String value, {
    double size = 15,
    bool bold = false,
    Color? color,
  }) => Text(
    value,
    style: profileText(
      size,
      bold: bold,
    ).copyWith(color: color ?? AppColors.chocolate),
  );
  Widget card(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: listingSurface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Material(color: Colors.transparent, child: child),
  );
  Widget avatar(CarePet p, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: Container(
      color: const Color(0xFFF5E6CA),
      child: Image.asset(
        'assets/images/service_${p.cat ? 'cat' : 'dog'}.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    ),
  );
  Widget heading(IconData icon, String title) => Row(
    children: [
      CircleAvatar(
        backgroundColor: const Color(0xFFF6E6C8),
        foregroundColor: AppColors.brown,
        child: Icon(icon),
      ),
      const SizedBox(width: 12),
      Expanded(child: label(title, size: 19, bold: true)),
    ],
  );
  Widget task(String id, String title, String subtitle) {
    final checked = _done.containsKey(taskKey(pet, id));
    return CheckboxListTile(
      key: ValueKey('care-$id'),
      value: checked,
      onChanged: _busy ? null : (_) => _toggle(id),
      activeColor: listingGold,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: label(title, bold: true),
      subtitle: label(subtitle, size: 12, color: AppColors.brown),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget videoCard(bool morning) {
    final saved = _done[taskKey(pet, morning ? 'video-am' : 'video-pm')];
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: listingBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
            morning ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
            morning ? 'Ertalabki video' : 'Kechki video',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 4, bottom: 14),
            child: label(
              morning ? '06:00 – 12:00' : '18:00 – 00:00',
              color: AppColors.brown,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: saved == null
                  ? const Color(0xFFF1EADF)
                  : const Color(0xFFEAF0DF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  saved == null
                      ? Icons.videocam_outlined
                      : Icons.check_circle_outline,
                  size: 34,
                  color: saved == null
                      ? AppColors.brown
                      : const Color(0xFF51713D),
                ),
                const SizedBox(height: 8),
                label(
                  saved == null
                      ? 'Video hali qo‘shilmagan'
                      : 'Qurilmaga saqlandi',
                  size: 13,
                ),
              ],
            ),
          ),
          if (saved == null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey(morning ? 'video-am' : 'video-pm'),
                onPressed: _busy ? null : () => _video(morning),
                icon: const Icon(Icons.video_call_outlined),
                label: const Text('Video qo‘shish'),
                style: FilledButton.styleFrom(
                  backgroundColor: listingGold,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MomiqScaffold(
    backgroundColor: listingBackground,
    appBar: AppBar(
      backgroundColor: listingBackground,
      foregroundColor: AppColors.chocolate,
      centerTitle: true,
      title: label('Bugungi parvarish', size: 21, bold: true),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : widget.pets.isEmpty
        ? Center(child: label('Hozircha parvarishdagi hayvonlar yo‘q'))
        : SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              children: [
                Center(
                  child: label(
                    '${_now.day}.${_now.month.toString().padLeft(2, '0')}.${_now.year} · Bugun',
                    color: AppColors.brown,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.pets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final p = widget.pets[index];
                      return Semantics(
                        selected: _index == index,
                        child: InkWell(
                          key: ValueKey('care-pet-${p.id}'),
                          onTap: _busy
                              ? null
                              : () => setState(() => _index = index),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 166,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _index == index
                                  ? const Color(0xFFF8EBCD)
                                  : listingSurface,
                              border: Border.all(
                                color: _index == index
                                    ? listingGold
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                avatar(p, 52),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      label(p.name, bold: true),
                                      label(
                                        p.cat ? 'Mushuk' : 'It',
                                        size: 12,
                                        color: AppColors.brown,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('${pet.name} uchun bugungi vazifalar', bold: true),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: label(
                          '${completed(pet)} / ${total(pet)} bajarildi',
                          size: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: completed(pet) / total(pet),
                          minHeight: 9,
                          color: listingGold,
                          backgroundColor: listingBorder,
                        ),
                      ),
                    ],
                  ),
                ),
                card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading(Icons.rice_bowl_outlined, 'Ovqatlantirish'),
                      const SizedBox(height: 8),
                      label(
                        'Mijoz belgilagan: kuniga ${pet.meals.length} mahal',
                        size: 12,
                        color: AppColors.brown,
                      ),
                      const SizedBox(height: 10),
                      for (var i = 0; i < pet.meals.length; i++)
                        task(
                          'meal-$i',
                          ['Ertalabki ovqat', 'Tushlik', 'Kechki ovqat'][i % 3],
                          pet.meals[i],
                        ),
                    ],
                  ),
                ),
                if (pet.medicine)
                  card(
                    Column(
                      children: [
                        heading(Icons.medication_outlined, 'Dori berish'),
                        task(
                          'medicine',
                          'Ertalabki dori',
                          '09:00 · Mijoz ko‘rsatmasi bo‘yicha',
                        ),
                      ],
                    ),
                  ),
                if (pet.walk)
                  card(
                    Column(
                      children: [
                        heading(Icons.pets_outlined, 'Sayr'),
                        task('walk', 'Kechki sayr', '18:00 · 20 daqiqa'),
                      ],
                    ),
                  ),
                card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Video hisobotlar', size: 21, bold: true),
                      const SizedBox(height: 8),
                      label(
                        'Kuniga 2 ta · Majburiy',
                        color: listingGold,
                        bold: true,
                      ),
                      const SizedBox(height: 8),
                      label(
                        'Har bir hayvon uchun alohida video qo‘shing.',
                        size: 13,
                        color: AppColors.brown,
                      ),
                      videoCard(true),
                      videoCard(false),
                      const SizedBox(height: 14),
                      label(
                        'Video saqlangach, vazifa avtomatik belgilanadi. Hozircha videolar faqat shu qurilmada saqlanadi.',
                        size: 12,
                        color: AppColors.brown,
                      ),
                    ],
                  ),
                ),
                card(
                  Column(
                    children: [
                      for (final p in widget.pets)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              avatar(p, 42),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    label(
                                      '${p.name}: ${completed(p)} / ${total(p)} bajarildi',
                                      size: 13,
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: completed(p) / total(p),
                                      color: listingGold,
                                      backgroundColor: listingBorder,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
  );
}
