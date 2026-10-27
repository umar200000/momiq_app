import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../customer/data/customer_api.dart';

int parseWalletAmount(String text) {
  final value = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Summani 2 kasr xonasigacha kiriting.');
  }
  final parts = value.split('.');
  final minor =
      BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (minor <= BigInt.zero || minor > BigInt.from(100000000000)) {
    throw const FormatException('Summa chegaradan tashqarida.');
  }
  return minor.toInt();
}

String walletMoney(int minor) =>
    '${minor < 0 ? '-' : ''}${minor.abs() ~/ 100}${minor.abs() % 100 == 0 ? '' : '.${(minor.abs() % 100).toString().padLeft(2, '0')}'} so‘m';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, this.api, this.pickReceipt});
  final CustomerApi? api;
  final Future<Uint8List?> Function()? pickReceipt;
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  CustomerApi? _api;
  Map<String, dynamic>? _wallet;
  Map<String, dynamic>? _paymentConfig;
  List<dynamic> _topups = [];
  String? _nextCursor;
  bool _moreLoading = false;
  String? _error;
  bool _loading = true, _sending = false, _picking = false, _accepted = false;
  final _amount = TextEditingController();
  Uint8List? _receipt;
  String? _requestId;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      _api = widget.api ?? await CustomerApi.restore();
      if (_api == null) {
        throw CustomerApiException(
          lt(
            'Hisobingizga kiring.',
            'Sign in to continue.',
            'Войдите в аккаунт.',
          ),
        );
      }
      final wallet = await _api!.request('GET', '/wallet');
      final topups = await _api!.request('GET', '/wallet/topups');
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _topups = topups['topups'] as List;
          _nextCursor = topups['nextCursor'] as String?;
          if (_paymentConfig == null ||
              (_receipt == null && _amount.text.isEmpty)) {
            _paymentConfig = Map<String, dynamic>.from(wallet['config']);
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _more() async {
    if (_moreLoading || _nextCursor == null) return;
    setState(() => _moreLoading = true);
    try {
      final page = await _api!.request(
        'GET',
        '/wallet/topups?cursor=${Uri.encodeComponent(_nextCursor!)}',
      );
      if (mounted) {
        setState(() {
          _topups.addAll(page['topups'] as List);
          _nextCursor = page['nextCursor'] as String?;
        });
      }
    } catch (error) {
      _notice(error.toString());
    } finally {
      if (mounted) setState(() => _moreLoading = false);
    }
  }

  Future<void> _pick() async {
    if (_picking || _sending) return;
    setState(() => _picking = true);
    try {
      Uint8List? bytes;
      if (widget.pickReceipt != null) {
        bytes = await widget.pickReceipt!();
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2400,
          imageQuality: 95,
        );
        bytes = await file?.readAsBytes();
      }
      if (bytes != null) {
        if (bytes.length > 3 * 1024 * 1024) {
          throw CustomerApiException(
            lt(
              'Chek 3 MB dan kichik bo‘lsin.',
              'Receipt must be under 3 MB.',
              'Чек должен быть меньше 3 МБ.',
            ),
          );
        }
        if (mounted) {
          setState(() {
            _receipt = bytes;
            _requestId = null;
          });
        }
      }
    } catch (error) {
      _notice(error.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (_sending || _receipt == null || !_accepted || _api == null) return;
    setState(() => _sending = true);
    try {
      final value = parseWalletAmount(_amount.text);
      final config = _paymentConfig!;
      _requestId ??= base64UrlEncode(
        List<int>.generate(18, (_) => Random.secure().nextInt(256)),
      );
      await _api!.request('POST', '/wallet/topups', {
        'requestId': _requestId,
        'amountMinor': value,
        'receipt': base64Encode(_receipt!),
        'qrVersion': config['version'],
        'termsVersion': config['termsVersion'],
        'acceptNonRefundable': true,
      });
      if (!mounted) return;
      setState(() {
        _receipt = null;
        _requestId = null;
        _accepted = false;
        _amount.clear();
      });
      _notice(
        lt(
          'Chek yuborildi. Balans admin tekshirganidan keyin to‘ldiriladi.',
          'Receipt sent. Your balance changes after admin verification.',
          'Чек отправлен. Баланс пополнится после проверки администратором.',
        ),
      );
      await _load();
    } catch (error) {
      _notice(error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _status(String value) => switch (value) {
    'approved' => lt('Tasdiqlangan', 'Approved', 'Подтверждено'),
    'rejected' => lt('Rad etilgan', 'Rejected', 'Отклонено'),
    _ => lt('Tekshirilmoqda', 'Under review', 'На проверке'),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Momiq balansi', 'Momiq balance', 'Баланс Momiq')),
      actions: [
        IconButton(
          tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
          onPressed: _loading || _sending ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  FilledButton(
                    onPressed: _load,
                    child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
                  ),
                ],
              ),
            ),
          )
        : ListView(padding: const EdgeInsets.all(20), children: _content()),
  );

  List<Widget> _content() {
    final wallet = _wallet!;
    final config = _paymentConfig!;
    final qr = config['qrImage'] as String?;
    return [
      Text(
        walletMoney(wallet['balanceMinor'] as int),
        key: const ValueKey('walletBalance'),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      Text(
        lt(
              'Yangi mijozlar uchun minimal balans: ',
              'Minimum balance for new clients: ',
              'Минимальный баланс для новых клиентов: ',
            ) +
            walletMoney(config['minimumBalanceMinor'] as int),
      ),
      Text(
        '${lt('Komissiya', 'Commission', 'Комиссия')}: ${(config['commissionBps'] as int) / 100}%',
      ),
      const SizedBox(height: 12),
      Text(
        lt(
          'Xizmat pulini mijoz bilan o‘zingiz kelishasiz. Momiq bu pulni qabul qilmaydi.',
          'Arrange the service payment directly with the client. Momiq does not collect it.',
          'Оплату услуги согласуйте с клиентом напрямую. Momiq её не принимает.',
        ),
      ),
      const Divider(height: 32),
      Text('Paynet Xolis', style: Theme.of(context).textTheme.titleLarge),
      if (config['testOnly'] == true)
        Text(
          lt(
            'TEST QR — haqiqiy to‘lov qilmang',
            'TEST QR — do not make a real payment',
            'ТЕСТОВЫЙ QR — не переводите реальные деньги',
          ),
          style: const TextStyle(color: Colors.red),
        ),
      if (qr == null || config['qrActive'] != true)
        Text(
          lt(
            'QR orqali yangi to‘lovlar hozir ochilmagan. Oldingi to‘lov cheki bo‘lsa yordam xizmatiga murojaat qiling.',
            'New QR payments are paused. Contact support if you already paid.',
            'Новые оплаты по QR приостановлены. Если вы уже оплатили, обратитесь в поддержку.',
          ),
        )
      else ...[
        Text(
          '${lt('Oluvchi', 'Recipient', 'Получатель')}: ${config['recipientName'] ?? ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if ((config['paymentInstructions'] as String? ?? '').isNotEmpty)
          Text(config['paymentInstructions'] as String),
        Text(
          lt(
            'Provayderdagi oluvchi nomi bilan solishtiring. Nom mos kelmasa to‘lov qilmang.',
            'Check the recipient name in the provider app. Do not pay if it differs.',
            'Сверьте имя получателя в приложении провайдера. При несовпадении не платите.',
          ),
        ),
        Image.memory(
          base64Decode(qr),
          height: 240,
          semanticLabel: 'Paynet Xolis QR',
          errorBuilder: (_, _, _) => Text(
            lt(
              'QR rasm ochilmadi.',
              'Could not load QR image.',
              'Не удалось открыть QR.',
            ),
          ),
        ),
        Text(
          lt(
            'Provayder ilovasida QR kodni skanerlang. To‘lovdan keyin chekni shu yerga yuboring.',
            'Scan the QR in the provider app, then submit your receipt here.',
            'Отсканируйте QR в приложении провайдера, затем отправьте чек здесь.',
          ),
        ),
        TextField(
          key: const ValueKey('topupAmount'),
          controller: _amount,
          enabled: !_sending,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _requestId = null,
          decoration: InputDecoration(
            labelText: lt(
              'To‘langan summa (so‘m)',
              'Paid amount (UZS)',
              'Оплаченная сумма (сум)',
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('pickTopupReceipt'),
          onPressed: _sending || _picking ? null : _pick,
          icon: const Icon(Icons.receipt_long),
          label: Text(lt('Chekni tanlash', 'Choose receipt', 'Выбрать чек')),
        ),
        if (_receipt != null)
          Image.memory(
            _receipt!,
            height: 160,
            semanticLabel: lt(
              'Tanlangan chek',
              'Selected receipt',
              'Выбранный чек',
            ),
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
          ),
        CheckboxListTile(
          key: const ValueKey('nonRefundableConsent'),
          contentPadding: EdgeInsets.zero,
          value: _accepted,
          onChanged: _sending
              ? null
              : (value) => setState(() => _accepted = value == true),
          title: Text(
            lt(
              'Ishlatilmagan balans qaytarilmasligini tushundim va roziman.',
              'I understand and accept that unused balance is non-refundable.',
              'Я понимаю и принимаю, что неиспользованный баланс не возвращается.',
            ),
          ),
        ),
        FilledButton(
          key: const ValueKey('submitTopup'),
          onPressed: !_accepted || _receipt == null || _sending || _picking
              ? null
              : _submit,
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  lt(
                    'Chekni tekshirishga yuborish',
                    'Submit receipt for review',
                    'Отправить чек на проверку',
                  ),
                ),
        ),
      ],
      const Divider(height: 32),
      Text(
        lt('To‘ldirish so‘rovlari', 'Top-up requests', 'Заявки на пополнение'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      for (final row in _topups)
        ListTile(
          title: Text(walletMoney(row['amountMinor'] as int)),
          subtitle: Text(
            [
              _status(row['status']),
              if (row['reviewReason'] != null) row['reviewReason'],
            ].join(' · '),
          ),
        ),
      if (_nextCursor != null)
        TextButton(
          onPressed: _moreLoading ? null : _more,
          child: Text(lt('Yana yuklash', 'Load more', 'Загрузить ещё')),
        ),
      const Divider(height: 32),
      Text(
        lt('Balans harakatlari', 'Balance history', 'История баланса'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      for (final row in wallet['entries'] as List)
        ListTile(
          title: Text(walletMoney(row['amountMinor'] as int)),
          subtitle: Text(row['reason'] as String),
        ),
    ];
  }
}
