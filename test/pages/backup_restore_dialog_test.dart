import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/pages/backup/backup_restore_dialog.dart';

import '../backup/backup_test_support.dart';

void main() {
  testWidgets('every category stored in the file starts selected', (
    tester,
  ) async {
    final document = backupDocument({
      'banner_visible': true,
      'theme_color': '紫色',
      'user_token': 'token',
      'reading_history_a': '{"chapterUuid":"a"}',
    });
    Set<BackupCategory>? restored;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                restored = await showDialog<Set<BackupCategory>>(
                  context: context,
                  builder: (_) => BackupRestoreDialog(document: document),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    // The「全选」row sits above one row per stored category.
    expect(rows.length, document.categories.length + 1);
    expect(rows.every((row) => row.value == true), isTrue);
    expect(find.text('全选'), findsOneWidget);
    // Counts and sizes are measured for every row, not just the selection.
    expect(
      find.textContaining(' 项 · '),
      findsNWidgets(document.categories.length),
    );

    //「全选」clears every row at once, which leaves nothing to restore.
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((row) => row.value == false),
      isTrue,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(restored, document.categories);
  });
}
