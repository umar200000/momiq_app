import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../listings/presentation/listing_style.dart' show lt;
import '../../customer/data/customer_api.dart';
import '../data/wallet_draft_storage.dart';

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
  const WalletPage({super.key, this.api, this.pickReceipt, this.draftStorage});
  final CustomerApi? api;
  final Future<Uint8List?> Function()? pickReceipt;
  final WalletDraftStorage? draftStorage;
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with WidgetsBindingObserver {
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
  WalletDraftStorage? _draftStorage;
  Timer? _draftTimer;
  bool _paymentStarted = false,
      _paymentSubmitted = false,
      _draftRestored = false,
      _starting = false,
      _draftUnreadable = false;
  String? _draftError;
  int _draftRevision = 0, _savedDraftRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    if (_paymentStarted) unawaited(_saveDraftSafely());
    _amount.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _paymentStarted) {
      _draftTimer?.cancel();
      unawaited(_saveDraftSafely());
    }
  }

  Future<void> _persistDraft() async {
    if (!_paymentStarted ||
        _paymentSubmitted ||
        _draftStorage == null ||
        _paymentConfig == null) {
      return;
    }
    final version = _draftRevision;
    final data = <String, dynamic>{
      'formatVersion': 1,
      'amount': _amount.text,
      'receipt': _receipt == null ? null : base64Encode(_receipt!),
      'requestId': _requestId,
      'config': _paymentConfig,
    };
    await _draftStorage!.write(data);
    if (mounted) {
      setState(() {
        _savedDraftRevision = version;
        _draftError = null;
      });
    }
  }

  Future<void> _saveDraftSafely() async {
    try {
      await _persistDraft();
    } catch (_) {
      if (mounted) {
        setState(
          () => _draftError = lt(
            'Qoralama saqlanmadi. Ilovani yopishdan oldin qayta urinib ko‘ring.',
            'Draft was not saved. Retry before closing the app.',
            'Черновик не сохранён. Повторите перед закрытием приложения.',
          ),
        );
      }
    }
  }

  void _draftChanged() {
    _requestId = null;
    _draftRevision++;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), _saveDraftSafely);
    setState(() {});
  }

  Future<void> _startPayment() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final config = Map<String, dynamic>.from(_paymentConfig!);
      await _draftStorage!.write({
        'formatVersion': 1,
        'amount': '',
        'receipt': null,
        'requestId': null,
        'config': config,
      });
      if (!mounted) return;
      setState(() {
        _paymentConfig = config;
        _paymentStarted = true;
        _paymentSubmitted = false;
        _draftRevision++;
        _savedDraftRevision = _draftRevision;
      });
    } catch (_) {
      _paymentStarted = false;
      _notice(
        lt(
          'QR’ni ochish uchun qoralamani saqlab bo‘lmadi. Qayta urinib ko‘ring.',
          'Could not save the payment draft. Please retry.',
          'Не удалось сохранить черновик. Повторите попытку.',
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _discardDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          lt('Qoralamani bekor qilish?', 'Discard draft?', 'Удалить черновик?'),
        ),
        content: Text(
          lt(
            'Bu amalga oshgan to‘lovni bekor qilmaydi. Agar pul o‘tkazgan bo‘lsangiz, avval chekni yuboring.',
            'This does not cancel a payment. If you already paid, submit the receipt first.',
            'Это не отменяет платёж. Если вы уже оплатили, сначала отправьте чек.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Saqlab qolish', 'Keep draft', 'Оставить')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(lt('Bekor qilish', 'Discard', 'Удалить')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _draftTimer?.cancel();
    try {
      await _draftStorage?.clear();
      if (!mounted) return;
      setState(() {
        _paymentStarted = false;
        _draftRestored = true;
        _draftUnreadable = false;
        _draftError = null;
        _receipt = null;
        _requestId = null;
        _accepted = false;
        _amount.clear();
      });
      await _load();
    } catch (error) {
      _notice(error.toString());
    }
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
      _draftStorage ??=
          widget.draftStorage ??
          EncryptedWalletDraftStorage(
            owner: _api!.userId,
            scope: _api!.baseUrl,
          );
      if (!_draftRestored) {
        try {
          final draft = await _draftStorage!.read();
          if (draft != null) {
            if (draft['formatVersion'] != 1 ||
                draft['amount'] is! String ||
                draft['config'] is! Map) {
              throw const FormatException('Invalid payment draft');
            }
            _paymentConfig = Map<String, dynamic>.from(draft['config']);
            _amount.text = draft['amount'] as String;
            _receipt = draft['receipt'] == null
                ? null
                : base64Decode(draft['receipt'] as String);
            _requestId = draft['requestId'] as String?;
            _paymentStarted = true;
          }
          _draftRestored = true;
        } catch (_) {
          _draftUnreadable = true;
          throw CustomerApiException(
            lt(
              'To‘lov qoralamasini ochib bo‘lmadi. U avtomatik o‘chirilmagan.',
              'Could not open the payment draft. It has not been deleted.',
              'Не удалось открыть черновик платежа. Он не удалён.',
            ),
          );
        }
      }
      final wallet = await _api!.request('GET', '/wallet');
      final topups = await _api!.request('GET', '/wallet/topups');
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _topups = topups['topups'] as List;
          _nextCursor = topups['nextCursor'] as String?;
          if (!_paymentStarted) {
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
            _draftRevision++;
          });
          await _persistDraft();
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
      _draftTimer?.cancel();
      _draftRevision++;
      await _persistDraft(); // Stable retry id must survive before sending money evidence.
      await _api!.request('POST', '/wallet/topups', {
        'requestId': _requestId,
        'amountMinor': value,
        'receipt': base64Encode(_receipt!),
        'qrVersion': config['version'],
        'termsVersion': config['termsVersion'],
        'acceptNonRefundable': true,
      });
      // Lifecycle/dispose saves must not recreate a successfully submitted draft
      // while its queued clear is still completing.
      _paymentSubmitted = true;
      await _draftStorage!.clear();
      if (!mounted) return;
      setState(() {
        _paymentStarted = false;
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
        if (_paymentStarted || _draftUnreadable)
          IconButton(
            tooltip: lt(
              'Qoralamani bekor qilish',
              'Discard draft',
              'Удалить черновик',
            ),
            onPressed: _sending || _picking || _starting ? null : _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
        IconButton(
          tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
          onPressed: _loading || _sending || _starting ? null : _load,
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
    final currentConfig = Map<String, dynamic>.from(wallet['config']);
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
            walletMoney(currentConfig['minimumBalanceMinor'] as int),
      ),
      Text(
        '${lt('Komissiya', 'Commission', 'Комиссия')}: ${(currentConfig['commissionBps'] as int) / 100}%',
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
      else if (!_paymentStarted) ...[
        Text(
          lt(
            'To‘lovni boshlash uchun QR kodni oching. Qoralama shu qurilmada saqlanadi.',
            'Open the QR to start. Your draft will be saved on this device.',
            'Откройте QR для оплаты. Черновик сохранится на этом устройстве.',
          ),
        ),
        FilledButton(
          onPressed: _starting ? null : _startPayment,
          key: const ValueKey('startTopup'),
          child: Text(lt('QR kodni ochish', 'Open QR code', 'Открыть QR-код')),
        ),
      ] else ...[
        Text(
          lt(
            'To‘lov qoralamasi · QR v${config['version']}',
            'Payment draft · QR v${config['version']}',
            'Черновик платежа · QR v${config['version']}',
          ),
        ),
        if (_draftError != null)
          Text(_draftError!, style: const TextStyle(color: Colors.red)),
        if (_draftError != null)
          TextButton(
            onPressed: _saveDraftSafely,
            child: Text(
              lt(
                'Qoralamani qayta saqlash',
                'Retry saving draft',
                'Повторить сохранение',
              ),
            ),
          )
        else
          Text(
            _savedDraftRevision == _draftRevision
                ? lt(
                    'Qoralama shu qurilmada saqlandi. Hisobdan chiqishda o‘chiriladi.',
                    'Draft saved on this device. Signing out removes it.',
                    'Черновик сохранён. При выходе из аккаунта он удаляется.',
                  )
                : lt('Qoralama saqlanmoqda…', 'Saving draft…', 'Сохранение…'),
          ),
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
          onChanged: (_) => _draftChanged(),
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
