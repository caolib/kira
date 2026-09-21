import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../utils/settings_backup.dart';
import 'backup_codec.dart';
import 'webdav_client.dart';
import 'webdav_config.dart';

enum BackupOperation {
  idle,
  reading,
  compressing,
  encrypting,
  decoding,
  testing,
  listing,
  uploading,
  downloading,
  restoring,
  deleting,
}

/// Shared local/WebDAV pipeline and cancellation/progress state. Widgets own
/// confirmations; this class never serializes a second preferences snapshot.
class BackupController extends ChangeNotifier {
  final SettingsBackupService service;
  final BackupCodec codec;
  BackupOperation _operation = BackupOperation.idle;
  CancelToken? _cancel;
  double? _progress;
  bool _disposed = false;

  BackupController({required this.service, required this.codec});

  BackupOperation get operation => _operation;
  double? get progress => _progress;
  bool get busy => _operation != BackupOperation.idle;
  bool get cancelling => _cancel?.isCancelled ?? false;
  bool get canCancel => busy && _operation != BackupOperation.restoring;

  void cancel() {
    if (!canCancel) return;
    _cancel?.cancel();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _stage(BackupOperation operation) {
    _operation = operation;
    _progress = null;
    _notify();
  }

  Future<T> _run<T>(
    BackupOperation operation,
    Future<T> Function(CancelToken cancel) action,
  ) async {
    if (busy) {
      throw const SettingsBackupException(SettingsBackupErrorCode.busy);
    }
    final cancel = CancelToken();
    _cancel = cancel;
    _stage(operation);
    try {
      final result = await action(cancel);
      if (cancel.isCancelled) backupCancelled();
      return result;
    } finally {
      _cancel = null;
      _stage(BackupOperation.idle);
    }
  }

  /// Per-category sizes for the content list. A read-only preview, so it stays
  /// outside [_run]: it must never block or compete with a real backup.
  Future<Map<BackupCategory, BackupCategorySummary>> measureCategories() async {
    final snapshot = await service.capture();
    return measureBackupCategories(snapshot);
  }

  Future<PreparedBackup> prepare(Set<BackupCategory> categories) =>
      _run(BackupOperation.reading, (cancel) async {
        final snapshot = await service.capture();
        if (cancel.isCancelled) backupCancelled();
        _stage(BackupOperation.compressing);
        return codec.prepare(snapshot.select(categories));
      });

  Future<EncodedBackup> encode(PreparedBackup prepared, {String? password}) =>
      _run(
        BackupOperation.encrypting,
        (_) => codec.encode(prepared, password: password),
      );

  Future<BackupDocument> decode(Uint8List bytes, {String? password}) => _run(
    BackupOperation.decoding,
    (_) => codec.decode(bytes, password: password),
  );

  Future<Uint8List> readLocal(PlatformFile file) => _run(
    BackupOperation.reading,
    (cancel) async {
      if (await file.length() > BackupCodec.maxFileBytes) {
        throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
      }
      final output = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (cancel.isCancelled) backupCancelled();
        if (output.length + chunk.length > BackupCodec.maxFileBytes) {
          throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
        }
        output.add(chunk);
      }
      return output.takeBytes();
    },
  );

  Future<void> restore(
    BackupDocument document,
    Set<BackupCategory> categories,
  ) => _run(BackupOperation.restoring, (_) async {
    await service.restore(document, categories);
  });

  Future<T> _remote<T>(
    BackupOperation operation,
    WebDavConfig config,
    WebDavCredentials credentials,
    Future<T> Function(WebDavClient client, CancelToken cancel) action,
  ) => _run(operation, (cancel) async {
    final client = WebDavClient(config: config, credentials: credentials);
    try {
      return await action(client, cancel);
    } finally {
      client.close();
    }
  });

  Future<void> test(WebDavConfig config, WebDavCredentials credentials) =>
      _remote(
        BackupOperation.testing,
        config,
        credentials,
        (client, cancel) => client.testConnection(cancel: cancel),
      );

  Future<List<WebDavBackupEntry>> list(
    WebDavConfig config,
    WebDavCredentials credentials,
  ) => _remote(
    BackupOperation.listing,
    config,
    credentials,
    (client, cancel) => client.list(cancel: cancel),
  );

  Future<WebDavBackupEntry> upload(
    WebDavConfig config,
    WebDavCredentials credentials,
    EncodedBackup backup,
  ) => _remote(
    BackupOperation.uploading,
    config,
    credentials,
    (client, cancel) =>
        client.upload(backup, cancel: cancel, onProgress: _onProgress),
  );

  Future<Uint8List> download(
    WebDavConfig config,
    WebDavCredentials credentials,
    WebDavBackupEntry entry,
  ) => _remote(
    BackupOperation.downloading,
    config,
    credentials,
    (client, cancel) =>
        client.download(entry, cancel: cancel, onProgress: _onProgress),
  );

  Future<void> delete(
    WebDavConfig config,
    WebDavCredentials credentials,
    WebDavBackupEntry entry,
  ) => _remote(
    BackupOperation.deleting,
    config,
    credentials,
    (client, cancel) => client.delete(entry, cancel: cancel),
  );

  void _onProgress(int count, int total) {
    _progress = total > 0 ? (count / total).clamp(0, 1) : null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    if (canCancel) _cancel?.cancel();
    super.dispose();
  }
}
