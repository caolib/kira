import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_preferences.dart';
import 'package:kira/backup/backup_runtime.dart';
import 'package:kira/models/copy_account_store.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';
import 'backup_test_support.dart';

const _originalAccount = SavedCredential(
  username: 'account-a',
  password: 'password-a',
  token: 'token-a',
  loginSource: 'hotmanga',
  userId: 'id-a',
  nickname: 'name-a',
  avatar: 'avatar-a',
);
const _importedAccount = SavedCredential(
  username: 'account-b',
  password: 'password-b',
  token: 'token-b',
  loginSource: 'copy',
  userId: 'id-b',
  nickname: 'name-b',
  avatar: 'avatar-b',
);

Map<String, Object> _accountValues(SavedCredential account) => {
  'user_token': account.token!,
  'user_id': account.userId!,
  'user_username': account.username,
  'user_nickname': account.nickname!,
  'user_avatar': account.avatar!,
  'login_source': account.source,
  'saved_username': account.username,
  'saved_password': account.password,
  'saved_credentials': jsonEncode([account.toJson()]),
};

class _DelayedFlushRuntime extends SettingsBackupRuntime {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> flush() async {
    started.complete();
    await release.future;
    await super.flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = UserManager();
  late AccountPreferencesPlatform platform;
  late FailingAccountSecureStore secure;
  late SharedBackupPreferences backend;
  late MemoryBackupJournal journal;
  late SettingsBackupService service;
  late String? copyRecord;

  setUp(() async {
    platform = AccountPreferencesPlatform()..install();
    secure = FailingAccountSecureStore();
    SecureCredentialStore.setInstance(secure);
    backend = SharedBackupPreferences(secure: secure);
    journal = MemoryBackupJournal();
    service = SettingsBackupService(
      preferences: backend,
      journal: journal,
      runtime: SettingsBackupRuntime(),
      logger: TestBackupLogger(),
    );
    user.resumeAccountMutationsAfterRestore();
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _accountValues(_originalAccount).entries) {
      final value = entry.value;
      if (value is String) await prefs.setString(entry.key, value);
    }
    await user.init();
    await user.copyAccount.saveSession(
      const CopyAccountSession(token: 'novel-token', userId: 'novel-id'),
    );
    copyRecord = await secure.readCopyAccountRecord();
  });

  tearDown(() async {
    secure.failAllWrites = false;
    secure.failKey = null;
    platform.failKey = null;
    await service.recoverPendingRestore();
    SettingsBackupRuntime().resume();
    platform.dispose();
    SecureCredentialStore.resetInstance();
  });

  Future<void> expectOriginal() async {
    expect(await secure.readToken(), 'token-a');
    expect(await secure.readUsername(), 'account-a');
    expect(await secure.readPassword(), 'password-a');
    expect(
      (await secure.readCredentials()).map((item) => item.toJson()).toList(),
      [_originalAccount.toJson()],
    );
    expect(user.token, 'token-a');
    expect(user.userId, 'id-a');
    expect(user.nickname, 'name-a');
    expect(await secure.readCopyAccountRecord(), copyRecord);
    expect(user.copyToken, 'novel-token');
  }

