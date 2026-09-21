import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/backup/backup_journal.dart';
import 'package:kira/models/secure_credential_store.dart';

import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late InMemorySecureCredentialStore secrets;
  late EncryptedBackupJournal journal;
  final original = backupDocument(
    {
      'user_token': 'never-plaintext-on-disk',
      'saved_password': 'local-account-password',
    },
    categories: {BackupCategory.account},
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kira_backup_journal_');
    secrets = InMemorySecureCredentialStore();
    journal = EncryptedBackupJournal(
      directory: () async => directory,
      secrets: secrets,
    );
  });

  tearDown(() async => directory.delete(recursive: true));

  test('encrypted journal roundtrip and atomic publish', () async {
    expect(await journal.read(), isNull);
    await journal.save(original);
    final pending = File('${directory.path}/backup-restore.pending');
    expect(await pending.exists(), isTrue);
    expect(await File('${pending.path}.tmp').exists(), isFalse);
    final bytes = await pending.readAsBytes();
    expect(
      String.fromCharCodes(bytes),
      isNot(contains('never-plaintext-on-disk')),
    );
    expect(await secrets.readBackupRollbackKey(), isNotNull);
    expect((await journal.read())?.toJson(), original.toJson());
    await journal.clear();
    expect(await journal.read(), isNull);
  });

  test('backup password changes do not affect rollback key', () async {
    await journal.save(original);
    await secrets.writeBackupPassword('totally-different-password');
    expect((await journal.read())?.toJson(), original.toJson());
  });

  test(
    'tampered and unavailable-key journals fail closed and remain present',
    () async {
      await journal.save(original);
      final file = File('${directory.path}/backup-restore.pending');
      final bytes = await file.readAsBytes();
      bytes[8] ^= 1;
      await file.writeAsBytes(bytes, flush: true);
      await expectLater(journal.read(), throwsA(isA<Exception>()));
      expect(await file.exists(), isTrue);
      await secrets.writeBackupRollbackKey(null);
      await expectLater(journal.read(), throwsA(isA<Exception>()));
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'never overwrites a pending journal; unpublished temporary file is ignored',
    () async {
      await File(
        '${directory.path}/backup-restore.pending.tmp',
      ).writeAsString('partial');
      expect(await journal.read(), isNull);
      await journal.save(original);
      await expectLater(journal.save(original), throwsA(isA<Exception>()));
      expect((await journal.read())?.toJson(), original.toJson());
    },
  );
}
