import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/secure_credential_store.dart';
import 'backup_codec.dart';
import 'backup_document.dart';
import 'backup_error.dart';

abstract interface class BackupJournal {
  Future<BackupDocument?> read();
  Future<void> save(BackupDocument original);
  Future<void> clear();
}

/// A device-local write-ahead journal. Its random AES key is held in secure
/// storage, NOT derived from (or changed with) the user's backup password.
/// An atomic rename publishes the flushed journal before any prefs are changed.
class EncryptedBackupJournal implements BackupJournal {
  static const _magic = [75, 73, 82, 65, 82, 79, 76, 1]; // KIRAROL + v1
  final Future<Directory> Function() _directory;
  final SecureCredentialStore _secrets;
  final BackupCodec _codec;
  final Cipher _cipher = FlutterCryptography().aesGcm();

  EncryptedBackupJournal({
    Future<Directory> Function()? directory,
    SecureCredentialStore? secrets,
    BackupCodec? codec,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _secrets = secrets ?? SecureCredentialStore(),
       _codec = codec ?? BackupCodec();

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File('${directory.path}/backup-restore.pending');
  }

  Future<SecretKey> _key({bool create = false}) async {
    var raw = await _secrets.readBackupRollbackKey();
    if (raw == null && create) {
      raw = base64Encode(BackupCodec.randomBytes(32));
      await _secrets.writeBackupRollbackKey(raw);
    }
    if (raw == null) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.recoveryRequired,
      );
    }
    final bytes = base64Decode(raw);
    if (bytes.length != 32) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.recoveryRequired,
      );
    }
    return SecretKeyData(bytes, overwriteWhenDestroyed: true);
  }

  @override
  Future<BackupDocument?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    if (await file.length() > BackupCodec.maxFileBytes) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.recoveryRequired,
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length < 36 || !listEquals(bytes.sublist(0, 8), _magic)) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.recoveryRequired,
      );
    }
    final key = await _key();
    try {
      final compressed = await _cipher.decrypt(
        SecretBox(
          bytes.sublist(20, bytes.length - 16),
          nonce: bytes.sublist(8, 20),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: key,
        aad: bytes.sublist(0, 20),
      );
      return await _codec.decode(Uint8List.fromList(compressed));
    } finally {
      key.destroy();
    }
  }

  @override
  Future<void> save(BackupDocument original) async {
    final file = await _file();
    if (await file.exists()) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.recoveryRequired,
      );
    }
    final prepared = await _codec.prepare(original);
    if (prepared.compressed.length + 36 > BackupCodec.maxFileBytes) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
    final key = await _key(create: true);
    try {
      final nonce = BackupCodec.randomBytes(12);
      final header = [..._magic, ...nonce];
      final box = await _cipher.encrypt(
        prepared.compressed,
        secretKey: key,
        nonce: nonce,
        aad: header,
      );
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes([
        ...header,
        ...box.cipherText,
        ...box.mac.bytes,
      ], flush: true);
      await temporary.rename(file.path);
    } finally {
      key.destroy();
    }
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
