import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import '../../listings/presentation/listing_style.dart' show lt;

/// Only the operator's payment QR is exported. Receipts remain private.
class PaymentQr extends StatefulWidget {
  const PaymentQr({
    super.key,
    required this.bytes,
    required this.version,
    required this.recipient,
    required this.testOnly,
    this.saveImage,
  });
  final Uint8List bytes;
  final int version;
  final String recipient;
  final bool testOnly;
  final Future<void> Function(Uint8List bytes, String name)? saveImage;

  @override
  State<PaymentQr> createState() => _PaymentQrState();
}

class _PaymentQrState extends State<PaymentQr> {
  bool _saving = false;
  String? _message;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final name =
          '${widget.testOnly ? 'TEST-' : ''}Momiq-QR-v${widget.version}';
      if (widget.saveImage != null) {
        await widget.saveImage!(widget.bytes, name);
      } else {
        await Gal.putImageBytes(widget.bytes, name: name);
      }
      if (mounted) {
        setState(
          () => _message = lt(
            'QR galereyaga saqlandi. To‘lovdan oldin oluvchini tekshiring.',
            'QR saved to your gallery. Check the recipient before paying.',
            'QR сохранён в галерею. Перед оплатой проверьте получателя.',
          ),
        );
      }
    } on GalException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.type) {
            GalExceptionType.accessDenied => lt(
              'Galereyaga saqlash ruxsati berilmadi. Telefon sozlamalaridan ruxsatni tekshiring yoki QR’ni boshqa qurilmadan skanerlang.',
              'Gallery access was denied. Check the app permissions in Settings or scan from another device.',
              'Нет разрешения на сохранение. Проверьте разрешения в настройках или сканируйте с другого устройства.',
            ),
            GalExceptionType.notEnoughSpace => lt(
              'Telefonda bo‘sh joy yetarli emas.',
              'Not enough device storage.',
              'Недостаточно места на устройстве.',
            ),
            _ => lt(
              'QR saqlanmadi. Qayta urinib ko‘ring.',
              'QR was not saved. Please retry.',
              'QR не сохранён. Повторите попытку.',
            ),
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = lt(
            'QR saqlanmadi. Qayta urinib ko‘ring.',
            'QR was not saved. Please retry.',
            'QR не сохранён. Повторите попытку.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _enlarge() => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Paynet Xolis · QR v${widget.version}'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: lt('Yopish', 'Close', 'Закрыть'),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.recipient),
            ),
            if (widget.testOnly)
              Text(
                lt(
                  'TEST — haqiqiy to‘lov qilmang',
                  'TEST — do not pay',
                  'ТЕСТ — не оплачивайте',
                ),
                style: const TextStyle(color: Colors.red),
              ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    widget.bytes,
                    fit: BoxFit.contain,
                    semanticLabel: 'Paynet Xolis QR',
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Image.memory(
        widget.bytes,
        height: 240,
        semanticLabel: 'Paynet Xolis QR',
        errorBuilder: (_, _, _) => Text(
          lt(
            'QR rasm ochilmadi.',
            'Could not load QR.',
            'Не удалось открыть QR.',
          ),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('enlargePaymentQr'),
            onPressed: _enlarge,
            icon: const Icon(Icons.zoom_in),
            label: Text(lt('Kattalashtirish', 'Enlarge', 'Увеличить')),
          ),
          OutlinedButton.icon(
            key: const ValueKey('savePaymentQr'),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.download),
            label: Text(lt('QR’ni saqlash', 'Save QR', 'Сохранить QR')),
          ),
        ],
      ),
      Text(
        lt(
          'Saqlangan QR galereyada qoladi. Har yangi to‘lov oldidan ilovadagi joriy QR’ni oching.',
          'Saved QR stays in your gallery. Open the current QR in the app before each new payment.',
          'QR остаётся в галерее. Перед новой оплатой откройте актуальный QR в приложении.',
        ),
      ),
      if (_message != null)
        Text(_message!, key: const ValueKey('qrSaveResult')),
    ],
  );
}
