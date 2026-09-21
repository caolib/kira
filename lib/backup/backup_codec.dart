import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';

import 'backup_category.dart';
import 'backup_document.dart';
import 'backup_error.dart';

class PreparedBackup {
  final BackupDocument document;
  final Uint8List compressed;
  final int rawBytes;
  final Map<BackupCategory, BackupCategorySummary> summaries;
  final Duration serializationTime;
  final Duration compressionTime;

  const PreparedBackup({
    required this.document,
    required this.compressed,
    required this.rawBytes,
    required this.summaries,
    required this.serializationTime,
    required this.compressionTime,
  });

  /// Denominator for category shares: compact JSON entries, without envelope.
  int get entryBytes =>
      summaries.values.fold(0, (sum, item) => sum + item.rawBytes);
}

class EncodedBackup {
  final Uint8List bytes;
  final bool encrypted;
  final Duration derivationTime;
  final Duration encryptionTime;

  const EncodedBackup({
    required this.bytes,
    required this.encrypted,
    this.derivationTime = Duration.zero,
    this.encryptionTime = Duration.zero,
  });

  String get extension => encrypted ? '.kirabak' : '.json.gz';
}

/// Content-sniffed, bounded codec. No file name or remote metadata is trusted.
///
/// KIRABAK! | version:u8 | gzip:u8 | PBKDF2:u8 | AES256GCM:u8 |
/// iterations:u32be | salt:16 | nonce:12 | ciphertextLength:u32be |
/// ciphertext:N | tag:16. All 48 header bytes are authenticated as AAD.
class BackupCodec {
  static const maxFileBytes = 16 * 1024 * 1024;
  static const maxContentBytes = 64 * 1024 * 1024;
  static const iterations = 600000;
  static const headerLength = 48;
  static const tagLength = 16;
  static const _magic = [75, 73, 82, 65, 66, 65, 75, 33];
  static final _random = Random.secure();

  final Cryptography _cryptography;

  BackupCodec({Cryptography? cryptography})
    : _cryptography = cryptography ?? FlutterCryptography();

  static Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  static String uniqueFileName(String extension, {DateTime? now}) {
    final time = (now ?? DateTime.now()).toUtc().toIso8601String().replaceAll(
      RegExp('[-:.]'),
      '',
    );
    final id = randomBytes(
      12,
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return 'kira-$time-$id$extension';
  }

  static bool isEncrypted(List<int> bytes) =>
      bytes.length >= _magic.length &&
      listEquals(bytes.sublist(0, _magic.length), _magic);

  Future<PreparedBackup> prepare(BackupDocument document) =>
      compute(_prepareDocument, document, debugLabel: 'backup.gzip');

  Future<EncodedBackup> encode(
    PreparedBackup prepared, {
    String? password,
  }) async {
    final compressed = prepared.compressed;
    if (password == null) {
      _checkFileSize(compressed.length);
      return EncodedBackup(bytes: compressed, encrypted: false);
    }
    if (password.isEmpty) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.passwordRequired,
      );
    }
    _checkFileSize(headerLength + compressed.length + tagLength);
    final header = Uint8List(headerLength)..setRange(0, 8, _magic);
    header.setRange(8, 12, [1, 1, 1, 1]);
    final data = ByteData.sublistView(header);
    data.setUint32(12, iterations);
    final salt = randomBytes(16);
    final nonce = randomBytes(12);
    header
      ..setRange(16, 32, salt)
      ..setRange(32, 44, nonce);
    data.setUint32(44, compressed.length);
    final timer = Stopwatch()..start();
    final key = await _derive(password, salt);
    final derivationTime = timer.elapsed;
    timer.reset();
    try {
      final box = await _cipher.encrypt(
        compressed,
        secretKey: key,
        nonce: nonce,
        aad: header,
      );
      return EncodedBackup(
        bytes:
            (BytesBuilder(copy: false)
                  ..add(header)
                  ..add(box.cipherText)
                  ..add(box.mac.bytes))
                .takeBytes(),
        encrypted: true,
        derivationTime: derivationTime,
        encryptionTime: timer.elapsed,
      );
    } finally {
      key.destroy();
    }
  }

  Future<BackupDocument> decode(Uint8List bytes, {String? password}) async {
    _checkFileSize(bytes.length);
    if (bytes.isEmpty) {
      throw const SettingsBackupException(SettingsBackupErrorCode.emptyFile);
    }
    if (!isEncrypted(bytes)) {
      return compute(_decodePlain, bytes, debugLabel: 'backup.decode');
    }
    if (bytes.length < headerLength + tagLength) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidFormat,
      );
    }
    final header = Uint8List.sublistView(bytes, 0, headerLength);
    if (header[8] != 1) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedVersion,
      );
    }
    final data = ByteData.sublistView(header);
    if (header[9] != 1 ||
        header[10] != 1 ||
        header[11] != 1 ||
        data.getUint32(12) != iterations) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidEncryptionParameters,
      );
    }
    if (data.getUint32(44) != bytes.length - headerLength - tagLength) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidFormat,
      );
    }
    if (password == null || password.isEmpty) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.passwordRequired,
      );
    }
    final key = await _derive(password, header.sublist(16, 32));
    try {
      final compressed = await _cipher.decrypt(
        SecretBox(
          Uint8List.sublistView(bytes, headerLength, bytes.length - tagLength),
          nonce: header.sublist(32, 44),
          mac: Mac(Uint8List.sublistView(bytes, bytes.length - tagLength)),
        ),
        secretKey: key,
        aad: header,
      );
      return await compute(
        _decodeGzip,
        Uint8List.fromList(compressed),
        debugLabel: 'backup.decode',
      );
    } on SecretBoxAuthenticationError {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.authenticationFailed,
      );
    } finally {
      key.destroy();
    }
  }

  Cipher get _cipher => _cryptography.aesGcm();

  // deriveKeyFromPassword is important: deriveKey(secretKey: ...) would bypass
  // FlutterPbkdf2's Android native implementation.
  Future<SecretKey> _derive(String password, List<int> salt) => _cryptography
      .pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
      .deriveKeyFromPassword(password: password, nonce: salt);

  static void _checkFileSize(int size) {
    if (size > maxFileBytes) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
  }
}

