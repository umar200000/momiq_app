import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../data/conversation_controller.dart';
import '../data/conversation_data.dart';
import '../../customer/presentation/customer_session_boundary.dart';

String chatSessionExpired() => lt(
  'Sessiya o‘zgardi. Suhbatni qayta oching.',
  'The session changed. Reopen the conversation.',
  'Сессия изменилась. Откройте переписку заново.',
);

String reportStatus(String status) => switch (status) {
  'removed' => lt('Xabar yashirildi', 'Message hidden', 'Сообщение скрыто'),
  'dismissed' => lt(
    'Qoidabuzarlik tasdiqlanmadi',
    'Violation not confirmed',
    'Нарушение не подтверждено',
  ),
  _ => lt('Ko‘rib chiqilmoqda', 'Under review', 'На рассмотрении'),
};

class ChatReportDialog extends StatelessWidget {
  const ChatReportDialog({
    super.key,
    required this.api,
    required this.conversationId,
    required this.messageId,
  });
  final CustomerApi api;
  final String conversationId, messageId;
  @override
  Widget build(BuildContext context) => CustomerSessionBoundary(
    api: api,
    expired: AlertDialog(
      scrollable: true,
      content: Text(chatSessionExpired()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(lt('Yopish', 'Close', 'Закрыть')),
        ),
      ],
    ),
    child: _BoundChatReportDialog(
      key: ValueKey((api, conversationId, messageId)),
      api: api,
      conversationId: conversationId,
      messageId: messageId,
    ),
  );
}

class _BoundChatReportDialog extends StatefulWidget {
  const _BoundChatReportDialog({
    super.key,
    required this.api,
    required this.conversationId,
    required this.messageId,
  });
  final CustomerApi api;
  final String conversationId, messageId;
  @override
  State<_BoundChatReportDialog> createState() => _ChatReportDialogState();
}

class _ChatReportDialogState extends State<_BoundChatReportDialog> {
  final _reason = TextEditingController();
  final _session = CustomerApi.sessionVersion;
  bool get _live => mounted && _session == CustomerApi.sessionVersion;
  final _requestId = chatRequestId();
  String? _error;
  bool _busy = false;
  String? _submittedReason;
  Future<void> _submit() async {
    if (!_live || _busy || _reason.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _submittedReason ??= _reason.text.trim();
    try {
      final response = await widget.api
          .request('POST', '/conversations/${widget.conversationId}/reports', {
            'messageId': widget.messageId,
            'reason': _submittedReason,
            'requestId': _requestId,
          });
      if (!_live) return;
      chatReport(
        response,
        messageId: widget.messageId,
        reason: _submittedReason,
      );
      if (mounted && _live) {
        final route = ModalRoute.of(context);
        if (route != null && route.isActive) {
          route.navigator?.removeRoute(route, true);
        }
      }
    } catch (_) {
      if (_live) {
        setState(
          () => _error = lt(
            'Murojaat tasdiqlanmadi. Qayta urinib ko‘ring yoki murojaatlar tarixini tekshiring.',
            'Report not confirmed. Retry or check your report history.',
            'Обращение не подтверждено. Повторите или проверьте историю.',
          ),
        );
      }
    } finally {
      if (_live) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy || !_live,
    child: AlertDialog(
      scrollable: true,
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

class ChatReportsPage extends StatelessWidget {
  const ChatReportsPage({
    super.key,
    required this.api,
    required this.conversationId,
  });
  final CustomerApi api;
  final String conversationId;
  @override
  Widget build(BuildContext context) => CustomerSessionBoundary(
    api: api,
    expired: Scaffold(body: Center(child: Text(chatSessionExpired()))),
    child: _BoundChatReportsPage(
      key: ValueKey((api, conversationId)),
      api: api,
      conversationId: conversationId,
    ),
  );
}

class _BoundChatReportsPage extends StatefulWidget {
  const _BoundChatReportsPage({
    super.key,
    required this.api,
    required this.conversationId,
  });
  final CustomerApi api;
  final String conversationId;
  @override
  State<_BoundChatReportsPage> createState() => _ChatReportsPageState();
}

class _ChatReportsPageState extends State<_BoundChatReportsPage> {
  final _items = <ChatJson>[];
  final _session = CustomerApi.sessionVersion;
  bool get _live => mounted && _session == CustomerApi.sessionVersion;
  bool _busy = false, _failed = false;
  String? _cursor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!_live || _busy || (more && _cursor == null)) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final before = more ? _cursor : null;
      final response = await widget.api.request(
        'GET',
        '/conversations/${widget.conversationId}/reports${more ? '?before=$_cursor' : ''}',
      );
      if (!_live) return;
      final page = chatReportPage(response, before: before);
      setState(() {
        if (!more) _items.clear();
        _items.addAll((page['items'] as List).map((r) => ChatJson.from(r)));
        _cursor = page['nextCursor'];
      });
    } catch (_) {
      if (_live) setState(() => _failed = true);
    } finally {
      if (_live) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Murojaatlarim', 'My reports', 'Мои обращения')),
      actions: [
        IconButton(
          tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
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
