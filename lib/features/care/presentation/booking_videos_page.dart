import '../../bookings/presentation/booking_source_boundary.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../data/booking_video_controller.dart';
import '../data/video_picker_cache.dart';
import '../../support/support_page.dart';

class BookingVideosPage extends StatelessWidget {
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
  Widget build(BuildContext context) => BookingSourceBoundary(
    api: api,
    valid:
        controller == null ||
        (identical(controller!.api, api) &&
            controller!.bookingId == bookingId &&
            controller!.live),
    child: _BookingVideosPage(
      key: ValueKey((api, bookingId, controller)),
      api: api,
      bookingId: bookingId,
      controller: controller,
    ),
  );
}

class _BookingVideosPage extends StatefulWidget {
  const _BookingVideosPage({
    super.key,
    required this.api,
    required this.bookingId,
    this.controller,
  });
  final CustomerApi api;
  final String bookingId;
  final BookingVideoController? controller;
  @override
  State<_BookingVideosPage> createState() => _BookingVideosPageState();
}

class _BookingVideosPageState extends State<_BookingVideosPage>
    with WidgetsBindingObserver, BookingOwnedDialogs<_BookingVideosPage> {
  late final c =
      widget.controller ?? BookingVideoController(widget.api, widget.bookingId);
  Timer? timer;
  bool foreground = true, picking = false;
  bool get live => mounted && c.live;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.load();
    timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  void refresh() {
    if (live &&
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
    if (!live || picking || !c.canSelect(pet, slot)) return;
    final source = await showOwnedSheet<ImageSource>(
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
    if (source == null || !live || !c.canSelect(pet, slot)) return;
    setState(() => picking = true);
    String? selectionId;
    try {
      selectionId = await c.beginSelection(pet, slot);
      if (selectionId == null || !live || !c.live) return;
      final file = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null || !live || !c.live) return;
      if (await file.length() > 32 * 1024 * 1024) {
        throw FormatException(
          lt(
            'Video 32 MiB dan oshmasin. 1080p yoki kichikroq video tanlang.',
            'Choose a video under 32 MiB, at 1080p or lower.',
            'Выберите видео до 32 МиБ, не выше 1080p.',
          ),
        );
      }
      if (!live) return;
      await c.select(
        pet,
        slot,
        await file.readAsBytes(),
        selectionId: selectionId,
      );
      if (c.live &&
          c.pending?['requestId'] == selectionId &&
          !c.selectionInterrupted) {
        await discardVideoPickerCopy(file.path);
      }
    } catch (_) {
      if (mounted && live) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lt(
                'Video ochilmadi. Tanlovni yoki saqlangan qoralamani qayta tekshiring.',
                'Could not open the video. Check the selection or saved draft.',
                'Не удалось открыть видео. Проверьте выбор или сохранённый черновик.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (live && selectionId != null && c.error == null) {
        await c.cancelSelection(selectionId);
      }
      if (live) setState(() => picking = false);
    }
  }

  Future<void> changeDay() async {
    if (!live || c.busy || picking || c.data == null) return;
    final last = DateTime.parse(c.data!['policy']['today']);
    final selected = await showOwnedDatePicker(
      initialDate: DateTime.parse(c.data!['day']),
      firstDate: DateTime(2020),
      lastDate: last,
    );
    if (selected != null && live) {
      await c.load(day: selected.toIso8601String().substring(0, 10));
    }
  }

  Future<void> explain(String pet, String slot) async {
    if (!live || c.busy || picking || c.explanationDraft != null) return;
    final day = c.data?['day'];
    var reason = '', emergency = false;
    final accepted = await showOwnedDialog<bool>(
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          scrollable: true,
          title: Text(
            lt(
              'Video yuborilmaganining sababi',
              'Reason for missing video',
              'Причина отсутствия видео',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lt(
                    'Sabab mijoz va yordam xizmatiga ko‘rinadi. Bu video o‘rnini bosmaydi; avtomatik jarima yoki qaytim yo‘q.',
                    'The customer and support can read this. It does not replace a video; no automatic fine or refund.',
                    'Причину увидят клиент и поддержка. Это не заменяет видео; автоматического штрафа или возврата нет.',
                  ),
                ),
                TextField(
                  maxLength: 1000,
                  maxLines: 3,
                  onChanged: (value) => setDialog(() => reason = value),
                  decoration: InputDecoration(
                    labelText: lt('Sabab', 'Reason', 'Причина'),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: emergency,
                  onChanged: (value) =>
                      setDialog(() => emergency = value ?? false),
                  title: Text(
                    lt(
                      'Favqulodda holat',
                      'Emergency',
                      'Чрезвычайная ситуация',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(lt('Bekor', 'Cancel', 'Отмена')),
            ),
            FilledButton(
              onPressed: reason.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(lt('Yuborish', 'Send', 'Отправить')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && live && c.data?['day'] == day) {
      await c.explain(pet, slot, reason, emergency);
    }
  }

  Widget followup(String pet, String slot) {
    final rows = (c.data?['followups'] as List? ?? []).where(
      (r) => r['slot'] == slot,
    );
    if (rows.isEmpty) return const SizedBox.shrink();
    final row = rows.first;
    final notes = (row['explanations'] as List).where((n) => n['petId'] == pet);
    if (notes.isNotEmpty) {
      final note = notes.first;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          note['emergency'] == true
              ? lt(
                  'Enaga favqulodda holat bildirdi',
                  'Sitter reported an emergency',
                  'Няня сообщила о чрезвычайной ситуации',
                )
              : lt(
                  'Enaga bildirgan sabab',
                  'Reason reported by sitter',
                  'Причина, указанная няней',
                ),
        ),
        subtitle: Text('${note['reason']}\n${note['created']}'),
      );
    }
    if (row['canExplain'] != true ||
        !(row['missingPetIds'] as List).contains(pet)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: c.busy || picking || c.explanationDraft != null
          ? null
          : () => explain(pet, slot),
      child: Text(
        lt(
          'Sabab / favqulodda holatni yozish',
          'Report reason / emergency',
          'Указать причину / чрезвычайную ситуацию',
        ),
      ),
    );
  }

  Future<void> discard() async {
    if (!live || c.busy || picking) return;
    final yes = await showOwnedDialog<bool>(
      builder: (context) => AlertDialog(
        scrollable: true,
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
    if (yes == true && live) await c.discard();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Video hisobotlar', 'Video reports', 'Видеоотчёты')),
    ),
    body: ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (!c.live) return bookingSourceExpired();
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
            Text(
              lt(
                'Videolar buyurtma tugagach 30 kun saqlanadi. Nizo bo‘lsa, u yopilguncha va yopilgandan keyin yana 30 kun saqlanadi.',
                'Videos remain for 30 days after the booking ends. An open dispute holds them until resolution and for 30 more days.',
                'Видео хранятся 30 дней после завершения заказа. При споре — до решения и ещё 30 дней после него.',
              ),
            ),
            if (c.busy)
              LinearProgressIndicator(
                value: c.uploading && c.progress < 1 ? c.progress : null,
              ),
            if (c.error != null)
              Text(
                lt(
                  'Video holatini yuklash yoki saqlash amalga oshmadi. Yangilang yoki saqlangan so‘rovni qayta yuboring.',
                  'Could not load or save the video status. Refresh or retry the saved request.',
                  'Не удалось загрузить или сохранить статус видео. Обновите или повторите сохранённый запрос.',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextButton(
              onPressed: locked ? null : refresh,
              child: Text(lt('Yangilash', 'Refresh', 'Обновить')),
            ),
            TextButton.icon(
              onPressed: locked
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SupportThreadPage(
                          api: widget.api,
                          bookingId: widget.bookingId,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.support_agent),
              label: Text(
                lt(
                  'Yordamga murojaat',
                  'Contact support',
                  'Обратиться в поддержку',
                ),
              ),
            ),
            if (c.explanationDraft != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        lt(
                          'Sabab hali server tomonidan tasdiqlanmagan.',
                          'The server has not confirmed this explanation.',
                          'Сервер ещё не подтвердил объяснение.',
                        ),
                      ),
                      Text(
                        '${c.explanationDraft!['day']} · ${c.explanationDraft!['reason']}',
                      ),
                      FilledButton(
                        onPressed: locked ? null : c.sendExplanation,
                        child: Text(
                          lt(
                            'Sababni qayta yuborish',
                            'Retry explanation',
                            'Повторить отправку причины',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: locked
                            ? null
                            : () async {
                                final yes = await showOwnedDialog<bool>(
                                  builder: (context) => AlertDialog(
                                    scrollable: true,
                                    content: Text(
                                      lt(
                                        'Faqat telefondagi sabab qoralamasi tozalanadi. Serverga yetib borgan sabab saqlanadi.',
                                        'Only the local explanation draft is cleared. A server-confirmed explanation remains.',
                                        'Удалится только черновик на телефоне. Сохранённая сервером причина останется.',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(
                                          lt('Bekor', 'Cancel', 'Отмена'),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(
                                          lt('Tozalash', 'Clear', 'Очистить'),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (yes == true && live) {
                                  await c.discardExplanation();
                                }
                              },
                        child: Text(
                          lt(
                            'Sabab qoralamasini tozalash',
                            'Clear explanation draft',
                            'Очистить черновик причины',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (c.pending != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        c.selectionInterrupted
                            ? lt(
                                'Video tanlash yakunlanmagan. Hech narsa yuborilmadi. Qoralamani tozalab, kerakli hayvon va vaqt uchun videoni qayta tanlang.',
                                'Video selection was interrupted. Nothing was uploaded. Clear the draft and select the video again for the intended pet and time.',
                                'Выбор видео прерван. Ничего не отправлено. Очистите черновик и снова выберите видео для нужного питомца и времени.',
                              )
                            : lt(
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
                        if (!c.selectionInterrupted)
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
                                return Column(
                                  children: [
                                    ListTile(
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
                                            !locked &&
                                                c.canSelect(pet['id'], slot)
                                            ? () => pick(pet['id'], slot)
                                            : null,
                                      ),
                                    ),
                                    followup(pet['id'], slot),
                                  ],
                                );
                              }
                              final item = entries.first;
                              final available = item['available'] != false;
                              final url =
                                  '${widget.api.baseUrl}${c.path}/${item['id']}';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '$label · ${(item['durationMs'] / 1000).round()} s',
                                ),
                                subtitle: Text(
                                  available
                                      ? lt(
                                          'Serverda saqlangan',
                                          'Saved on server',
                                          'Сохранено на сервере',
                                        )
                                      : lt(
                                          'Saqlash muddati tugagan',
                                          'Retention period ended',
                                          'Срок хранения истёк',
                                        ),
                                ),
                                leading: !available
                                    ? const Icon(Icons.history)
                                    : Image.network(
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
                                trailing: available
                                    ? const Icon(Icons.play_circle_outline)
                                    : null,
                                onTap: !c.live || !available
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
