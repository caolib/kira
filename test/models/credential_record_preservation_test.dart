import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/copy_account_store.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';
import '../test_helpers.dart';

const _recordKey = 'secure_mirror_saved_credentials';
const _opaque = {
  'future_only_account': {'version': 2},
};
const _account = SavedCredential(
  username: 'fixture-user',
  password: 'old-password',
  token: 'old-token',
  loginSource: 'copy',
  userId: 'reader-id',
  accountId: 'local:a',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = UserManager();
  late AccountPreferencesPlatform platform;

  void seed(Map<String, Object> values) {
    platform.values.addAll({
      for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
    });
  }

  Future<void> reload({bool persistMigrations = true}) async {
    SharedPreferences.resetStatic();
    SecureCredentialStore.resetInstance();
    await user.init(persistMigrations: persistMigrations);
  }

  void seedDuplicates() {
    final duplicate = _account.copyWith(
      accountId: 'local:b',
      token: 'second-token',
    );
    seed({
      'login_source': 'copy',
      'user_username': _account.username,
      'user_id': _account.userId!,
      'user_account_id': _account.accountId!,
      'secure_mirror_user_token': _account.token!,
      'secure_mirror_saved_username': _account.username,
      'secure_mirror_saved_password': _account.password,
      'secure_mirror_credentials_migrated_to_secure': 'true',
      _recordKey: jsonEncode([
        {
          ..._account.toJson(),
          'future_a': {'preserve': true},
        },
        _opaque,
        {...duplicate.toJson(), 'future_b': 'keep'},
      ]),
      'secure_mirror_copy_account_v1': jsonEncode({
        'migrationHandled': true,
        'activeId': duplicate.accountId,
        'accounts': [
          for (final account in [_account, duplicate])
            CopyAccountSession(
              token: account.token!,
              accountId: account.accountId,
              userId: account.userId!,
              username: account.username,
            ).toJson(),
        ],
      }),
    });
  }

  setUp(() {
    setupSecureCredentialStoreForTest();
    platform = AccountPreferencesPlatform()..install();
    SecureCredentialStore.resetInstance();
    user.resumeAccountMutationsAfterRestore();
  });

  tearDown(() {
    user.resumeAccountMutationsAfterRestore();
    platform.dispose();
    teardownSecureCredentialStoreForTest();
  });

  test(
    'deduplication retains unknown fields and opaque records across boots',
    () async {
      seedDuplicates();
      await reload();
      final raw = await SecureCredentialStore().readCredentialsRecord();
      final records = jsonDecode(raw!);
      expect(records, hasLength(2));
      expect(records, contains(equals(_opaque)));
      final saved = (await SecureCredentialStore().readCredentials()).single;
      expect(saved.toJson()['future_a'], {'preserve': true});
      expect(saved.toJson()['future_b'], 'keep');
      expect(saved.accountId, user.copyAccount.accounts.single.id);
      expect(saved.token, user.copyToken);
      expect(saved.password, _account.password);
      for (var boot = 0; boot < 3; boot++) {
        await reload();
        expect(await SecureCredentialStore().readCredentialsRecord(), raw);
        expect(user.savedCredentials.single.toJson()['future_b'], 'keep');
        expect(user.token, saved.token);
      }
    },
  );

  test(
    'editing a password preserves future data; explicit clear removes it',
    () async {
      final raw = jsonEncode([
        {
          'username': 'fixture-user',
          'password': 'old-password',
          'future_field': {'preserve': true},
        },
        _opaque,
      ]);
      seed({_recordKey: raw, 'login_source': 'hotmanga'});
      await reload();
      expect(await SecureCredentialStore().readCredentialsRecord(), raw);
      await user.saveCredentials('fixture-user', 'new-password');
      final edited = await SecureCredentialStore().readCredentialsRecord();
      expect(jsonDecode(edited!), contains(equals(_opaque)));
      expect(user.savedCredentials.single.toJson()['future_field'], {
        'preserve': true,
      });
      await reload();
      expect(await SecureCredentialStore().readCredentialsRecord(), edited);
      expect(user.savedCredentials.single.password, 'new-password');
      await user.clearCredentials();
      await reload();
      expect(await SecureCredentialStore().readCredentialsRecord(), '[]');
      expect(user.savedCredentials, isEmpty);
    },
  );

  for (final throws in [false, true]) {
    test(
      'failed COPY deduplication restores the exact record, throws=$throws',
      () async {
        seedDuplicates();
        await reload(persistMigrations: false);
        final original = await SecureCredentialStore().readCredentialsRecord();
        final copyOriginal = await SecureCredentialStore()
            .readCopyAccountRecord();
        var injected = false;
        platform.throwOnFailure = throws;
        platform.beforeWrite = (key, value) async {
          if (!injected && key == 'flutter.secure_mirror_copy_account_v1') {
            injected = true;
            platform.failKey = 'secure_mirror_copy_account_v1';
            platform.failValue = value;
          }
        };
        await user.init();
        expect(injected, isTrue);
        expect(platform.failKey, isNull);
        expect(await SecureCredentialStore().readCredentialsRecord(), original);
        expect(
          await SecureCredentialStore().readCopyAccountRecord(),
          copyOriginal,
        );
        await reload(persistMigrations: false);
        expect(await SecureCredentialStore().readCredentialsRecord(), original);
        await reload();
        expect(await SecureCredentialStore().readCredentials(), hasLength(1));
        expect(
          jsonDecode((await SecureCredentialStore().readCredentialsRecord())!),
          contains(equals(_opaque)),
        );
      },
    );

    test(
      'failed login restores the exact legacy-shaped record, throws=$throws',
      () async {
        final raw = jsonEncode([
          {
            'username': 'fixture-user',
            'password': 'old-password',
            'token': 'old-token',
            'future_field': {'preserve': true},
          },
          _opaque,
        ]);
        seed({
          'login_source': 'hotmanga',
          'user_username': 'fixture-user',
          'user_id': 'reader-id',
          'secure_mirror_user_token': 'old-token',
          'secure_mirror_saved_username': 'fixture-user',
          'secure_mirror_saved_password': 'old-password',
          _recordKey: raw,
        });
        await reload();
        final before = Map.of(platform.values);
        platform.throwOnFailure = throws;
        platform.failKey = 'user_nickname';
        platform.failValue = 'updated';
        await expectLater(
          user.authenticateAndLogin(
            source: 'hotmanga',
            authenticate: () async => {
              'username': 'fixture-user',
              'user_id': 'reader-id',
              'token': 'new-token',
              'nickname': 'updated',
            },
          ),
          throwsA(isA<CopyAccountStorageException>()),
        );
        expect(platform.failKey, isNull);
        expect(platform.values, before);
        await reload();
        expect(await SecureCredentialStore().readCredentialsRecord(), raw);
        expect(user.token, 'old-token');
      },
    );
  }

  test(
    'read-only novel status inheritance waits for a normal startup',
    () async {
      seed({
        'reader_status_overlay': true,
        'reader_status_overlay_position': 4,
        'reader_status_overlay_opacity': 0.4,
      });
      final before = Map.of(platform.values);
      await reload(persistMigrations: false);
      expect(platform.values, before);
      expect(user.novelStatus.statusOverlay, isTrue);
      expect(user.novelStatus.statusOverlayPosition, 4);
      expect(user.novelStatus.statusOverlayOpacity, 0.4);
      expect(user.novelStatus.statusOverlayChapter, isTrue);
      await reload();
      expect(platform.values['flutter.novel_status_overlay_seeded'], isTrue);
      await user.reader.setStatusOverlayPosition(1);
      await reload();
      expect(user.reader.statusOverlayPosition, 1);
      expect(user.novelStatus.statusOverlayPosition, 4);
      expect(user.novelStatus.statusOverlayOpacity, 0.4);
    },
  );
}
