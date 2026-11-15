import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves a stored download path without escaping its owning directory.
///
/// iOS may move an application's data container on upgrade/restore. Legacy
/// metadata contains absolute paths, so a missing old path can be relocated
/// only when its complete Documents/comic_downloads/book/chapter suffix agrees
/// with the current directory. Never repair an arbitrary path by basename.
abstract final class DownloadedFilePath {
  static String? resolve(
    String storedPath, {
    required String rootPath,
    required String directoryPath,
    required bool relocateIOSContainer,
  }) {
    if (storedPath.isEmpty || storedPath.contains('\u0000')) return null;
    final uri = Uri.tryParse(storedPath);
    if (uri != null && uri.hasScheme && !p.windows.isAbsolute(storedPath)) {
      return null;
    }
    final segments = storedPath.replaceAll('\\', '/').split('/');
    if (segments.any((segment) => segment == '..' || segment == '.')) {
      return null;
    }

    final directory = p.normalize(p.absolute(directoryPath));
    final stored = p.normalize(storedPath);
    if (p.isAbsolute(stored)) {
      if (p.isWithin(directory, stored)) return stored;
    } else {
      final candidate = p.normalize(p.join(directory, stored));
      return p.isWithin(directory, candidate) ? candidate : null;
    }
    if (!relocateIOSContainer) return null;

    // Use POSIX paths even in Windows regression tests that model an iOS move.
    final root = rootPath.replaceAll('\\', '/');
    final targetDirectory = directoryPath.replaceAll('\\', '/');
    final old = storedPath.replaceAll('\\', '/');
    if (p.posix.basename(root) != 'comic_downloads' ||
        p.posix.basename(p.posix.dirname(root)) != 'Documents' ||
        !p.posix.isWithin(root, targetDirectory)) {
      return null;
    }
    final relativeDirectory = p.posix.relative(targetDirectory, from: root);
    final suffix = '/Documents/comic_downloads/$relativeDirectory/';
    final index = old.lastIndexOf(suffix);
    if (index < 0 || !old.startsWith('/')) return null;
    final oldContainer = old.substring(0, index);
    // Both physical devices and CoreSimulator use this data-container layout.
    if (!RegExp(
      r'/Containers/Data/Application/[^/]+$',
    ).hasMatch(oldContainer)) {
      return null;
    }
    final relativeFile = old.substring(index + suffix.length);
    if (relativeFile.isEmpty || p.posix.isAbsolute(relativeFile)) return null;
    final candidate = p.normalize(p.join(directory, relativeFile));
    if (!p.isWithin(directory, candidate) || !File(candidate).existsSync()) {
      return null;
    }
    return candidate;
  }
}
