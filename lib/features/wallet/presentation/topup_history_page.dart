import 'dart:convert';
import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import 'wallet_page.dart';
import '../data/topup_history_data.dart';

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
  final List<Map<String, dynamic>> _corrections = [];
  bool _correctionsBusy = false, _correctionsLoaded = false;
  String? _correctionsCursor, _correctionsError;
  int _correctedMinor = 0;
  int _session = CustomerApi.sessionVersion, _generation = 0;
  DialogRoute<void>? _dialog;
  bool get _live =>
      mounted &&
      _session == CustomerApi.sessionVersion &&
      (CustomerApi.active == null || identical(CustomerApi.active, widget.api));
  bool Function() _scope() {
    final generation = _generation, api = widget.api, id = widget.topupId;
    return () =>
        _live &&
        generation == _generation &&
        identical(api, widget.api) &&
        id == widget.topupId;
  }

  void _closeDialog() {
    final dialog = _dialog;
    _dialog = null;
    if (dialog == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = dialog.navigator;
      if (navigator != null && navigator.mounted && dialog.isActive) {
        navigator.removeRoute(dialog);
      }
    });
  }

  @override
  void didUpdateWidget(TopupHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api, widget.api) ||
        oldWidget.topupId != widget.topupId) {
      _closeDialog();
      _generation++;
      if (!identical(oldWidget.api, widget.api)) {
        _session = CustomerApi.sessionVersion;
      }
      _items.clear();
      _corrections.clear();
      _opening.clear();
      _cursor = _error = _correctionsCursor = _correctionsError = null;
      _busy = _amending = _correctionsBusy = _correctionsLoaded = false;
      _correctedMinor = 0;
      _load();
    }
  }

  @override
  void dispose() {
    _closeDialog();
    super.dispose();
  }

  Future<void> _loadCorrections({bool more = false}) async {
    if (!_live || _correctionsBusy || (more && _correctionsCursor == null)) {
      return;
    }
    final current = _scope();
    setState(() {
      _correctionsBusy = true;
      _correctionsError = null;
    });
    try {
      final page = await widget.api.request(
        'GET',
        '/wallet/topups/${widget.topupId}/corrections${more ? '?before=$_correctionsCursor' : ''}',
      );
      if (!current()) return;
      final parsed = topupCorrectionPage(page);
      setState(() {
        if (!more) _corrections.clear();
        _corrections.addAll(
          (parsed['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
        _correctionsCursor = parsed['nextCursor'] as String?;
        _correctedMinor = parsed['correctedMinor'] as int;
        _correctionsLoaded = true;
      });
    } catch (_) {
      if (mounted && current()) {
        setState(
          () => _correctionsError = lt(
            'Tuzatishlar yuklanmadi. Qayta urining.',
            'Could not load corrections. Retry.',
            'Не удалось загрузить исправления. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted && current()) setState(() => _correctionsBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!_live || _busy || (more && _cursor == null)) return;
    final current = _scope();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.api.request(
        'GET',
        '/wallet/topups/${widget.topupId}/history${more ? '?before=$_cursor' : ''}',
      );
      if (!current()) return;
      final parsed = topupHistoryPage(page);
      setState(() {
        if (!more) _items.clear();
        _items.addAll(
          (parsed['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
        _cursor = parsed['nextCursor'] as String?;
      });
    } catch (_) {
      if (mounted && current()) {
        setState(
          () => _error = lt(
            'Tarix yuklanmadi. Qayta urinib ko‘ring.',
            'Could not load history. Retry.',
            'Не удалось загрузить историю. Повторите.',
          ),
        );
      }
    } finally {
      if (mounted && current()) setState(() => _busy = false);
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
    if (!_live || _opening.isNotEmpty || !_opening.add(revision)) return;
    final current = _scope();
    setState(() {});
    try {
      final result = await widget.api.request(
        'GET',
        '/wallet/topups/${widget.topupId}/history/$revision/receipt',
      );
      if (!mounted || !current()) return;
      final encoded = result['receipt'];
      if (encoded is! String ||
          encoded.isEmpty ||
          encoded.length > 4 * 1024 * 1024) {
        throw const FormatException('Invalid receipt');
      }
      final bytes = base64Decode(encoded);
      final dialog = DialogRoute<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
            lt(
              'Chekning v$revision nusxasi',
              'Receipt v$revision',
              'Чек v$revision',
            ),
          ),
          content: SingleChildScrollView(
            child: Image.memory(
              bytes,
              errorBuilder: (_, error, stack) => Text(
                lt(
                  'Chek rasmini ochib bo‘lmadi. Yoping va qayta urining.',
                  'Could not decode receipt. Close and retry.',
                  'Не удалось открыть изображение чека. Закройте и повторите.',
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(lt('Yopish', 'Close', 'Закрыть')),
            ),
          ],
        ),
      );
      _dialog = dialog;
      await Navigator.of(context).push(dialog);
      if (identical(_dialog, dialog)) _dialog = null;
    } catch (_) {
      if (mounted && current()) {
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
      if (mounted && current()) {
        _opening.remove(revision);
        setState(() {});
      }
    }
  }

  Future<void> _amend() async {
    if (!_live || _busy || _amending) return;
    final current = _scope(), api = widget.api, id = widget.topupId;
    setState(() => _amending = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WalletPage(api: api, topupId: id),
        ),
      );
      if (mounted && current()) await _load();
    } finally {
      if (mounted && current()) setState(() => _amending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_live) _closeDialog();
    return Scaffold(
      appBar: AppBar(
        title: Text(lt('Chek tarixi', 'Receipt history', 'История чека')),
      ),
      body: !_live
          ? Center(
              child: Text(
                lt(
                  'Hisobingizga qayta kiring.',
                  'Sign in again.',
                  'Войдите снова.',
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  TextButton(
                    key: const ValueKey('topupCorrections'),
                    onPressed: _correctionsBusy
                        ? null
                        : () => _loadCorrections(),
                    child: Text(
                      lt(
                        'Tushum tuzatishlari',
                        'Top-up corrections',
                        'Корректировки пополнения',
                      ),
                    ),
                  ),
                  if (_correctionsBusy) const LinearProgressIndicator(),
                  if (_correctionsError != null) Text(_correctionsError!),
                  if (_correctionsLoaded) ...[
                    Text(
                      '${lt('Balansdan tuzatish uchun yechilgan', 'Deducted to correct the top-up', 'Списано для исправления пополнения')}: ${_money(_correctedMinor)}',
                    ),
                    Text(
                      lt(
                        'Bu kartaga pul qaytarish emas. Savol bo‘lsa yordam xizmatiga murojaat qiling.',
                        'This is not a refund to a card. Contact support with questions.',
                        'Это не возврат на карту. Если есть вопросы, обратитесь в поддержку.',
                      ),
                    ),
                    for (final item in _corrections)
                      ListTile(
                        title: Text('−${_money(item['amountMinor'] as int)}'),
                        subtitle: Text(
                          '${item['reason']}\n${_date(item['created'] as String)}',
                        ),
                      ),
                    if (_correctionsCursor != null)
                      TextButton(
                        onPressed: _correctionsBusy
                            ? null
                            : () => _loadCorrections(more: true),
                        child: Text(
                          lt(
                            'Oldingi tuzatishlar',
                            'Earlier corrections',
                            'Предыдущие исправления',
                          ),
                        ),
                      ),
                  ],
                  if (_busy) const LinearProgressIndicator(),
                  if (_items.isNotEmpty &&
                      const {
                        'needs_info',
                        'rejected',
                      }.contains(_items.first['status']))
                    OutlinedButton.icon(
                      key: const ValueKey('amendHistoryTopup'),
                      onPressed: _busy || _amending || _error != null
                          ? null
                          : _amend,
                      icon: const Icon(Icons.edit_note),
                      label: Text(
                        lt(
                          'Chekni to‘ldirish',
                          'Update receipt',
                          'Дополнить чек',
                        ),
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
                              onPressed: _opening.isNotEmpty
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
                      child: Text(
                        lt('Yana yuklash', 'Load more', 'Загрузить ещё'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
