import '../../media/presentation/private_api_image.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../bookings/presentation/bookings_page.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/widgets/momiq_scaffold.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../wallet/data/receipt_image.dart';
import '../data/conversation_controller.dart';
import 'chat_reports.dart';

String chatService(String? service) => switch (service) {
  'boarding' => lt('Uyda qarash', 'Boarding', 'Передержка'),
  'homeVisit' => lt('Uyga kelish', 'Home visit', 'Визит на дом'),
  'personal' => lt('Shaxsiy enaga', 'Personal sitter', 'Личная няня'),
  _ => '',
};
String chatRetry() => lt('Qayta urinish', 'Retry', 'Повторить');
String chatFailure() => lt(
  'Ulanish yoki saqlash amalga oshmadi. Qayta urinib ko‘ring.',
  'Could not connect or save. Please retry.',
  'Не удалось подключиться или сохранить. Повторите.',
);

Future<void> openConversation(
  BuildContext context,
  String listing, {
  CustomerApi? api,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ConversationPage(listingId: listing, api: api),
    ),
  );
}

/// Embedded in the active tab; disposing it or covering the route stops polling.
class ConversationInbox extends StatefulWidget {
  const ConversationInbox({super.key, this.api});
  final CustomerApi? api;
  @override
  State<ConversationInbox> createState() => _ConversationInboxState();
}

