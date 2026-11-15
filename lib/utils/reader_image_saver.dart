import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';
import 'app_platform.dart';

/// Photo-library operations shared by the comic and novel image viewers.
abstract final class ReaderImageSaver {
  static String? get _album => AppPlatform.isIOS ? null : 'kira';

  static Future<bool> requestAccess() async {
    final toAlbum = _album != null;
    return await Gal.hasAccess(toAlbum: toAlbum) ||
        await Gal.requestAccess(toAlbum: toAlbum);
  }

  static Future<void> save(Uint8List bytes) async {
    final extension = imageExtension(bytes);
    if (AppPlatform.isIOS && extension == '.webp') {
      // Gal's native file path API force-unwraps PhotoKit's asset request.
      // Convert WebP before crossing that boundary instead of risking a native
      // crash on formats PhotoKit cannot import as a file.
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null) throw StateError('Unable to encode image as PNG');
          await Gal.putImageBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            name: 'kira.png',
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      return;
    }
    if (extension != '.webp') {
      await Gal.putImageBytes(bytes, album: _album, name: 'kira$extension');
      return;
    }

    // Keep the existing Android WebP workaround, with an isolated temporary
    // directory so simultaneous viewers cannot overwrite each other's files.
    final directory = await (await getTemporaryDirectory()).createTemp(
      'kira_save_',
    );
    try {
      final file = File('${directory.path}/image.webp');
      await file.writeAsBytes(bytes, flush: true);
      await Gal.putImage(file.path, album: _album);
    } finally {
      try {
        await directory.delete(recursive: true);
      } catch (error, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            error,
            stackTrace: stack,
            source: 'reader_image_saver.cleanup',
          ),
        );
      }
    }
  }

  static String imageExtension(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return '.gif';
    }
    return '.jpg';
  }
}
