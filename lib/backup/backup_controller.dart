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

/// The upload committed; only retention failed. Never retry the upload as if
/// the new file were missing.
class BackupRetentionException implements Exception {
  final WebDavBackupEntry entry;
  final Object error;
  final StackTrace stackTrace;

  const BackupRetentionException(this.entry, this.error, this.stackTrace);
}

typedef WebDavClientFactory =
    WebDavClient Function({
      required WebDavConfig config,
      required WebDavCredentials credentials,
    });

/// Shared local/WebDAV pipeline and cancellation/progress state. Widgets own
/// confirmations; this class never serializes a second preferences snapshot.
class BackupController extends ChangeNotifier {
  final SettingsBackupService service;
  final BackupCodec codec;
  BackupOperation _operation = BackupOperation.idle;
  CancelToken? _cancel;
  double? _progress;
  bool _disposed = false;

  final WebDavClientFactory _createClient;

  BackupController({
    required this.service,
    required this.codec,
    WebDavClientFactory createClient = WebDavClient.new,
  }) : _createClient = createClient;

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
    final client = _createClient(config: config, credentials: credentials);
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
    EncodedBackup backup, {
    int retentionLimit = 0,
  }) async {
    WebDavBackupEntry? committed;
    try {
      return await _remote(BackupOperation.uploading, config, credentials, (
        client,
        cancel,
      ) async {
        final entry = await client.upload(
          backup,
          cancel: cancel,
          onProgress: _onProgress,
        );
        committed = entry;
        if (retentionLimit > 0) {
          await _prune(client, cancel, entry, retentionLimit);
        }
        return entry;
      });
    } catch (error, stack) {
      // Includes _run's final cancellation check, after the remote action.
      final entry = committed;
      if (entry == null) rethrow;
      Error.throwWithStackTrace(
        BackupRetentionException(entry, error, stack),
        stack,
      );
    }
  }

  Future<void> _prune(
    WebDavClient client,
    CancelToken cancel,
    WebDavBackupEntry committed,
    int limit,
  ) async {
    _stage(BackupOperation.listing);
    final files = await client.list(cancel: cancel, confirmedFilesOnly: true);
    // Include the commit even if the server hasn't listed it yet.
    final all = files.any((file) => file.name == committed.name)
        ? files
        : [...files, committed];
    final dated =
        [
          for (final file in all)
            if (file.generatedAt case final time?) (file: file, time: time),
        ]..sort((a, b) {
          final cmp = a.time.compareTo(b.time);
          return cmp != 0 ? cmp : a.file.name.compareTo(b.file.name);
        });
    if (dated.length <= limit) return;
    // Keep the newest N *and* the committed entry. After clock rollback
    // they may not overlap: don't delete another device's newer backup.
    final expired = dated
        .take(dated.length - limit)
        .map((e) => e.file)
        .where((e) => e.name != committed.name);
    if (expired.isEmpty) return;
    _stage(BackupOperation.deleting);
    await _deleteFiles(client, cancel, expired);
  }

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
  ) => deleteMany(config, credentials, [entry], onDeleted: (_) {});

  Future<void> deleteMany(
    WebDavConfig config,
    WebDavCredentials credentials,
    List<WebDavBackupEntry> entries, {
    required void Function(WebDavBackupEntry) onDeleted,
  }) => _remote(
    BackupOperation.deleting,
    config,
    credentials,
    (client, cancel) =>
        _deleteFiles(client, cancel, List.of(entries), onDeleted: onDeleted),
  );

  Future<void> _deleteFiles(
    WebDavClient client,
    CancelToken cancel,
    Iterable<WebDavBackupEntry> entries, {
    void Function(WebDavBackupEntry)? onDeleted,
  }) async {
    for (final entry in entries) {
      await client.delete(entry, cancel: cancel);
      onDeleted?.call(entry);
    }
  }

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