class _ConversationInboxState extends State<ConversationInbox>
    with WidgetsBindingObserver {
  CustomerApi? _api;
  final _items = <ChatJson>[];
  String? _cursor;
  bool _busy = false, _failed = false, _foreground = true;
  final int _session = CustomerApi.sessionVersion;
  Timer? _timer;
  bool get _visible =>
      mounted &&
      _foreground &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      _session == CustomerApi.sessionVersion;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_visible) _load(quiet: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_visible) _load(quiet: true);
  }

  Future<void> _load({bool more = false, bool quiet = false}) async {
    if (_busy || (more && _cursor == null)) return;
    _busy = true;
    if (!quiet) setState(() => _failed = false);
    try {
      _api ??= widget.api ?? await CustomerApi.restore();
      if (_api == null) throw StateError('Sign in');
      final result = await _api!.request(
        'GET',
        '/conversations${more ? '?before=${Uri.encodeQueryComponent(_cursor!)}' : ''}',
      );
      if (!mounted || _session != CustomerApi.sessionVersion) return;
      setState(() {
        // Auto-refresh only the first page. Preserve older loaded conversations
        // until an explicit refresh, and deduplicate moved/new threads.
        final incoming = (result['items'] as List)
            .map((x) => ChatJson.from(x))
            .toList();
        if (quiet) {
          final ids = incoming.map((e) => e['id']).toSet();
          _items.removeWhere((e) => ids.contains(e['id']));
          _items.insertAll(0, incoming);
        } else {
          if (!more) _items.clear();
          final ids = _items.map((e) => e['id']).toSet();
          _items.addAll(incoming.where((e) => ids.add(e['id'])));
        }
        if (!quiet || _items.length <= 30) {
          _cursor = result['nextCursor'] as String?;
        }
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              lt('Suhbatlar', 'Conversations', 'Переписки'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: chatRetry(),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (_busy && _items.isEmpty) const LinearProgressIndicator(),
      if (_failed) Text(chatFailure()),
      if (!_busy && !_failed && _items.isEmpty)
        Text(
          lt(
            'Hozircha suhbatlar yo‘q',
            'No conversations yet',
            'Переписок пока нет',
          ),
        ),
      for (final item in _items)
        ListTile(
          key: ValueKey('conversation-${item['id']}'),
          title: Text(item['peerName'] as String),
          subtitle: Text(
            '${chatService(item['service'])}\n${item['lastMessage']?['text'] ?? ''}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: item['unreadCount'] > 0
              ? Badge(label: Text('${item['unreadCount']}'))
              : const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ConversationPage(conversationId: item['id'], api: _api),
              ),
            );
            if (mounted) _load();
          },
        ),
      if (_cursor != null)
        TextButton(
          onPressed: _busy ? null : () => _load(more: true),
          child: Text(lt('Yana', 'More', 'Ещё')),
        ),
    ],
  );
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    this.conversationId,
    this.listingId,
    this.api,
    this.controller,
  }) : assert(
         conversationId != null || listingId != null || controller != null,
       );
  final String? conversationId, listingId;
  final CustomerApi? api;
  final ConversationController? controller;
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage>
    with WidgetsBindingObserver {
  ConversationController? _chat;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  String? _image;
  bool _starting = false, _failed = false, _foreground = true, _picking = false;
  bool _actionBusy = false;
  Timer? _timer;
  bool get _visible =>
      mounted && _foreground && (ModalRoute.of(context)?.isCurrent ?? true);
  bool get _atBottom => !_scroll.hasClients || _scroll.offset < 70;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _scroll.addListener(_readVisible);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_visible) _poll();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_visible) _poll();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _failed = false;
    });
    try {
      if (_chat == null) {
        if (widget.controller != null) {
          _chat = widget.controller;
        } else {
          final api = widget.api ?? await CustomerApi.restore();
          if (api == null) throw StateError('Sign in');
          final id =
              widget.conversationId ??
              (await api.request('POST', '/conversations', {
                    'listingId': widget.listingId,
                  }))['id']
                  as String;
          if (!mounted) return;
          _chat = ConversationController(api, id);
        }
        _chat!.addListener(_changed);
      }
      await _chat!.initialize();
      if (!mounted) return;
      _text.text = _chat!.pending?['text'] ?? _text.text;
      _image = _chat!.pending?['image'] ?? _image;
      WidgetsBinding.instance.addPostFrameCallback((_) => _readVisible());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _poll() async {
    if (_chat == null || !_chat!.ready) return;
    await _chat!.refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readVisible());
  }

  void _readVisible() {
    if (!_visible || !_atBottom || _chat == null || _chat!.readCursor == '0') {
      return;
    }
    // Only a fetched page advances this cursor. A local send cannot skip an
    // incoming message that arrived concurrently but has not been loaded yet.
    _chat!.readThrough(_chat!.readCursor);
  }

  Future<void> _send() async {
    final chat = _chat;
    if (chat == null) return;
    if (await chat.send(_text.text, _image)) {
      if (!mounted) return;
      setState(() {
        _text.clear();
        _image = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      await _poll();
    }
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await validateReceiptImage(bytes);
      if (mounted) setState(() => _image = base64Encode(bytes));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lt(
                'Rasm tanlanmadi. JPEG, PNG yoki WebP, 3 MB gacha.',
                'Could not select image. JPEG, PNG or WebP, up to 3 MB.',
                'Не удалось выбрать фото. JPEG, PNG или WebP до 3 МБ.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _menu(String action) async {
    final chat = _chat;
    if (chat == null || _actionBusy) return;
    if (action == 'bookings') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(
                lt(
                  'Shu suhbatdagi buyurtmalar',
                  'Bookings in this conversation',
                  'Заказы в этой переписке',
                ),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: BookingInbox(api: chat.api, conversationId: chat.id),
            ),
          ),
        ),
      );
      return;
    }
    if (action == 'reports') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatReportsPage(api: chat.api, conversationId: chat.id),
        ),
      );
      return;
    }
    final discard = action == 'discard';
    final block = chat.conversation?['blockedByMe'] != true;
    final title = discard
        ? lt('Qoralamani tozalash', 'Clear outbox', 'Очистить черновик')
        : block
        ? lt(
            'Foydalanuvchini bloklash',
            'Block user',
            'Заблокировать пользователя',
          )
        : lt(
            'Blokni olib tashlash',
            'Unblock user',
            'Разблокировать пользователя',
          );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          discard
              ? lt(
                  'Xabar serverga yetib borgan bo‘lishi mumkin. Bu faqat qurilmadagi qayta yuborish qoralamasini tozalaydi; yuborilgan xabarni qaytarib olmaydi.',
                  'The server may already have accepted this message. This clears only the local retry draft; it does not recall a sent message.',
                  'Сервер мог уже принять сообщение. Удалится только локальный черновик повтора, не отправленное сообщение.',
                )
              : lt(
                  'Bu qaror shu foydalanuvchi bilan barcha xizmatlardagi yozishmalarga ta’sir qiladi. Buyurtmani bekor qilmaydi.',
                  'This applies to all service conversations with this user. It does not cancel a booking.',
                  'Это действует во всех переписках с пользователем и не отменяет заказ.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Bekor qilish', 'Cancel', 'Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      if (discard) {
        await chat.discardPending();
        if (mounted) {
          setState(() {
            _text.clear();
            _image = null;
          });
        }
      } else {
        await chat.setBlocked(block);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(chatFailure())));
      }
      await chat.refresh();
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _chat?.removeListener(_changed);
    if (widget.controller == null) _chat?.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final pending = chat?.pending != null;
    final disabled =
        chat == null ||
        !chat.ready ||
        !chat.live ||
        chat.sending ||
        _actionBusy ||
        _picking ||
        chat.conversation?['canSend'] == false;
    final messages = chat?.messages.reversed.toList() ?? <ChatJson>[];
    return MomiqScaffold(
      appBar: AppBar(
        title: Text(
          chat?.conversation?['peerName'] ??
              lt('Suhbat', 'Conversation', 'Переписка'),
        ),
        actions: [
          PopupMenuButton<String>(
            enabled:
                chat?.ready == true && chat?.sending == false && !_actionBusy,
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'bookings',
                child: Text(lt('Buyurtmalar', 'Bookings', 'Заказы')),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  chat?.conversation?['blockedByMe'] == true
                      ? lt(
                          'Blokni olib tashlash',
                          'Unblock user',
                          'Разблокировать',
                        )
                      : lt('Bloklash', 'Block user', 'Заблокировать'),
                ),
              ),
              PopupMenuItem(
                value: 'reports',
                child: Text(lt('Murojaatlarim', 'My reports', 'Мои обращения')),
              ),
              if (pending)
                PopupMenuItem(
                  value: 'discard',
                  child: Text(
                    lt(
                      'Qoralamani tozalash',
                      'Clear outbox',
                      'Очистить черновик',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_starting || chat?.loading == true)
              const LinearProgressIndicator(),
            if (_failed || chat?.error != null)
              MaterialBanner(
                content: Text(chatFailure()),
                actions: [
                  TextButton(
                    onPressed: _starting
                        ? null
                        : () => chat?.ready == true ? _poll() : _start(),
                    child: Text(chatRetry()),
                  ),
                ],
              ),
            if (chat?.conversation != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(chatService(chat!.conversation!['service'])),
              ),
            if (chat?.conversation?['canSend'] == false)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  lt(
                    'Bu foydalanuvchi bilan yozishma to‘xtatilgan.',
                    'Messaging with this user is unavailable.',
                    'Переписка с этим пользователем недоступна.',
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return chat?.more == true
                        ? TextButton(
                            onPressed: chat!.loading
                                ? null
                                : () => chat.refresh(older: true),
                            child: Text(
                              lt(
                                'Oldingi xabarlar',
                                'Earlier messages',
                                'Ранние сообщения',
                              ),
                            ),
                          )
                        : const SizedBox.shrink();
                  }
                  final m = messages[index];
                  final mine = m['mine'] == true;
                  final read =
                      int.parse(
                        chat?.conversation?['peerReadThrough'] ?? '0',
                      ) >=
                      int.parse(m['id']);
                  final delivered =
                      int.parse(
                        chat?.conversation?['peerDeliveredThrough'] ?? '0',
                      ) >=
                      int.parse(m['id']);
                  final time = DateTime.tryParse(m['created'] ?? '')?.toLocal();
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mine
                                  ? lt('Siz', 'You', 'Вы')
                                  : chat!.conversation!['peerName'],
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            if ((m['text'] as String).isNotEmpty)
                              SelectableText(m['text']),
                            if (m['hidden'] == true)
                              Text(reportStatus('removed')),
                            if (m['hasImage'] == true)
                              _ChatImage(
                                api: chat!.api,
                                path: '${chat.path}/messages/${m['id']}/image',
                                key: ValueKey('image-${m['id']}'),
                              ),
                            Text(
                              '${time == null ? '' : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'}${mine ? ' · ${read
                                        ? lt('O‘qilgan', 'Read', 'Прочитано')
                                        : delivered
                                        ? lt('Yetkazildi', 'Delivered', 'Доставлено')
                                        : lt('Yuborildi', 'Sent', 'Отправлено')}' : ''}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            if (!mine && m['hidden'] != true)
                              TextButton.icon(
                                onPressed: () => showDialog<bool>(
                                  context: context,
                                  builder: (_) => ChatReportDialog(
                                    api: chat!.api,
                                    conversationId: chat.id,
                                    messageId: m['id'],
                                  ),
                                ),
                                icon: const Icon(Icons.flag_outlined, size: 16),
                                label: Text(
                                  lt('Shikoyat', 'Report', 'Пожаловаться'),
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
            if (pending)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  lt(
                    'Yuborish tasdig‘i kutilmoqda. Qayta yuborish shu xabarni takrorlamaydi.',
                    'Awaiting send confirmation. Retry safely uses the same message.',
                    'Ожидается подтверждение. Повторная отправка не создаст дубликат.',
                  ),
                ),
              ),
            if (_image != null)
              Row(
                children: [
                  const Icon(Icons.image),
                  Expanded(
                    child: Text(
                      lt(
                        'Rasm biriktirilgan',
                        'Image attached',
                        'Фото прикреплено',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: disabled || pending
                        ? null
                        : () => setState(() => _image = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: lt('Rasm', 'Image', 'Фото'),
                    onPressed: disabled || pending ? null : _pick,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('conversationText'),
                      controller: _text,
                      enabled: !disabled && !pending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4000,
                      decoration: InputDecoration(
                        labelText: lt('Xabar', 'Message', 'Сообщение'),
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('conversationSend'),
                    tooltip: pending
                        ? chatRetry()
                        : lt('Yuborish', 'Send', 'Отправить'),
                    onPressed: disabled ? null : _send,
                    icon: chat?.sending == true
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatImage extends StatelessWidget {
  const _ChatImage({super.key, required this.api, required this.path});
  final CustomerApi api;
  final String path;
  @override
  Widget build(BuildContext context) => PrivateApiImage(
    api: api,
    path: path,
    width: 220,
    label: lt('Rasmni ochish', 'Open image', 'Открыть фото'),
  );
}
