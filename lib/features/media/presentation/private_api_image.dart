import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;

/// Explicit, authenticated image reads bound to their source and session.
class PrivateApiImage extends StatefulWidget {
  const PrivateApiImage({
    super.key,
    required this.api,
    required this.path,
    required this.label,
    this.height = 180,
    this.width,
  });
  final CustomerApi api;
  final String path, label;
  final double height;
  final double? width;
  @override
  State<PrivateApiImage> createState() => _PrivateApiImageState();
}

class _PrivateApiImageState extends State<PrivateApiImage> {
  int session = CustomerApi.sessionVersion, generation = 0;
  Uint8List? bytes;
  bool busy = false, failed = false;
  bool get live =>
      mounted &&
      session == CustomerApi.sessionVersion &&
      (CustomerApi.active == null || identical(CustomerApi.active, widget.api));

  @override
  void didUpdateWidget(PrivateApiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api, widget.api) ||
        oldWidget.path != widget.path) {
      generation++;
      if (!identical(oldWidget.api, widget.api)) {
        session = CustomerApi.sessionVersion;
      }
      bytes = null;
      busy = false;
      failed = false;
    }
  }

  Future<void> load() async {
    if (!live || busy) return;
    final requestGeneration = generation;
    final api = widget.api, path = widget.path;
    bool current() =>
        live &&
        requestGeneration == generation &&
        identical(api, widget.api) &&
        path == widget.path;
    setState(() {
      busy = true;
      failed = false;
      bytes = null;
    });
    try {
      final result = await api.request('GET', path);
      if (!current()) return;
      final encoded = result['image'];
      if (encoded is! String ||
          encoded.isEmpty ||
          encoded.length > 4 * 1024 * 1024) {
        throw const FormatException('Invalid image');
      }
      final decoded = base64Decode(encoded);
      setState(() => bytes = decoded);
    } catch (_) {
      if (current()) setState(() => failed = true);
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  String get failure => lt(
    'Rasm ochilmadi. Qayta urinib ko‘ring.',
    'Could not open image. Retry.',
    'Не удалось открыть фото. Повторите.',
  );

  @override
  Widget build(BuildContext context) {
    if (!live) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bytes != null)
          Image.memory(
            bytes!,
            height: widget.height,
            width: widget.width,
            fit: BoxFit.contain,
            semanticLabel: widget.label,
            errorBuilder: (_, _, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(failure),
                TextButton(
                  onPressed: busy ? null : load,
                  child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
                ),
              ],
            ),
          ),
        if (failed) Text(failure),
        if (bytes == null)
          TextButton.icon(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.image),
            label: Text(widget.label),
          ),
        if (busy) const LinearProgressIndicator(),
      ],
    );
  }
}
