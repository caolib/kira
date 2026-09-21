import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/pages/backup/backup_content_controls.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _controls({
  Set<BackupCategory> selected = const {},
  Map<BackupCategory, int>? sizes,
  bool enabled = true,
  void Function(BackupCategory category, bool selected)? onSelect,
  ValueChanged<bool>? onSelectAll,
}) => BackupContentControls(
  selected: selected,
  sizes: sizes,
  enabled: enabled,
  encrypted: true,
  passwordSet: false,
  passwordRemembered: false,
  onSelect: onSelect ?? (_, _) {},
  onSelectAll: onSelectAll ?? (_) {},
  onEncryptionChanged: (_) {},
  onPassword: () {},
);

void main() {
  testWidgets('select all row covers every category', (tester) async {
    bool? selectAll;
    await tester.pumpWidget(
      _app(_controls(onSelectAll: (value) => selectAll = value)),
    );

    final rows = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(rows.length, BackupCategory.values.length + 1);
    expect((rows.first.title as Text).data, '全选');
    // Partially selected: the row shows unchecked and selects everything.
    expect(rows.first.value, isFalse);
    await tester.tap(find.text('全选'));
    expect(selectAll, isTrue);

    selectAll = null;
    await tester.pumpWidget(
      _app(
        _controls(
          selected: BackupCategory.values.toSet(),
          onSelectAll: (value) => selectAll = value,
        ),
      ),
    );
    final all = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .first;
    expect(all.value, isTrue);
    await tester.tap(find.text('全选'));
    expect(selectAll, isFalse);
  });

  testWidgets('every category shows its measured size once available', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_controls()));
    expect(find.text('0 B'), findsNothing);

    await tester.pumpWidget(
      _app(
        _controls(
          sizes: const {
            BackupCategory.settings: 2048,
            BackupCategory.account: 10,
          },
        ),
      ),
    );
    expect(find.text('2.00 KiB'), findsOneWidget);
    expect(find.text('10 B'), findsOneWidget);
    expect(find.text('0 B'), findsNWidgets(BackupCategory.values.length - 2));
  });

  testWidgets('encryption switch is labelled as file encryption', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_controls()));
    expect(find.text('备份文件加密'), findsOneWidget);
    expect(find.text('密码保护'), findsNothing);
  });
}
