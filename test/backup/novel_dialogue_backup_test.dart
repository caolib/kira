import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/models/novel_reader_settings.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';
import '../test_helpers.dart';
import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountPreferencesPlatform platform;
  setUp(() {
    setupSecureCredentialStoreForTest();
    platform = AccountPreferencesPlatform()..install();
  });
  tearDown(() {
    platform.dispose();
    teardownSecureCredentialStoreForTest();
  });

  test(
    'cold loads preserve an old opt-out and default a missing field on',
    () async {
      final prefs = await SharedPreferences.getInstance();
      for (final (json, expected) in [
        ('{}', true),
        ('{"dialogueEnabled":false}', false),
      ]) {
        await prefs.setString(NovelReaderSettings.storageKey, json);
        SharedPreferences.resetStatic();
        final settings = await NovelReaderSettings.load();
        expect(settings.dialogueEnabled, expected);
        expect(settings.dialogueQuotes, NovelDialogueQuotes.defaults);
        expect(
          (await SharedPreferences.getInstance()).getString(
            NovelReaderSettings.storageKey,
          ),
          json,
        );
      }
    },
  );

  test(
    'settings backup preserves partial and empty selections and a disabled switch',
    () async {
      final service = SettingsBackupService(
        journal: MemoryBackupJournal(),
        runtime: TestBackupRuntime(),
        logger: TestBackupLogger(),
      );
      final codec = BackupCodec();
      for (final quotes in [
        NovelDialogueQuotes.none.withQuote(
          NovelDialogueQuote.straightDouble,
          true,
        ),
        NovelDialogueQuotes.none,
      ]) {
        final chosen = NovelReaderSettings(
          dialogueEnabled: false,
          dialogueQuotes: quotes,
        );
        await chosen.save();
        final snapshot = (await service.capture()).select({
          BackupCategory.settings,
        });
        expect(
          snapshot.preferences[NovelReaderSettings.storageKey]!.type,
          'string',
        );
        final data = await codec.encode(await codec.prepare(snapshot));
        final backup = await codec.decode(data.bytes);
        await const NovelReaderSettings().save();
        await service.restore(backup, {BackupCategory.settings});
        SharedPreferences.resetStatic();
        expect(await NovelReaderSettings.load(), chosen);
      }
    },
  );

  test(
    'failed quote preference write surfaces the error and keeps the previous disk value',
    () async {
      const original = NovelReaderSettings(dialogueEnabled: false);
      await original.save();
      final changed = original.copyWith(
        dialogueQuotes: NovelDialogueQuotes.none,
      );
      platform
        ..failKey = NovelReaderSettings.storageKey
        ..failValue = jsonEncode(changed.toJson());
      await expectLater(changed.save(), throwsStateError);
      SharedPreferences.resetStatic();
      expect(await NovelReaderSettings.load(), original);
    },
  );
}
