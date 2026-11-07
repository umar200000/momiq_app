import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Remove only the app's disposable picker copy after its encrypted draft was
/// flushed. Never delete an original gallery file or follow a link outside temp.
Future<bool> discardVideoPickerCopy(
  String path, {
  Future<Directory> Function()? temporary,
}) async {
  try {
    final root = await (temporary ?? getTemporaryDirectory)();
    final canonicalRoot = await root.resolveSymbolicLinks();
    final file = File(path);
    if (!await file.exists()) return false;
    final canonicalFile = await file.resolveSymbolicLinks();
    if (!canonicalFile.startsWith('$canonicalRoot${Platform.pathSeparator}')) {
      return false;
    }
    await File(canonicalFile).delete();
    return true;
  } on FileSystemException {
    // The sandbox/OS owns transient picker cache cleanup if a file is still held.
    return false;
  }
}
