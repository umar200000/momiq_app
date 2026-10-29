import '../media/presentation/private_api_image.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../customer/data/customer_api.dart';
import '../listings/presentation/listing_style.dart' show lt;
import '../wallet/data/receipt_image.dart';
import 'support_controller.dart';
import 'support_resolution.dart';

String supportState(String value) => switch (value) {
  'waiting_user' => lt(
    'Javobingiz kutilmoqda',
    'Waiting for your reply',
    'Ожидается ваш ответ',
  ),
  'resolved' => lt('Yopilgan', 'Resolved', 'Закрыто'),
  _ => lt('Ko‘rib chiqilmoqda', 'Open', 'На рассмотрении'),
};
String supportError() => lt(
  'Yuklash yoki yuborish amalga oshmadi. Qayta urinib ko‘ring.',
  'Could not load or send. Retry.',
  'Не удалось загрузить или отправить. Повторите.',
);

String supportTargetLabel(String kind, [String? purpose]) => purpose == 'appeal'
    ? lt(
        'Qarorni qayta ko‘rib chiqish',
        'Appeal decision',
        'Обжаловать решение',
      )
    : kind == 'review'
    ? lt('Sharhga shikoyat', 'Report review', 'Пожаловаться на отзыв')
    : lt(
        'E’lon yoki profilga shikoyat',
        'Report listing or profile',
        'Пожаловаться на объявление или профиль',
      );

class PublicContentReportButton extends StatefulWidget {
  const PublicContentReportButton({
    super.key,
    required this.api,
    required this.target,
  });
  final CustomerApi? api;
  final Map<String, String> target;
  @override
  State<PublicContentReportButton> createState() =>
      _PublicContentReportButtonState();
}

class _PublicContentReportButtonState extends State<PublicContentReportButton> {
  final session = CustomerApi.sessionVersion;
  bool get live =>
      session == CustomerApi.sessionVersion &&
      widget.api != null &&
      widget.api!.userId.isNotEmpty &&
      (CustomerApi.active == null || identical(CustomerApi.active, widget.api));
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: !live
        ? null
        : () {
            if (!live) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SupportThreadPage(api: widget.api!, target: widget.target),
              ),
            );
          },
    icon: const Icon(Icons.flag_outlined),
    label: Text(
      supportTargetLabel(widget.target['kind']!, widget.target['purpose']),
    ),
  );
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key, this.api});
  final CustomerApi? api;
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  CustomerApi? api;
  final items = <SupportJson>[];
  List<SupportJson> legacy = [];
  final session = CustomerApi.sessionVersion;
  bool busy = false, failed = false, loaded = false;
  String? cursor;
  bool get live => mounted && session == CustomerApi.sessionVersion;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (!live || busy || (more && cursor == null)) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      api ??= widget.api ?? await CustomerApi.restore();
      if (api == null) throw StateError('Sign in');
      if (!live) return;
      final result = await api!.request(
        'GET',
        '/support${more ? '?before=$cursor' : ''}',
      );
      if (!live) return;
      setState(() {
        if (!more) {
          items.clear();
          legacy = ((result['legacyItems'] ?? []) as List)
              .map((r) => SupportJson.from(r))
              .toList();
        }
        final ids = items.map((r) => r['id']).toSet();
        items.addAll(
          (result['items'] as List)
              .map((r) => SupportJson.from(r))
              .where((r) => ids.add(r['id'])),
        );
        cursor = result['nextCursor'];
        loaded = true;
      });
    } catch (_) {
      if (live) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open([String? id]) async {
    if (api == null || !live) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupportThreadPage(api: api!, id: id),
      ),
    );
    if (live) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Yordam murojaatlari', 'Support requests', 'Обращения')),
      actions: [
        IconButton(
          tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          lt(
            'Momiq yordam xizmati bilan yozishma. Bu yerda xizmat puli to‘lanmaydi.',
            'Private conversation with Momiq support. No service payment here.',
            'Переписка с поддержкой Momiq. Оплата услуги здесь не проводится.',
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (failed) Text(supportError()),
        FilledButton(
          key: const ValueKey('newSupport'),
          onPressed: api == null || busy ? null : () => open(),
          child: Text(lt('Yangi murojaat', 'New request', 'Новое обращение')),
        ),
        if (loaded && items.isEmpty)
          Text(
            lt(
              'Murojaatlar hali yo‘q.',
              'No requests yet.',
              'Обращений пока нет.',
            ),
          ),
        if (legacy.isNotEmpty)
          ExpansionTile(
            title: Text(
              lt(
                'Oldingi murojaatlar arxivi',
                'Previous request archive',
                'Архив прежних обращений',
              ),
            ),
            children: [
              for (final item in legacy)
                ListTile(title: Text('${item['text'] ?? ''}')),
            ],
          ),
        for (final item in items)
          ListTile(
            title: Text(item['subject']),
            subtitle: Text(
              '${supportState(item['status'])} · ${item['updated']}',
            ),
            onTap: () => open(item['id']),
          ),
        if (cursor != null)
          TextButton(
            onPressed: busy ? null : () => load(more: true),
            child: Text(lt('Yana', 'More', 'Ещё')),
          ),
      ],
    ),
  );
}

