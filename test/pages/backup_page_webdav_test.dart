import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/backup/backup_controller.dart';
import 'package:kira/backup/backup_settings.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/pages/backup/webdav_panel.dart';
import 'package:kira/pages/backup_page.dart';
import 'package:kira/providers/backup_providers.dart';
import 'package:kira/utils/settings_backup.dart';

import '../backup/backup_test_support.dart';
import '../test_helpers.dart';

class _MemoryRemote extends BackupController {
  final entries = [
    for (final name in ['a', 'b', 'c'])
      WebDavBackupEntry(name: '$name.kirabak'),
  ];
  final deleted = <String>[];
  int lists = 0;

  _MemoryRemote(MemoryBackupPreferences prefs)
    : super(
        service: SettingsBackupService(
          preferences: prefs,
          journal: MemoryBackupJournal(),
          runtime: TestBackupRuntime(),
        ),
        codec: BackupCodec(),
      );

  @override
  Future<List<WebDavBackupEntry>> list(
    WebDavConfig config,
    WebDavCredentials credentials,
  ) async {
    lists++;
    return entries.toList();
  }

  @override
  Future<void> deleteMany(
    WebDavConfig config,
    WebDavCredentials credentials,
    List<WebDavBackupEntry> entries, {
    required void Function(WebDavBackupEntry) onDeleted,
  }) async {
    for (final entry in entries) {
      deleted.add(entry.name);
      this.entries.remove(entry);
      onDeleted(entry);
    }
  }
}

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('保存上限不删文件，批量删除确认后才处理选中的远端备份', (tester) async {
    final prefs = MemoryBackupPreferences();
    final settings = BackupSettings(preferences: prefs);
    await settings.saveConnection(
      WebDavConfig(serverUrl: 'https://example.invalid'),
      const WebDavCredentials(username: '', password: ''),
    );
    final remote = _MemoryRemote(prefs);
    addTearDown(remote.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupSettingsProvider.overrideWithValue(settings),
          backupControllerProvider.overrideWithValue(remote),
        ],
        child: wrapWithApp(const BackupPage(), wrapInScaffold: false),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(WebDavPanel),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    WebDavPanel panel() => tester.widget<WebDavPanel>(find.byType(WebDavPanel));
    expect(panel().retentionLimit, 0);
    panel().onRetentionChanged(1);
    await tester.pumpAndSettle();
    expect((await settings.load()).retentionLimit, 1);
    expect(remote.deleted, isEmpty);
    expect(remote.lists, 1);
    expect(panel().entries, hasLength(3));

    final selected = [panel().entries.first, panel().entries.last];
    for (final confirm in [false, true]) {
      final result = panel().onDeleteSelected(selected);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 份远端备份'), findsOneWidget);
      expect(remote.deleted, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(confirm ? '删除' : '取消'),
        ),
      );
      await tester.pumpAndSettle();
      await result;
    }
    expect(remote.deleted, ['a.kirabak', 'c.kirabak']);
    expect(panel().entries.single.name, 'b.kirabak');
  });
}
