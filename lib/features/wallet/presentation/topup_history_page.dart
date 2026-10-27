import 'dart:convert';
import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import 'wallet_page.dart';

class TopupHistoryPage extends StatefulWidget {
  const TopupHistoryPage({super.key, required this.api, required this.topupId});
  final CustomerApi api;
  final String topupId;
  @override
  State<TopupHistoryPage> createState() => _TopupHistoryPageState();
}

class _TopupHistoryPageState extends State<TopupHistoryPage> {
  final List<Map<String, dynamic>> _items = [];
  final Set<int> _opening = {};
  String? _cursor, _error;
  bool _busy = false, _amending = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.api.request(
        'GET',
        '/wallet/topups/${widget.topupId}/history${more ? '?before=$_cursor' : ''}',
      );
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(
          (page['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
        _cursor = page['nextCursor'] as String?;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = lt(
            'Tarix yuklanmadi. Qayta urinib ko‘ring.',
            'Could not load history. Retry.',
            'Не удалось загрузить историю. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _event(String event) => switch (event) {
    'created' => lt('Yuborilgan', 'Submitted', 'Отправлено'),
    'migrated' => lt(
      'Eski yozuvning nusxasi',
      'Imported evidence',
      'Импортированная запись',
    ),
    'request_info' => lt(
      'Aniqlashtirish so‘ralgan',
      'Clarification requested',
      'Запрошено уточнение',
    ),
    'resubmitted' => lt(
      'Qayta yuborilgan',
      'Resubmitted',
      'Отправлено повторно',
    ),
    'approve' => lt('Tasdiqlangan', 'Approved', 'Одобрено'),
    'reject' => lt('Rad etilgan', 'Rejected', 'Отклонено'),
    _ => event,
  };

  String _money(int minor) =>
      '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')} UZS';
  String _date(String value) {
    final date = DateTime.parse(value).toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(date)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  Future<void> _receipt(int revision) async {
    if (!_opening.add(revision)) return;
    setState(() {});
    try {
      final result = await widget.api.request(
        'GET',
        '/wallet/topups/${widget.topupId}/history/$revision/receipt',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            lt(
              'Chekning v$revision nusxasi',
              'Receipt v$revision',
              'Чек v$revision',
            ),
          ),
          content: SingleChildScrollView(
            child: Image.memory(base64Decode(result['receipt'] as String)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(lt('Yopish', 'Close', 'Закрыть')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lt(
                'Chek ochilmadi. Qayta urinib ko‘ring.',
                'Could not open receipt. Retry.',
                'Не удалось открыть чек. Повторите.',
              ),
            ),
          ),
        );
      }
    } finally {
      _opening.remove(revision);
      if (mounted) setState(() {});
    }
  }

  Future<void> _amend() async {
    if (_busy || _amending) return;
    setState(() => _amending = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WalletPage(api: widget.api, topupId: widget.topupId),
        ),
      );
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _amending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Chek tarixi', 'Receipt history', 'История чека')),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_items.isNotEmpty &&
              const {'needs_info', 'rejected'}.contains(_items.first['status']))
            OutlinedButton.icon(
              key: const ValueKey('amendHistoryTopup'),
              onPressed: _busy || _amending || _error != null ? null : _amend,
              icon: const Icon(Icons.edit_note),
              label: Text(
                lt('Chekni to‘ldirish', 'Update receipt', 'Дополнить чек'),
              ),
            ),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
            ),
          ],
          for (final item in _items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_event(item['event'])} · v${item['revision']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${_money(item['amountMinor'] as int)} · QR v${item['qrVersion']}',
                    ),
                    if ((item['reason'] as String).isNotEmpty)
                      Text(item['reason'] as String),
                    if ((item['payerReference'] as String).isNotEmpty)
                      Text(item['payerReference'] as String),
                    Text(_date(item['created'] as String)),
                    TextButton(
                      onPressed: _opening.contains(item['revision'])
                          ? null
                          : () => _receipt(item['revision'] as int),
                      child: Text(
                        lt(
                          'Shu bosqichdagi chek',
                          'Receipt at this step',
                          'Чек на этом этапе',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_cursor != null)
            TextButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: Text(lt('Yana yuklash', 'Load more', 'Загрузить ещё')),
            ),
        ],
      ),
    ),
  );
}
