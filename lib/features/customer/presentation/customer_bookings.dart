import 'package:momiq_app/core/widgets/button_progress.dart';
import 'package:momiq_app/core/widgets/momiq_scaffold.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'customer_widgets.dart';

String _messageAuthor(CJson message) => message['mine'] == true
    ? lt('Siz', 'You', 'Вы')
    : switch (message['senderRole']) {
        'support' => lt(
          'Momiq yordam xizmati',
          'Momiq support',
          'Поддержка Momiq',
        ),
        'sitter' => lt('Enaga', 'Sitter', 'Няня'),
        _ => lt(
          'Muallif ko‘rsatilmagan',
          'Author not specified',
          'Автор не указан',
        ),
      };

class CustomerChatList extends StatefulWidget {
  const CustomerChatList({super.key, required this.store});
  final CustomerStore store;
  @override
  State<CustomerChatList> createState() => _CustomerChatListState();
}

class _CustomerChatListState extends State<CustomerChatList> {
  String _query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final all = widget.store.list('messages');
      final ids = {
        ...all
            .map((m) => m['sitter'])
            .whereType<String>()
            .where((id) => id.isNotEmpty),
      }.toList();
      DateTime lastTime(String id) =>
          all.where((m) => m['sitter'] == id).isEmpty
          ? DateTime(2000)
          : DateTime.tryParse(
                  '${all.lastWhere((m) => m['sitter'] == id)['time'] ?? ''}',
                ) ??
                DateTime(2000);
      ids.sort((a, b) => lastTime(b).compareTo(lastTime(a)));
      final visible = ids
          .where(
            (id) => '${customerSitter(id)['name']}'.toLowerCase().contains(
              _query.toLowerCase(),
            ),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lt(
              'Oldingi yordam yozishmalari',
              'Earlier support conversations',
              'Предыдущие обращения',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('customerChatSearch'),
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              hintText: ct('Suhbatlarni qidirish'),
              prefixIcon: const Icon(Icons.search_rounded, color: listingGold),
              filled: true,
              fillColor: listingSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 22),
          cText('Suhbatlar · ${visible.length}', bold: true, size: 17),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            cCard(
              Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 42,
                    color: listingGold,
                  ),
                  const SizedBox(height: 12),
                  cText(
                    _query.isEmpty ? 'Hali suhbat yo‘q' : 'Suhbat topilmadi',
                    bold: true,
                  ),
                  cText(
                    _query.isEmpty
                        ? 'Enaga profilidan suhbatni boshlashingiz mumkin.'
                        : 'Enaganing ismi bilan qidirib ko‘ring.',
                    size: 13,
                  ),
                ],
              ),
            ),
          for (final id in visible)
            Builder(
              builder: (context) {
                final sitter = customerSitter(id);
                final messages = all.where((m) => m['sitter'] == id).toList();
                final last = messages.isEmpty ? null : messages.last;
                return cCard(
                  Row(
                    children: [
                      ClipOval(
                        child: SitterPortrait(index: sitter['photo'], size: 54),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sitter['name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4B2C1C),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              last == null
                                  ? ct('Suhbatni boshlash')
                                  : '${_messageAuthor(last)}: ${last['image'] != null ? ct('Rasm') : last['text']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF8C7965),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 7),
                            cText(
                              _chatService(sitter),
                              size: 11,
                              color: listingGold,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          if (last != null)
                            cText(_chatTime(last['time']), size: 10),
                          const SizedBox(height: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: listingGold,
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => cPush(
                    context,
                    CustomerChatPage(store: widget.store, sitter: sitter),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

String _chatService(CJson sitter) {
  final service = sitter['service'];
  return service is int && service >= 0 && service < customerServices.length
      ? customerServices[service]
      : 'Enaga profili mavjud emas';
}

String _chatTime(String? value) {
  final time = DateTime.tryParse(value ?? '')?.toLocal();
  if (time == null) return '';
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class CustomerChatPage extends StatefulWidget {
  const CustomerChatPage({
    super.key,
    required this.store,
    required this.sitter,
  });
  final CustomerStore store;
  final CJson sitter;
  @override
  State<CustomerChatPage> createState() => _CustomerChatPageState();
}

class _CustomerChatPageState extends State<CustomerChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  Future<void> _send() async {
    if (_sending ||
        widget.sitter['unavailable'] == true ||
        _text.text.trim().isEmpty) {
      return;
    }
    final message = _text.text;
    setState(() => _sending = true);
    try {
      await widget.store.send(widget.sitter['id'], message);
      if (mounted) {
        _text.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) cNotice(context, 'Xabar saqlanmadi.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        imageQuality: 75,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await widget.store.saveItem('messages', {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'sitter': widget.sitter['id'],
        'mine': true,
        'text': '',
        'image': base64Encode(bytes),
        'time': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      if (mounted) cNotice(context, 'Rasm yuborilmadi.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => MomiqScaffold(
      backgroundColor: listingBackground,
      appBar: AppBar(
        backgroundColor: listingBackground,
        title: Row(
          children: [
            SitterPortrait(index: widget.sitter['photo'], size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cText(widget.sitter['name'], bold: true, size: 16),
                  cText(
                    _chatService(widget.sitter),
                    size: 11,
                    color: listingGold,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.store.syncError != null)
              MaterialBanner(
                content: Text(
                  lt(
                    'Xabarlarni yangilab bo‘lmadi.',
                    'Could not refresh messages.',
                    'Не удалось обновить сообщения.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: widget.store.refreshRemote,
                    child: Text(ct('Qayta urinish')),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: cText(
                widget.store.remote
                    ? 'Momiq yordam xizmati'
                    : 'Suhbat · xabarlar hozircha qurilmada saqlanadi',
                size: 11,
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (!widget.store
                      .list('messages')
                      .any((m) => m['sitter'] == widget.sitter['id']))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: cCard(
                        Column(
                          children: [
                            Image.asset(
                              'assets/images/service_cat.png',
                              height: 100,
                            ),
                            const SizedBox(height: 16),
                            cText('Suhbatni boshlang', size: 22, bold: true),
                            const SizedBox(height: 8),
                            cText(
                              'Hayvoningiz va parvarish tafsilotlarini enaga bilan kelishib oling.',
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final m
                      in widget.store
                          .list('messages')
                          .where((m) => m['sitter'] == widget.sitter['id']))
                    Align(
                      alignment: m['mine'] == true
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .78,
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: m['mine'] == true
                              ? const Color(0xFFF1D28E)
                              : listingSurface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(
                              m['mine'] == true ? 20 : 5,
                            ),
                            bottomRight: Radius.circular(
                              m['mine'] == true ? 5 : 20,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _messageAuthor(m),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (m['image'] != null)
                              GestureDetector(
                                onTap: () => showDialog<void>(
                                  context: context,
                                  builder: (context) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.memory(
                                        base64Decode(m['image']),
                                      ),
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    base64Decode(m['image']),
                                    width: 220,
                                  ),
                                ),
                              ),
                            if (m['text'] != '') cText(m['text']),
                            const SizedBox(height: 5),
                            cText(_chatTime(m['time']), size: 10),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: listingSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: listingBorder),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending || widget.sitter['unavailable'] == true
                        ? null
                        : _attach,
                    tooltip: 'Rasm yuborish',
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: listingGold,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('customerChatInput'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Xabar yozing...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _sending || widget.sitter['unavailable'] == true
                        ? null
                        : _send,
                    style: IconButton.styleFrom(backgroundColor: listingGold),
                    icon: ButtonProgress(
                      loading: _sending,
                      child: const Icon(Icons.send_outlined),
                    ),
                    key: const ValueKey('customerChatSend'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
