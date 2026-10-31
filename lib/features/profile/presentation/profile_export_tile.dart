import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/owned_dialogs.dart';
import '../../chat/data/conversation_controller.dart' show chatRequestId;
import '../../customer/data/customer_api.dart';
import '../../listings/presentation/listing_style.dart' show lt;

final _exportName = RegExp(r'^momiq-profile-[A-Za-z0-9_-]{32}\.json$');

Future<void> _removeTemporaryExport(File file) async {
  try {
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await file.delete();
    }
  } on FileSystemException {
    // Retry only this feature's temporary files at the next process start.
  }
}

Future<void> clearInterruptedProfileExports() async {
  if (!Platform.isIOS) return;
  try {
    await for (final file in Directory.systemTemp.list(followLinks: false)) {
      if (file is File && _exportName.hasMatch(file.uri.pathSegments.last)) {
        await _removeTemporaryExport(file);
      }
    }
  } on FileSystemException {
    // Unavailable temporary storage must not prevent account access.
  }
}

Future<Uri?> _save(String name, Uint8List bytes) async {
  try {
    return await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: 'application/json',
    );
  } finally {
    if (Platform.isIOS) {
      await _removeTemporaryExport(
        File.fromUri(Directory.systemTemp.uri.resolve(name)),
      );
    }
  }
}

class ProfileExportTile extends StatefulWidget {
  const ProfileExportTile({super.key, required this.api, this.save = _save});
  final CustomerApi api;
  final Future<Uri?> Function(String, Uint8List) save;
  @override
  State<ProfileExportTile> createState() => _ProfileExportState();
}

class _ProfileExportState extends State<ProfileExportTile>
    with OwnedDialogs<ProfileExportTile> {
  final session = CustomerApi.sessionVersion;
  bool busy = false;
  String? message;
  bool current(CustomerApi source) =>
      mounted &&
      identical(source, widget.api) &&
      session == CustomerApi.sessionVersion &&
      identical(source, CustomerApi.active);

  Future<void> export() async {
    final source = widget.api;
    if (busy || !current(source)) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final confirmed = await showOwnedDialog<bool>(
        builder: (context) => AlertDialog(
          title: Text(
            lt(
              'Profil nusxasini saqlash',
              'Save profile copy',
              'Сохранить копию профиля',
            ),
          ),
          content: Text(
            lt(
              'JSON faylga telefon, saqlangan manzillar, hayvonlar va sozlamalar yoziladi. Fayl siz tanlagan joyda saqlanadi.',
              'The JSON file includes your phone, saved addresses, pets and settings. Choose where to save it.',
              'В JSON-файл войдут телефон, сохранённые адреса, питомцы и настройки. Выберите место сохранения.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(lt('Ortga', 'Back', 'Назад')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                lt('Joy tanlash', 'Choose location', 'Выбрать место'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !current(source)) return;
      final data = await source.request('GET', '/me/profile-export');
      if (!current(source)) return;
      if (data['format'] != 'momiq-profile-v1' ||
          data['ownerId'] != source.userId ||
          data['generatedAt'] is! String ||
          DateTime.tryParse(data['generatedAt']) == null ||
          data['profile'] is! Map ||
          data['addresses'] is! List ||
          data['pets'] is! List ||
          data['preferences'] is! Map) {
        throw const FormatException('Invalid owner export');
      }
      final bytes = Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent('  ').convert({
            for (final key in [
              'format',
              'ownerId',
              'generatedAt',
              'profile',
              'addresses',
              'pets',
              'sitterProfile',
              'preferences',
            ])
              key: data[key],
          }),
        ),
      );
      final saved = await widget.save(
        'momiq-profile-${chatRequestId()}.json',
        bytes,
      );
      if (current(source) && saved != null) {
        setState(
          () => message = lt('Nusxa saqlandi', 'Copy saved', 'Копия сохранена'),
        );
      }
    } catch (_) {
      if (current(source)) {
        setState(
          () => message = lt(
            'Nusxani saqlab bo‘lmadi',
            'Could not save the copy',
            'Не удалось сохранить копию',
          ),
        );
      }
    } finally {
      if (current(source)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('saveProfileExport'),
    leading: const Icon(Icons.download_outlined),
    title: Text(
      lt(
        'Profil nusxasini saqlash',
        'Save profile copy',
        'Сохранить копию профиля',
      ),
    ),
    subtitle: message == null ? null : Text(message!),
    onTap: busy || !current(widget.api) ? null : export,
  );
}
