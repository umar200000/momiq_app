import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../data/conversation_controller.dart';

String reportStatus(String status) => switch (status) {
  'removed' => lt('Xabar yashirildi', 'Message hidden', 'Сообщение скрыто'),
  'dismissed' => lt(
    'Qoidabuzarlik tasdiqlanmadi',
    'Violation not confirmed',
    'Нарушение не подтверждено',
  ),
  _ => lt('Ko‘rib chiqilmoqda', 'Under review', 'На рассмотрении'),
};

class ChatReportDialog extends StatefulWidget {
  const ChatReportDialog({
    super.key,
    required this.api,
    required this.conversationId,
    required this.messageId,
  });
  final CustomerApi api;
  final String conversationId, messageId;
  @override
  State<ChatReportDialog> createState() => _ChatReportDialogState();
}

class _ChatReportDialogState extends State<ChatReportDialog> {
  final _reason = TextEditingController();
  final _requestId = chatRequestId();
  String? _error;
  bool _busy = false;
  String? _submittedReason;
  Future<void> _submit() async {
    if (_busy || _reason.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _submittedReason ??= _reason.text.trim();
    try {
      await widget.api
          .request('POST', '/conversations/${widget.conversationId}/reports', {
            'messageId': widget.messageId,
            'reason': _submittedReason,
            'requestId': _requestId,
          });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = lt(
            'Murojaat tasdiqlanmadi. Qayta urinib ko‘ring yoki murojaatlar tarixini tekshiring.',
            'Report not confirmed. Retry or check your report history.',
            'Обращение не подтверждено. Повторите или проверьте историю.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        lt(
          'Xabar ustidan shikoyat',
          'Report message',
          'Пожаловаться на сообщение',
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              lt(
                'Shu xabar va biriktirilgan rasm moderatorga tekshirish uchun yuboriladi. Bu foydalanuvchini avtomatik bloklamaydi.',
                'This message and its image will be available to the moderator. Reporting does not automatically block the user.',
                'Сообщение и фото будут доступны модератору. Жалоба не блокирует пользователя автоматически.',
              ),
            ),
            TextField(
              key: const ValueKey('chatReportReason'),
              controller: _reason,
              enabled: !_busy && _submittedReason == null,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: lt('Sabab', 'Reason', 'Причина'),
              ),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(lt('Yopish', 'Close', 'Закрыть')),
        ),
        FilledButton(
          key: const ValueKey('chatReportSubmit'),
          onPressed: _busy ? null : _submit,
          child: Text(lt('Yuborish', 'Submit', 'Отправить')),
        ),
      ],
    ),
  );
}

class ChatReportsPage extends StatefulWidget {
  const ChatReportsPage({
    super.key,
    required this.api,
    required this.conversationId,
  });
  final CustomerApi api;
  final String conversationId;
  @override
  State<ChatReportsPage> createState() => _ChatReportsPageState();
}

class _ChatReportsPageState extends State<ChatReportsPage> {
  final _items = <ChatJson>[];
  bool _busy = false, _failed = false;
  String? _cursor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final page = await widget.api.request(
        'GET',
        '/conversations/${widget.conversationId}/reports${more ? '?before=$_cursor' : ''}',
      );
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll((page['items'] as List).map((r) => ChatJson.from(r)));
        _cursor = page['nextCursor'];
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Murojaatlarim', 'My reports', 'Мои обращения')),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_failed)
          Text(
            lt(
              'Yuklanmadi. Qayta urinib ko‘ring.',
              'Could not load. Please retry.',
              'Не удалось загрузить. Повторите.',
            ),
          ),
        if (!_busy && !_failed && _items.isEmpty)
          Text(lt('Murojaat yo‘q.', 'No reports.', 'Обращений нет.')),
        for (final item in _items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reportStatus(item['status']),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(item['reason']),
                  if (item['reviewReason'] != null) Text(item['reviewReason']),
                ],
              ),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: Text(lt('Yana', 'More', 'Ещё')),
          ),
      ],
    ),
  );
}