/// Compact JSON for one preference entry (`"key":{...}`). Shared by the
/// document payload and the per-category size accounting so every size the UI
/// shows matches what the exported file actually contains.
Uint8List encodeBackupEntry(String key, BackupPreference value) =>
    utf8.encode('${jsonEncode(key)}:${jsonEncode(value.toJson())}');

/// Per-category entry counts and sizes (compact JSON, before compression).
/// Used by the content lists, which must not pay for a full [PreparedBackup].
Map<BackupCategory, BackupCategorySummary> measureBackupCategories(
  BackupDocument document,
) {
  document.validate();
  final summaries = <BackupCategory, BackupCategorySummary>{};
  var total = 0;
  for (final entry in document.preferences.entries) {
    final category = BackupSchema.categoryOf(entry.key);
    if (category == null || !document.categories.contains(category)) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedField,
      );
    }
    final size = encodeBackupEntry(entry.key, entry.value).length;
    final previous =
        summaries[category] ??
        const BackupCategorySummary(count: 0, rawBytes: 0);
    summaries[category] = BackupCategorySummary(
      count: previous.count + 1,
      rawBytes: previous.rawBytes + size,
    );
    total += size;
    if (total > BackupCodec.maxContentBytes - 2) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
  }
  return Map.unmodifiable(summaries);
}

PreparedBackup _prepareDocument(BackupDocument document) {
  if (document.categories.isEmpty) {
    throw const SettingsBackupException(SettingsBackupErrorCode.noCategories);
  }
  final timer = Stopwatch()..start();
  document.validate();
  final summaries = {
    for (final category in document.categories)
      category: const BackupCategorySummary(count: 0, rawBytes: 0),
  };
  final bytes = BytesBuilder(copy: false);
  final metadata = jsonEncode(document.metadata);
  bytes.add(utf8.encode('${metadata.substring(0, metadata.length - 1)},'));
  bytes.add(utf8.encode('"preferences":{'));
  var first = true;
  // Encode each preference only once, sharing the result with size accounting.
  for (final entry in document.preferences.entries) {
    final category = BackupSchema.categoryOf(entry.key);
    if (category == null || !document.categories.contains(category)) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedField,
      );
    }
    final encoded = encodeBackupEntry(entry.key, entry.value);
    final previous = summaries[category]!;
    summaries[category] = BackupCategorySummary(
      count: previous.count + 1,
      rawBytes: previous.rawBytes + encoded.length,
    );
    if (!first) bytes.addByte(44);
    first = false;
    bytes.add(encoded);
    if (bytes.length > BackupCodec.maxContentBytes - 2) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
  }
  bytes.add(utf8.encode('}}'));
  final raw = bytes.takeBytes();
  final serializationTime = timer.elapsed;
  timer.reset();
  // GZipCodec defaults to level 6; keep compression in this background isolate.
  final compressed = Uint8List.fromList(GZipCodec().encode(raw));
  BackupCodec._checkFileSize(compressed.length);
  return PreparedBackup(
    document: document,
    compressed: compressed,
    rawBytes: raw.length,
    summaries: Map.unmodifiable(summaries),
    serializationTime: serializationTime,
    compressionTime: timer.elapsed,
  );
}

BackupDocument _decodePlain(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    return _decodeGzip(bytes);
  }
  return _parseUtf8(bytes);
}

BackupDocument _decodeGzip(Uint8List bytes) =>
    _parseUtf8(decompressBackupContent(bytes));

BackupDocument _parseUtf8(List<int> bytes) {
  try {
    return BackupDocument.parse(utf8.decode(bytes));
  } on FormatException {
    throw const SettingsBackupException(SettingsBackupErrorCode.invalidJson);
  }
}

/// Chunked decoding aborts before retaining an oversized decompressed payload.
Uint8List decompressBackupContent(List<int> bytes) {
  final output = _BoundedBytesSink(BackupCodec.maxContentBytes);
  try {
    final input = GZipCodec().decoder.startChunkedConversion(output);
    for (var offset = 0; offset < bytes.length; offset += 16384) {
      input.add(bytes.sublist(offset, min(offset + 16384, bytes.length)));
    }
    input.close();
    return output.bytes.takeBytes();
  } on FormatException {
    throw const SettingsBackupException(SettingsBackupErrorCode.invalidFormat);
  }
}

class _BoundedBytesSink implements Sink<List<int>> {
  final int limit;
  final bytes = BytesBuilder(copy: false);

  _BoundedBytesSink(this.limit);

  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
