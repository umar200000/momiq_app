import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../data/booking_video_controller.dart';

class BookingVideosPage extends StatefulWidget {
  const BookingVideosPage({
    super.key,
    required this.api,
    required this.bookingId,
    this.controller,
  });
  final CustomerApi api;
  final String bookingId;
  final BookingVideoController? controller;
  @override
  State<BookingVideosPage> createState() => _BookingVideosPageState();
}

class _BookingVideosPageState extends State<BookingVideosPage>
    with WidgetsBindingObserver {
  late final c =
      widget.controller ?? BookingVideoController(widget.api, widget.bookingId);
  Timer? timer;
  bool foreground = true, picking = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.load();
    timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  void refresh() {
    if (mounted &&
        foreground &&
        !picking &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      c.load(
        day: c.data?['day'] == c.data?['policy']['today']
            ? null
            : c.data?['day'],
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> pick(String pet, String slot) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(lt('Video yozish', 'Record video', 'Записать видео')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(
                lt(
                  'Galereyadan tanlash',
                  'Choose from gallery',
                  'Выбрать из галереи',
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted || !c.canSelect(pet, slot)) return;
    setState(() => picking = true);
    try {
      final file = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null || !mounted || !c.live) return;
      if (await file.length() > 32 * 1024 * 1024) {
        throw FormatException(
          lt(
            'Video 32 MiB dan oshmasin. 1080p yoki kichikroq video tanlang.',
            'Choose a video under 32 MiB, at 1080p or lower.',
            'Выберите видео до 32 МиБ, не выше 1080p.',
          ),
        );
      }
      await c.select(pet, slot, await file.readAsBytes());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> changeDay() async {
    final last = DateTime.parse(c.data!['policy']['today']);
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(c.data!['day']),
      firstDate: DateTime(2020),
      lastDate: last,
    );
    if (selected != null && mounted) {
      await c.load(day: selected.toIso8601String().substring(0, 10));
    }
  }

  Future<void> discard() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          lt(
            'Qoralama tozalansinmi?',
            'Clear this draft?',
            'Очистить черновик?',
          ),
        ),
        content: Text(
          lt(
            'Bu faqat telefondagi qoralamani o‘chiradi. Serverga yetib borgan video saqlanadi; ro‘yxat yangilanadi.',
            'Only the local draft is removed. A video already received by the server remains; the list will refresh.',
            'Удалится только черновик на телефоне. Полученное сервером видео останется; список обновится.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Qaytish', 'Back', 'Назад')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(lt('Tozalash', 'Clear', 'Очистить')),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await c.discard();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Video hisobotlar', 'Video reports', 'Видеоотчёты')),
    ),
    body: ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final data = c.data;
        final locked = c.busy || picking || !c.live;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              lt(
                'Toshkent vaqti: ertalab 07:00–11:00, kechqurun 18:00–22:00. Har video 10–60 soniya, 32 MiB gacha, 1080p yoki kichikroq.',
                'Tashkent time: 07:00–11:00 and 18:00–22:00. Each video: 10–60 seconds, up to 32 MiB, 1080p or lower.',
                'Время Ташкента: 07:00–11:00 и 18:00–22:00. Видео: 10–60 секунд, до 32 МиБ, не выше 1080p.',
              ),
            ),
            const SizedBox(height: 12),
            if (c.busy)
              LinearProgressIndicator(
                value: c.uploading && c.progress < 1 ? c.progress : null,
              ),
            if (c.error != null)
              Text(
                '${c.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextButton(
              onPressed: locked ? null : refresh,
              child: Text(lt('Yangilash', 'Refresh', 'Обновить')),
            ),
            if (c.pending != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        lt(
                          'Video qoralamasi saqlangan. Server tasdiqlamaguncha yuborilgan deb hisoblanmaydi.',
                          'Video draft saved. It is submitted only after the server confirms it.',
                          'Черновик сохранён. Отправка завершится после подтверждения сервера.',
                        ),
                      ),
                      Text(
                        '${c.pending!['day']} · ${c.pending!['slot'] == 'morning' ? lt('Ertalab', 'Morning', 'Утро') : lt('Kechqurun', 'Evening', 'Вечер')}',
                      ),
                      if (c.uploading) ...[
                        Text(
                          c.progress >= 1
                              ? lt(
                                  'Server videoni tekshiryapti…',
                                  'Server is checking the video…',
                                  'Сервер проверяет видео…',
                                )
                              : '${(c.progress * 100).round()}%',
                        ),
                        TextButton(
                          onPressed: c.cancel,
                          child: Text(
                            lt(
                              'Yuklashni to‘xtatish',
                              'Stop upload',
                              'Остановить загрузку',
                            ),
                          ),
                        ),
                      ] else ...[
                        FilledButton(
                          onPressed: locked ? null : c.send,
                          child: Text(
                            lt(
                              'Yuborish / qayta urinish',
                              'Send / retry',
                              'Отправить / повторить',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: locked ? null : discard,
                          child: Text(
                            lt(
                              'Qoralamani tozalash',
                              'Clear draft',
                              'Очистить черновик',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (data != null) ...[
              Text('${data['day']} · Asia/Tashkent'),
              TextButton(
                onPressed: locked ? null : changeDay,
                child: Text(lt('Boshqa kun', 'Another day', 'Другой день')),
              ),
              if (data['serviceAvailable'] != true)
                Text(
                  lt(
                    'Video xizmati vaqtincha mavjud emas.',
                    'Video service is temporarily unavailable.',
                    'Видеосервис временно недоступен.',
                  ),
                ),
              for (final pet in data['pets'] as List)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pet['name'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        for (final slot in ['morning', 'evening'])
                          Builder(
                            builder: (context) {
                              final entries = (data['items'] as List).where(
                                (v) =>
                                    v['petId'] == pet['id'] &&
                                    v['slot'] == slot,
                              );
                              final label = slot == 'morning'
                                  ? lt('Ertalab', 'Morning', 'Утро')
                                  : lt('Kechqurun', 'Evening', 'Вечер');
                              if (entries.isEmpty) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(label),
                                  subtitle: Text(
                                    lt(
                                      'Video hali yuborilmagan',
                                      'No video submitted',
                                      'Видео не отправлено',
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: lt(
                                      'Video qo‘shish',
                                      'Add video',
                                      'Добавить видео',
                                    ),
                                    icon: const Icon(
                                      Icons.add_a_photo_outlined,
                                    ),
                                    onPressed:
                                        !locked && c.canSelect(pet['id'], slot)
                                        ? () => pick(pet['id'], slot)
                                        : null,
                                  ),
                                );
                              }
                              final item = entries.first;
                              final url =
                                  '${widget.api.baseUrl}${c.path}/${item['id']}';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '$label · ${(item['durationMs'] / 1000).round()} s',
                                ),
                                subtitle: Text(
                                  lt(
                                    'Serverda saqlangan',
                                    'Saved on server',
                                    'Сохранено на сервере',
                                  ),
                                ),
                                leading: Image.network(
                                  '$url/poster',
                                  headers: {
                                    'Authorization':
                                        'Bearer ${widget.api.token}',
                                  },
                                  width: 64,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.movie_outlined),
                                ),
                                trailing: const Icon(Icons.play_circle_outline),
                                onTap: !c.live
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => _Playback(
                                            api: widget.api,
                                            url: '$url/playback',
                                          ),
                                        ),
                                      ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}

class _Playback extends StatefulWidget {
  const _Playback({required this.api, required this.url});
  final CustomerApi api;
  final String url;
  @override
  State<_Playback> createState() => _PlaybackState();
}

class _PlaybackState extends State<_Playback> with WidgetsBindingObserver {
  VideoPlayerController? player;
  Object? error;
  final session = CustomerApi.sessionVersion;
  Timer? guard;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    guard = Timer.periodic(const Duration(seconds: 1), (_) {
      if (session != CustomerApi.sessionVersion) {
        player?.dispose();
        player = null;
        if (mounted) setState(() => error = StateError('Session expired'));
        guard?.cancel();
      }
    });
  }

  Future<void> load() async {
    if (loading || session != CustomerApi.sessionVersion) return;
    loading = true;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: {'Authorization': 'Bearer ${widget.api.token}'},
    );
    await player?.dispose();
    if (!mounted || session != CustomerApi.sessionVersion) {
      await controller.dispose();
      loading = false;
      return;
    }
    player = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (mounted && session == CustomerApi.sessionVersion) {
        setState(() => error = null);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      loading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    guard?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(lt('Video', 'Video', 'Видео'))),
    body: Center(
      child: error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lt(
                    'Video ochilmadi. Qayta urinib ko‘ring.',
                    'Video could not be opened. Try again.',
                    'Не удалось открыть видео. Повторите.',
                  ),
                ),
                TextButton(
                  onPressed: load,
                  child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
                ),
              ],
            )
          : player?.value.isInitialized != true
          ? const CircularProgressIndicator()
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: player!.value.aspectRatio,
                      child: VideoPlayer(player!),
                    ),
                  ),
                ),
                VideoProgressIndicator(player!, allowScrubbing: true),
                ValueListenableBuilder(
                  valueListenable: player!,
                  builder: (context, value, _) => IconButton(
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: () =>
                        value.isPlaying ? player!.pause() : player!.play(),
                  ),
                ),
              ],
            ),
    ),
  );
}
