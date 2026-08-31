import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'download_manager.dart';

/// 自定义下载目录流程的失败原因。
enum DownloadDirectoryError {
  /// 未授予所需存储权限。
  permissionDenied,

  /// 所选目录不可写（如只读卷、路径转换失败）。
  notWritable,
}

/// 自定义下载目录流程的异常，[reason] 供 UI 映射文案。
class DownloadDirectoryException implements Exception {
  final DownloadDirectoryError reason;

  const DownloadDirectoryException(this.reason);

  @override
  String toString() => 'DownloadDirectoryException($reason)';
}

/// 自定义下载目录的完整流程：授权（仅 Android 需要）→ 系统目录选择器 → 可写探测。
///
/// 返回用户所选目录路径（已规范化）；用户取消返回 null；失败抛出
/// [DownloadDirectoryException]。
Future<String?> pickDownloadDirectory({String? dialogTitle}) async {
  if (!await ensureDownloadStoragePermission()) {
    throw const DownloadDirectoryException(
      DownloadDirectoryError.permissionDenied,
    );
  }

  final path = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
  if (path == null || path.trim().isEmpty) return null;

  final normalized = DownloadManager.normalizeDirectoryPath(path)!;
  final dir = Directory(normalized);
  try {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  } on FileSystemException {
    throw const DownloadDirectoryException(DownloadDirectoryError.notWritable);
  }
  if (!await DownloadManager.isDirectoryWritable(dir)) {
    throw const DownloadDirectoryException(DownloadDirectoryError.notWritable);
  }
  return normalized;
}

/// 确保拥有写公共目录所需的存储权限。
///
/// Android 11+ 走"所有文件访问"系统开关页（MANAGE_EXTERNAL_STORAGE）；
/// Android 10 及以下没有该开关（插件返回 restricted），退化为运行时存储权限。
Future<bool> ensureDownloadStoragePermission() async {
  if (!Platform.isAndroid) return true;

  final manage = await Permission.manageExternalStorage.status;
  if (manage.isGranted) return true;
  if (manage.isRestricted) {
    final storage = await Permission.storage.request();
    return storage.isGranted || storage.isLimited;
  }
  final after = await Permission.manageExternalStorage.request();
  return after.isGranted;
}