class SupportThreadPage extends StatefulWidget {
  const SupportThreadPage({
    super.key,
    required this.api,
    this.id,
    this.bookingId,
    this.controller,
    this.target,
  });
  final CustomerApi api;
  final String? id, bookingId;
  final SupportController? controller;
  final Map<String, String>? target;
  @override
  State<SupportThreadPage> createState() => _SupportThreadPageState();
}

class _SupportThreadPageState extends State<SupportThreadPage> {
  late final c =
      widget.controller ??
      SupportController(widget.api, widget.id, target: widget.target);
  final message = TextEditingController(), subject = TextEditingController();
  String? image;
  String topic = 'general';
  bool picking = false;
  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) topic = 'booking';
    if (widget.target != null) {
      topic = 'safety';
      subject.text = supportTargetLabel(
        widget.target!['kind']!,
        widget.target!['purpose'],
      );
    }
    load();
  }

  Future<void> load() async {
    await c.load();
    if (!mounted) return;
    final p = c.pending;
    if (p != null) {
      setState(() {
        message.text = p['text'] ?? '';
        subject.text = p['subject'] ?? '';
        image = p['image'];
        topic = p['topic'] ?? topic;
      });
    }
  }

  @override
  void dispose() {
    message.dispose();
    subject.dispose();
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    setState(() => picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        requestFullMetadata: false,
      );
      if (file != null) {
        if (await file.length() > 3 * 1024 * 1024) {
          throw const FormatException('size');
        }
        final bytes = await file.readAsBytes();
        await validateReceiptImage(bytes);
        if (mounted && c.live) setState(() => image = base64Encode(bytes));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lt(
                'Rasm ochilmadi. PNG/JPEG/WebP, 3 MB gacha.',
                'Could not open image. PNG/JPEG/WebP, up to 3 MB.',
                'Не удалось открыть фото. PNG/JPEG/WebP, до 3 МБ.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> send() async {
    if (c.pending == null &&
        ((message.text.trim().isEmpty && (image == null || c.target != null)) ||
            (widget.id == null && subject.text.trim().isEmpty))) {
      return;
    }
    final sent = await c.send(
      message.text,
      image,
      subject: subject.text,
      topic: topic,
      bookingId: widget.bookingId,
    );
    if (!mounted || !c.live || !sent) return;
    if (widget.id == null) {
      final id = c.data!['ticket']['id'] as String;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SupportThreadPage(api: widget.api, id: id),
        ),
      );
    } else {
      setState(() {
        message.clear();
        image = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final ticket = c.data?['ticket'];
      final target = c.pending?['target'] ?? c.data?['target'] ?? c.target;
      final enabled =
          c.live &&
          !c.busy &&
          !picking &&
          c.pending == null &&
          c.error == null &&
          c.data != null;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            ticket?['subject'] ??
                lt('Yangi murojaat', 'New request', 'Новое обращение'),
          ),
          actions: [
            IconButton(
              tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
              onPressed: c.busy ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null) Text(supportError()),
            if (ticket != null) Text(supportState(ticket['status'])),
            if (target != null) ...[
              Text(
                '${supportTargetLabel(target['kind'], target['purpose'])} · #${target['id']}',
                key: const ValueKey('supportTarget'),
              ),
              Text(
                target['purpose'] == 'appeal'
                    ? lt(
                        'Qarorga nega rozi emasligingizni yozing. Administrator qayta ko‘rib chiqadi. Murojaat yuborish e’lon yoki sharhni avtomatik tiklamaydi.',
                        'Explain why you disagree. An administrator will review the decision. Submitting an appeal does not automatically restore the listing or review.',
                        'Объясните, почему вы не согласны. Администратор пересмотрит решение. Обращение не восстанавливает объявление или отзыв автоматически.',
                      )
                    : lt(
                        'Sababini yozing. Yordam xizmati ko‘rib chiqadi; shikoyatning o‘zi kontentni yashirmaydi. Rasmdagi muammo bo‘lsa, rasmni ham biriktiring.',
                        'Describe the reason. Support will review it; submitting a report does not hide content. Attach an image if the issue concerns a photo.',
                        'Опишите причину. Поддержка рассмотрит обращение; жалоба не скрывает контент автоматически. Если проблема в фото, приложите изображение.',
                      ),
              ),
            ],
            if (widget.id == null) ...[
              TextField(
                key: const ValueKey('supportSubject'),
                controller: subject,
                enabled: enabled,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: lt('Mavzu', 'Subject', 'Тема'),
                ),
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                isDense: false,
                itemHeight: null,
                initialValue: topic,
                items: [
                  for (final entry in <String, String>{
                    'general': lt('Umumiy', 'General', 'Общее'),
                    'payment': lt(
                      'Balans / chek',
                      'Balance / receipt',
                      'Баланс / чек',
                    ),
                    'account': lt('Hisob', 'Account', 'Аккаунт'),
                    'safety': lt('Xavfsizlik', 'Safety', 'Безопасность'),
                    if (widget.bookingId != null || topic == 'booking')
                      'booking': lt('Buyurtma', 'Booking', 'Заказ'),
                  }.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: enabled ? (v) => setState(() => topic = v!) : null,
              ),
            ],
            if ((c.pending?['bookingId'] ??
                    widget.bookingId ??
                    ticket?['bookingId']) !=
                null)
              Text(
                '#${c.pending?['bookingId'] ?? widget.bookingId ?? ticket?['bookingId']}',
              ),
            if (c.data?['nextCursor'] != null)
              TextButton(
                onPressed: c.busy ? null : () => c.load(more: true),
                child: Text(
                  lt(
                    'Oldingi xabarlar',
                    'Earlier messages',
                    'Предыдущие сообщения',
                  ),
                ),
              ),
            for (final m in c.data?['items'] ?? [])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m['authorRole'] == 'support'
                            ? lt(
                                'Momiq yordam xizmati',
                                'Momiq support',
                                'Поддержка Momiq',
                              )
                            : lt('Siz', 'You', 'Вы'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(m['text']),
                      Text(m['created']),
                      if (m['resolution'] != null)
                        SupportResolution(value: m['resolution']),
                      if (m['hasImage'] == true)
                        SupportImage(
                          api: widget.api,
                          path:
                              '/support/${ticket['id']}/messages/${m['id']}/image',
                        ),
                    ],
                  ),
                ),
              ),
            TextField(
              key: const ValueKey('supportMessage'),
              controller: message,
              enabled: enabled,
              maxLength: 4000,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: target == null
                    ? lt('Xabar', 'Message', 'Сообщение')
                    : lt('Shikoyat sababi', 'Report reason', 'Причина жалобы'),
              ),
            ),
            if (image != null)
              Image.memory(
                base64Decode(image!),
                height: 140,
                errorBuilder: (_, _, _) => Text(supportError()),
              ),
            TextButton.icon(
              onPressed: enabled ? pick : null,
              icon: const Icon(Icons.image),
              label: Text(
                lt('Rasm biriktirish', 'Attach image', 'Прикрепить фото'),
              ),
            ),
            if (image != null)
              TextButton(
                onPressed: enabled ? () => setState(() => image = null) : null,
                child: Text(
                  lt('Rasmni olib tashlash', 'Remove image', 'Убрать фото'),
                ),
              ),
            FilledButton(
              key: const ValueKey('sendSupport'),
              onPressed:
                  c.live &&
                      !c.busy &&
                      !picking &&
                      (enabled || c.pending != null)
                  ? send
                  : null,
              child: Text(
                c.pending != null
                    ? lt(
                        'Ayni xabarni qayta yuborish',
                        'Retry same message',
                        'Повторить то же сообщение',
                      )
                    : lt('Yuborish', 'Send', 'Отправить'),
              ),
            ),
            if (c.pending != null)
              TextButton(
                onPressed: c.busy ? null : c.discard,
                child: Text(
                  lt(
                    'Qayta yuborish qoralamasini tozalash',
                    'Clear retry draft',
                    'Очистить черновик повтора',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class SupportImage extends StatelessWidget {
  const SupportImage({super.key, required this.api, required this.path});
  final CustomerApi api;
  final String path;
  @override
  Widget build(BuildContext context) => PrivateApiImage(
    api: api,
    path: path,
    height: 200,
    label: lt('Rasmni ochish', 'Open image', 'Открыть фото'),
  );
}