  test('migration exports secure account using legacy portable keys', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().intersection(SharedBackupPreferences.secureAccountKeys),
      isEmpty,
    );
    final captured = (await service.capture()).select({BackupCategory.account});
    expect(
      captured.preferences.map(
        (key, preference) => MapEntry(key, preference.value),
      ),
      _accountValues(_originalAccount),
    );
    captured.validate();
    final normal = BackupDocument.parse(await service.exportPlainText());
    expect(normal.categories, {BackupCategory.settings});
    expect(
      normal.preferences.keys.where(BackupSchema.accountKeys.contains),
      isEmpty,
    );
    final sensitive = BackupDocument.parse(
      await service.exportPlainText(
        options: const SettingsBackupOptions(includeSensitive: true),
      ),
    );
    expect(sensitive.preferences['user_token']?.value, 'token-a');
    expect(sensitive.preferences['saved_password']?.value, 'password-a');
    expect(sensitive.preferences, isNot(contains('copy_account_v1')));
    expect(jsonEncode(sensitive.toJson()), isNot(contains('novel-token')));
  });

  test(
    'restore replaces secure token and profile together, preserving novel session',
    () async {
      await service.restore(backupDocument(_accountValues(_importedAccount)), {
        BackupCategory.account,
      });
      expect(user.token, 'token-b');
      expect(user.userId, 'id-b');
      expect(user.loginSource, 'copy');
      expect(user.savedPassword, 'password-b');
      expect(await secure.readToken(), 'token-b');
      expect(await secure.readCopyAccountRecord(), copyRecord);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().intersection(SharedBackupPreferences.secureAccountKeys),
        isEmpty,
      );
      await prefs.reload();
      await user.init();
      expect(user.token, 'token-b');
      expect(user.userId, 'id-b');
      expect(user.copyToken, 'novel-token');
    },
  );

  test(
    'account replacement does not merge opaque records from old accounts',
    () async {
      await secure.writeCredentialsRecord(
        jsonEncode([
          _originalAccount.toJson(),
          {'futureAccount': 'old-opaque-record'},
        ]),
      );
      final imported = _importedAccount.toJson()
        ..['futureField'] = {'version': 3};
      final record = jsonEncode([imported]);
      final values = _accountValues(_importedAccount)
        ..['saved_credentials'] = record;

      await service.restore(backupDocument(values), {BackupCategory.account});

      expect(await secure.readCredentialsRecord(), record);
      expect(await secure.readCopyAccountRecord(), copyRecord);
    },
  );

  for (final explicitClear in [false, true]) {
    test(
      'legacy remembered account synthesis respects explicit clear: $explicitClear',
      () async {
        final values = _accountValues(_importedAccount)
          ..remove('saved_credentials');
        if (explicitClear) values['saved_credentials'] = '[]';

        await service.restore(backupDocument(values), {BackupCategory.account});

        expect(await secure.hasCredentialsRecord(), isTrue);
        final credentials = await secure.readCredentials();
        if (explicitClear) {
          expect(credentials, isEmpty);
        } else {
          expect(credentials, hasLength(1));
          expect(credentials.single.username, _importedAccount.username);
          expect(credentials.single.password, _importedAccount.password);
          expect(credentials.single.source, _importedAccount.source);
        }
        expect(await secure.readCopyAccountRecord(), copyRecord);
      },
    );
  }

  test(
    'token-only account backup round-trips its handle without touching novel credentials',
    () async {
      const account = SavedCredential(
        username: '',
        password: '',
        token: 'token-only-backup',
        loginSource: 'copy',
        accountId: 'local:backup-handle',
      );
      final values = <String, Object>{
        'user_token': account.token!,
        'user_account_id': account.accountId!,
        'user_username': '',
        'user_id': '',
        'user_nickname': '',
        'user_avatar': '',
        'login_source': 'copy',
        'saved_credentials': jsonEncode([account.toJson()]),
      };
      await service.restore(backupDocument(values), {BackupCategory.account});
      expect(user.currentCredential?.accountId, account.accountId);
      expect(user.currentCredential?.hasIdentity, isFalse);
      expect(user.savedCredentials, hasLength(1));
      expect(user.savedCredentials.single.accountId, account.accountId);
      expect(await secure.readCopyAccountRecord(), copyRecord);
      final captured = (await service.capture()).select({
        BackupCategory.account,
      });
      expect(captured.preferences['user_account_id']?.value, account.accountId);
      final ordinary = BackupDocument.parse(await service.exportPlainText());
      expect(ordinary.preferences, isNot(contains('user_account_id')));
      await user.init();
      expect(user.currentCredential?.accountId, account.accountId);
      expect(user.token, account.token);
      expect(user.copyToken, 'novel-token');
      expect(await secure.readCopyAccountRecord(), copyRecord);
    },
  );

  test('capture refuses a restore that started during its flush', () async {
    final runtime = _DelayedFlushRuntime();
    final captureService = SettingsBackupService(
      preferences: backend,
      journal: journal,
      runtime: runtime,
    );
    final captured = captureService.capture();
    await runtime.started.future;
    final restoreStarted = Completer<void>();
    final releaseRestore = Completer<void>();
    secure.beforeWrite = (key, value) async {
      if (key == 'user_token' && value == 'token-b') {
        restoreStarted.complete();
        await releaseRestore.future;
      }
    };
    final restoring = service.restore(
      backupDocument(_accountValues(_importedAccount)),
      {BackupCategory.account},
    );
    await restoreStarted.future;
    try {
      runtime.release.complete();
      await expectLater(
        captured,
        throwsA(
          isA<SettingsBackupException>().having(
            (error) => error.code,
            'code',
            SettingsBackupErrorCode.busy,
          ),
        ),
      );
    } finally {
      releaseRestore.complete();
      await restoring;
    }
    expect(user.token, 'token-b');
    expect(user.userId, 'id-b');
  });

  test('ordinary settings restore preserves both account stores', () async {
    final original = (await service.capture()).select({BackupCategory.account});
    await service.restore(backupDocument({'banner_visible': false}), {
      BackupCategory.settings,
    });
    final after = (await service.capture()).select({BackupCategory.account});
    expect(
      after.preferences.map((key, value) => MapEntry(key, value.value)),
      original.preferences.map((key, value) => MapEntry(key, value.value)),
    );
    await expectOriginal();
  });

  test(
    'version one account imports use credential storage, not legacy preference keys',
    () async {
      final values = _accountValues(_importedAccount);
      final legacy = jsonEncode({
        'app': 'kira',
        'kind': 'settings_backup',
        'version': 1,
        'preferences': {
          for (final entry in values.entries)
            entry.key: {'type': 'string', 'value': entry.value},
          'copy_account_v1': {
            'type': 'string',
            'value': 'untrusted-copy-record',
          },
        },
      });
      await service.importPlainText(
        legacy,
        categories: {BackupCategory.account},
      );
      expect(await secure.readToken(), 'token-b');
      expect(user.userId, 'id-b');
      expect(user.savedUsername, 'account-b');
      expect(await secure.readCopyAccountRecord(), copyRecord);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('saved_password'), isFalse);
      expect(prefs.containsKey('copy_account_v1'), isFalse);
    },
  );

  for (final failure in ['secure', 'prefs-false', 'prefs-throw']) {
    test(
      '$failure halfway through restore rolls back secure and profile',
      () async {
        final original = await backend.readAll();
        if (failure == 'secure') {
          secure.failKey = 'saved_password';
          secure.failValue = 'password-b';
        } else {
          platform.failKey = 'user_nickname';
          platform.failValue = 'name-b';
          platform.throwOnFailure = failure == 'prefs-throw';
        }
        await expectLater(
          service.restore(backupDocument(_accountValues(_importedAccount)), {
            BackupCategory.account,
          }),
          throwsA(
            isA<SettingsBackupException>().having(
              (error) => error.code,
              'code',
              SettingsBackupErrorCode.writeFailed,
            ),
          ),
        );
        expect(await backend.readAll(), original);
        expect(journal.pending, isNull);
        await expectOriginal();
        await (await SharedPreferences.getInstance()).reload();
        await user.init();
        await expectOriginal();
      },
    );
  }

  test(
    'startup recovery repairs an interrupted secure/profile replacement',
    () async {
      final original = (await service.capture()).select({
        BackupCategory.account,
      });
      await journal.save(original);
      await secure.writeToken('half-written-token');
      await secure.writePassword('half-written-password');
      await backend.write('user_id', 'half-written-id');
      await backend.remove('user_nickname');
      final restartedService = SettingsBackupService(
        preferences: SharedBackupPreferences(secure: secure),
        journal: journal,
        runtime: SettingsBackupRuntime(),
      );
      expect(await restartedService.recoverPendingRestore(), isTrue);
      expect(journal.pending, isNull);
      await (await SharedPreferences.getInstance()).reload();
      await user.init();
      await expectOriginal();
      expect(await restartedService.recoverPendingRestore(), isFalse);
    },
  );

  test(
    'failed rollback retains journal until secure storage recovers',
    () async {
      secure.failAllWrites = true;
      await expectLater(
        service.restore(backupDocument(_accountValues(_importedAccount)), {
          BackupCategory.account,
        }),
        throwsA(
          isA<SettingsBackupException>().having(
            (error) => error.code,
            'code',
            SettingsBackupErrorCode.recoveryRequired,
          ),
        ),
      );
      expect(journal.pending, isNotNull);
      await expectLater(
        service.capture(),
        throwsA(isA<SettingsBackupException>()),
      );
      secure.failAllWrites = false;
      expect(await service.recoverPendingRestore(), isTrue);
      SettingsBackupRuntime().resume();
      await user.init();
      await expectOriginal();
    },
  );

  test(
    'logout tombstone overrides stale prefs and survives backup round trip',
    () async {
      await user.logout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_token', 'stale-plaintext-token');
      final signedOut = (await service.capture()).select({
        BackupCategory.account,
      });
      expect(signedOut.preferences['user_token']?.value, '');
      expect(
        jsonEncode(signedOut.toJson()),
        isNot(contains('stale-plaintext-token')),
      );
      await user.switchToCredential(_importedAccount);
      await service.restore(signedOut, {BackupCategory.account});
      expect(await secure.readToken(), '');
      expect(user.isLoggedIn, isFalse);
      expect(user.userId, isNull);
      expect(prefs.containsKey('user_token'), isFalse);
      await user.init();
      expect(user.isLoggedIn, isFalse);
      expect(await secure.readCopyAccountRecord(), copyRecord);
    },
  );

  test(
    'empty account replacement clears masked plaintext credentials only',
    () async {
      await secure.writeUsername(null);
      await secure.writePassword(null);
      await secure.writeCredentials([]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_username', 'stale-user');
      await prefs.setString('saved_password', 'stale-password');
      await prefs.setString(
        'saved_credentials',
        jsonEncode([_importedAccount.toJson()]),
      );
      final snapshot = await backend.readAll();
      expect(snapshot.containsKey('saved_password'), isFalse);
      await service.restore(
        backupDocument({}, categories: {BackupCategory.account}),
        {BackupCategory.account},
      );
      expect(
        prefs.getKeys().intersection(SharedBackupPreferences.secureAccountKeys),
        isEmpty,
      );
      expect(await secure.readToken(), '');
      expect(await secure.readCredentials(), isEmpty);
      expect(user.isLoggedIn, isFalse);
      expect(await secure.readCopyAccountRecord(), copyRecord);
    },
  );
}
