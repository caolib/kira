import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/backup/backup_error.dart';

import 'backup_test_support.dart';

Matcher backupError(SettingsBackupErrorCode code) =>
    isA<SettingsBackupException>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final codec = BackupCodec();
  final document = backupDocument({
    'theme_color': '紫色🌸',
    'theme_mode': 2,
    'banner_visible': true,
    'reader_image_gap': 1.25,
    'comment_blockwords': <String>['a', '简繁'],
    'user_token': 'private-value-do-not-display',
  });
  late PreparedBackup prepared;
  late EncodedBackup encrypted;
  const password = '  备份密码 🔑 no trimming  ';

  setUpAll(() async {
    // flutter_test defaults TargetPlatform to Android; exercise the real
    // Windows/Linux background implementation here, not an absent plugin.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    prepared = await codec.prepare(document);
    encrypted = await codec.encode(prepared, password: password);
  });
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  test('compact v2 gzip roundtrip preserves every preference type', () async {
    final encoded = await codec.encode(prepared);
    expect(encoded.extension, '.json.gz');
    expect(encoded.bytes.take(2), [0x1f, 0x8b]);
    final decoded = await codec.decode(encoded.bytes);
    expect(decoded.toJson(), document.toJson());
    expect(decoded.preferences['reader_image_gap']?.value, isA<double>());
    expect(
      decoded.preferences['comment_blockwords']?.value,
      isA<List<String>>(),
    );
    expect(decoded.categories, {
      BackupCategory.settings,
      BackupCategory.account,
    });
  });

  test(
    'preview counts actual UTF-8 entries without exposing setting values',
    () {
      final counts = prepared.summaries.values.fold(
        0,
        (sum, item) => sum + item.count,
      );
      expect(counts, document.preferences.length);
      var exact = 0;
      for (final entry in document.preferences.entries) {
        exact += utf8
            .encode(
              '${jsonEncode(entry.key)}:${jsonEncode(entry.value.toJson())}',
            )
            .length;
      }
      expect(prepared.entryBytes, exact);
      expect(
        prepared.rawBytes,
        utf8.encode(jsonEncode(document.toJson())).length,
      );
      expect(prepared.compressed.length, lessThan(prepared.rawBytes));
    },
  );

  test('measured category sizes match the prepared backup exactly', () {
    final measured = measureBackupCategories(document);
    expect(measured.keys.toSet(), prepared.summaries.keys.toSet());
    for (final entry in prepared.summaries.entries) {
      expect(measured[entry.key]!.count, entry.value.count);
      expect(measured[entry.key]!.rawBytes, entry.value.rawBytes);
    }
    expect(
      measured.values.fold(0, (sum, item) => sum + item.rawBytes),
      prepared.entryBytes,
    );
    // Empty categories stay absent, so lists show them as zero bytes.
    expect(measured.containsKey(BackupCategory.bookmarks), isFalse);
  });

  test(
    'AES-256-GCM binary roundtrip, fixed KDF and untrimmed Unicode password',
    () async {
      expect(encrypted.extension, '.kirabak');
      expect(BackupCodec.isEncrypted(encrypted.bytes), isTrue);
      expect(encrypted.bytes.length, prepared.compressed.length + 64);
      expect(ByteData.sublistView(encrypted.bytes).getUint32(12), 600000);
      final decoded = await codec.decode(encrypted.bytes, password: password);
      expect(decoded.toJson(), document.toJson());
      await expectLater(
        codec.decode(encrypted.bytes, password: password.trim()),
        throwsA(backupError(SettingsBackupErrorCode.authenticationFailed)),
      );
    },
  );

  test('wrong password and missing password are rejected', () async {
    await expectLater(
      codec.decode(encrypted.bytes),
      throwsA(backupError(SettingsBackupErrorCode.passwordRequired)),
    );
    await expectLater(
      codec.decode(encrypted.bytes, password: 'wrong'),
      throwsA(backupError(SettingsBackupErrorCode.authenticationFailed)),
    );
  });

  test(
    'ciphertext, authenticated salt and nonce tampering are rejected',
    () async {
      for (final offset in [
        16,
        32,
        BackupCodec.headerLength,
        encrypted.bytes.length - 1,
      ]) {
        final tampered = Uint8List.fromList(encrypted.bytes);
        tampered[offset] ^= 1;
        await expectLater(
          codec.decode(tampered, password: password),
          throwsA(backupError(SettingsBackupErrorCode.authenticationFailed)),
        );
      }
    },
  );

  test(
    'unknown header version and abnormal KDF are refused before derivation',
    () async {
      final unknown = Uint8List.fromList(encrypted.bytes)..[8] = 99;
      await expectLater(
        codec.decode(unknown),
        throwsA(backupError(SettingsBackupErrorCode.unsupportedVersion)),
      );
      for (final offset in [9, 10, 11, 12, 15]) {
        final invalid = Uint8List.fromList(encrypted.bytes);
        invalid[offset] ^= 1;
        await expectLater(
          codec.decode(invalid),
          throwsA(
            backupError(SettingsBackupErrorCode.invalidEncryptionParameters),
          ),
        );
      }
    },
  );

  test('truncation and trailing ciphertext are rejected', () async {
    for (final size in [8, 20, 48, encrypted.bytes.length - 1]) {
      await expectLater(
        codec.decode(
          Uint8List.sublistView(encrypted.bytes, 0, size),
          password: password,
        ),
        throwsA(isA<SettingsBackupException>()),
      );
    }
    await expectLater(
      codec.decode(
        Uint8List.fromList([...encrypted.bytes, 0]),
        password: password,
      ),
      throwsA(backupError(SettingsBackupErrorCode.invalidFormat)),
    );
    await expectLater(
      codec.decode(
        Uint8List.sublistView(
          prepared.compressed,
          0,
          prepared.compressed.length ~/ 2,
        ),
      ),
      throwsA(isA<SettingsBackupException>()),
    );
  });

  test('each encrypted file gets a fresh salt and nonce', () async {
    final second = await codec.encode(prepared, password: password);
    expect(
      second.bytes.sublist(16, 32),
      isNot(encrypted.bytes.sublist(16, 32)),
    );
    expect(
      second.bytes.sublist(32, 44),
      isNot(encrypted.bytes.sublist(32, 44)),
    );
  });

  test(
    'content sniffing accepts plain and fenced legacy JSON, excludes local keys',
    () async {
      final legacy = jsonEncode({
        'app': 'kira',
        'kind': 'settings_backup',
        'version': 1,
        'preferences': {
          'banner_visible': {'type': 'bool', 'value': false},
          'user_token': {'type': 'string', 'value': 'old-token'},
          'backup_webdav_config_v1': {'type': 'string', 'value': '{}'},
          'zhipu_chapter_summary_a': {'type': 'string', 'value': 'summary'},
          'download_save_directory': {
            'type': 'string',
            'value': '/some/device',
          },
        },
      });
      for (final text in [legacy, '```json\n$legacy\n```', '\uFEFF$legacy']) {
        final decoded = await codec.decode(
          Uint8List.fromList(utf8.encode(text)),
        );
        expect(decoded.sourceVersion, 1);
        expect(decoded.skippedCount, 3);
        expect(decoded.preferences.keys, ['banner_visible', 'user_token']);
        expect(decoded.categories, {
          BackupCategory.settings,
          BackupCategory.account,
        });
      }
    },
  );

  test(
    'rejects undeclared or unknown categories, unknown keys and bad types',
    () async {
      final cases = <Map<String, Object?>>[
        {...document.toJson(), 'version': 77},
        {
          ...document.toJson(),
          'categories': ['settings'],
        },
        {
          ...document.toJson(),
          'categories': ['bogus'],
        },
        {
          ...document.toJson(),
          'categories': ['settings', 'settings'],
        },
        {
          ...document.toJson(),
          'preferences': {
            'backup_webdav_config_v1': {'type': 'string', 'value': '{}'},
          },
        },
        {
          ...document.toJson(),
          'preferences': {
            'banner_visible': {'type': 'string', 'value': 'true'},
          },
        },
        {
          ...document.toJson(),
          'preferences': {
            'theme_mode': {'type': 'int', 'value': 1000},
          },
        },
      ];
      for (final invalid in cases) {
        await expectLater(
          codec.decode(Uint8List.fromList(utf8.encode(jsonEncode(invalid)))),
          throwsA(isA<SettingsBackupException>()),
        );
      }
    },
  );

  test('explicitly included empty category survives the roundtrip', () async {
    final empty = backupDocument({}, categories: {BackupCategory.bookmarks});
    final encoded = await codec.encode(await codec.prepare(empty));
    final decoded = await codec.decode(encoded.bytes);
    expect(decoded.categories, {BackupCategory.bookmarks});
    expect(decoded.preferences, isEmpty);
  });

  test('refuses inputs over 16 MiB before parsing', () async {
    await expectLater(
      codec.decode(Uint8List(BackupCodec.maxFileBytes + 1)),
      throwsA(backupError(SettingsBackupErrorCode.tooLarge)),
    );
  });

  test('bounded decompression rejects a gzip bomb over 64 MiB', () async {
    final raw = Uint8List(BackupCodec.maxContentBytes + 1);
    final compressed = Uint8List.fromList(GZipCodec().encode(raw));
    expect(compressed.length, lessThan(BackupCodec.maxFileBytes));
    await expectLater(
      codec.decode(compressed),
      throwsA(backupError(SettingsBackupErrorCode.tooLarge)),
    );
  });
}
