import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_schedule.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/pages/backup/webdav_panel.dart';

import '../test_helpers.dart';

Widget _app(Widget child) => wrapWithApp(SingleChildScrollView(child: child));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

final _config = WebDavConfig(serverUrl: 'https://dav.example/dav/');

const _first = WebDavBackupEntry(name: 'first.kirabak');
const _second = WebDavBackupEntry(name: 'second.json');

WebDavPanel _panel({
  Key? key,
  bool enabled = true,
  bool interactive = true,
  WebDavConfig? config,
  List<WebDavBackupEntry> entries = const [],
  BackupSchedule schedule = const BackupSchedule(),
  String? error,
  bool listed = false,
  ValueChanged<bool>? onToggle,
  VoidCallback? onConfigure,
  VoidCallback? onRefresh,
  ValueChanged<WebDavBackupEntry>? onRestore,
  ValueChanged<WebDavBackupEntry>? onDelete,
  Future<void> Function(List<WebDavBackupEntry>)? onDeleteSelected,
  int retentionLimit = 0,
  ValueChanged<int>? onRetentionChanged,
}) => WebDavPanel(
  key: key,
  config: config,
  entries: entries,
  enabled: enabled,
  interactive: interactive,
  canUpload: true,
  listed: listed,
  schedule: schedule,
  scheduleReady: true,
  error: error,
  onToggle: onToggle ?? (_) {},
  onConfigure: onConfigure ?? () {},
  onTest: () {},
  onUpload: () {},
  onRefresh: onRefresh ?? () {},
  onRestore: onRestore ?? (_) {},
  onDelete: onDelete ?? (_) {},
  onDeleteSelected: onDeleteSelected ?? (_) async {},
  retentionLimit: retentionLimit,
  onRetentionChanged: onRetentionChanged ?? (_) {},
  onScheduleChanged: (_) {},
);

/// 定时备份也是 SwitchListTile，总开关按标题定位。
final _masterSwitch = find.ancestor(
  of: find.text('WebDAV'),
  matching: find.byType(SwitchListTile),
);

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('总开关关闭时只留下开关本身', (tester) async {
    bool? toggled;
    await tester.pumpWidget(
      _app(
        _panel(
          enabled: false,
          config: _config,
          entries: [const WebDavBackupEntry(name: 'kira.kirabak')],
          onToggle: (value) => toggled = value,
        ),
      ),
    );

    expect(find.text('连接设置'), findsNothing);
    expect(find.text('定时备份'), findsNothing);
    expect(find.text('测试'), findsNothing);
    expect(find.text('kira.kirabak'), findsNothing);
    // 已有配置时说明设置还在，避免看起来像被清空了。
    expect(find.text('已关闭：不会上传备份，已保存的连接信息仍会保留。'), findsOneWidget);
    expect(find.text('开启后可配置服务器、定时备份与远端备份列表。'), findsNothing);

    expect(tester.widget<SwitchListTile>(_masterSwitch).value, isFalse);
    await tester.tap(_masterSwitch);
    expect(toggled, isTrue);
  });

  testWidgets('总开关开启后显示全部配置与远端列表', (tester) async {
    await tester.pumpWidget(
      _app(
        _panel(
          config: _config,
          schedule: const BackupSchedule(enabled: true),
          entries: [const WebDavBackupEntry(name: 'kira.kirabak')],
        ),
      ),
    );

    expect(tester.widget<SwitchListTile>(_masterSwitch).value, isTrue);
    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('https://dav.example/dav/'), findsOneWidget);
    expect(find.text('定时备份'), findsOneWidget);
    expect(find.text('测试'), findsOneWidget);
    expect(find.text('上传'), findsOneWidget);
    expect(find.text('kira.kirabak'), findsOneWidget);
  });

  testWidgets('未配置服务器时连接设置行给出提示', (tester) async {
    await tester.pumpWidget(_app(_panel()));

    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('未设置服务器'), findsOneWidget);
  });

  testWidgets('备份进行中锁住总开关', (tester) async {
    await tester.pumpWidget(_app(_panel(interactive: false, config: _config)));

    expect(tester.widget<SwitchListTile>(_masterSwitch).onChanged, isNull);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '定时备份'))
          .onChanged,
      isNull,
    );
  });

  testWidgets('未配置服务器时联网操作保持禁用', (tester) async {
    await tester.pumpWidget(_app(_panel()));

    final test = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '测试'),
    );
    final upload = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '上传'),
    );
    expect(test.onPressed, isNull);
    expect(upload.onPressed, isNull);
  });

  testWidgets('多选可勾选、全选、取消全选或退出，未勾选时不能删除', (tester) async {
    var deletes = 0;
    await tester.pumpWidget(
      _app(
        _panel(
          config: _config,
          entries: const [_first, _second],
          onDeleteSelected: (_) async {
            deletes++;
          },
        ),
      ),
    );
    await _tap(tester, find.text('多选'));
    final delete = find.widgetWithText(TextButton, '删除');
    expect(tester.widget<TextButton>(delete).onPressed, isNull);
    expect(find.text('已选 0 份'), findsOneWidget);
    await _tap(tester, find.text(_first.name));
    expect(find.text('已选 1 份'), findsOneWidget);
    await _tap(tester, find.text('全选'));
    expect(find.text('已选 2 份'), findsOneWidget);
    await _tap(tester, find.text('取消全选'));
    expect(tester.widget<TextButton>(delete).onPressed, isNull);
    await _tap(tester, find.text(_second.name));
    await _tap(tester, find.text('取消'));
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(deletes, 0);
    await _tap(tester, find.text('多选'));
    expect(find.text('已选 0 份'), findsOneWidget);
  });

  testWidgets('取消批删时保留原选择；部分删除后只保留失败项供重试', (tester) async {
    final entries = [_first, _second];
    final calls = <List<WebDavBackupEntry>>[];
    final confirmation = Completer<void>();
    Widget app() => _app(
      _panel(
        config: _config,
        entries: entries,
        onDeleteSelected: (files) async {
          calls.add(files);
          if (calls.length == 1) await confirmation.future;
        },
      ),
    );
    await tester.pumpWidget(app());
    await _tap(tester, find.text('多选'));
    await _tap(tester, find.text('全选'));
    await _tap(tester, find.text('删除'));
    final delete = find.widgetWithText(TextButton, '删除');
    expect(tester.widget<TextButton>(delete).onPressed, isNull);
    expect(calls.single, [_first, _second]);
    // 父页取消确认：没有修改 entries，也不应丢失多选状态。
    confirmation.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(delete).onPressed, isNotNull);
    expect(find.text('已选 2 份'), findsOneWidget);

    await _tap(tester, delete);
    // 复用父列表、更新同名条目元数据，模拟部分成功后父页发出新快照。
    const remaining = WebDavBackupEntry(name: 'second.json', size: 42);
    entries
      ..remove(_first)
      ..[0] = remaining;
    await tester.pumpWidget(app());
    expect(find.text('已选 1 份'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await _tap(tester, delete);
    expect(calls.last, [remaining]);
    entries.clear();
    await tester.pumpWidget(app());
    expect(find.text('多选'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('刷新即清除勾选，更换配置后同名文件不会被选中', (tester) async {
    var refreshes = 0;
    final otherConfig = WebDavConfig(serverUrl: 'https://other.example/dav/');
    Widget app(WebDavConfig config) => _app(
      _panel(
        key: ValueKey(config.root),
        config: config,
        entries: const [_first],
        onRefresh: () => refreshes++,
      ),
    );
    await tester.pumpWidget(app(_config));
    await _tap(tester, find.text('多选'));
    await _tap(tester, find.text('全选'));
    await _tap(tester, find.text('刷新'));
    expect(refreshes, 1);
    await _tap(tester, find.text('多选'));
    expect(find.text('已选 0 份'), findsOneWidget);
    await _tap(tester, find.text(_first.name));
    await tester.pumpWidget(app(otherConfig));
    await _tap(tester, find.text('多选'));
    expect(find.text('已选 0 份'), findsOneWidget);
  });

  testWidgets('普通模式保留原有单项恢复与删除菜单', (tester) async {
    WebDavBackupEntry? restored;
    WebDavBackupEntry? deleted;
    await tester.pumpWidget(
      _app(
        _panel(
          config: _config,
          entries: const [_first],
          onRestore: (entry) => restored = entry,
          onDelete: (entry) => deleted = entry,
        ),
      ),
    );
    final menu = find.byType(PopupMenuButton<String>);
    await _tap(tester, menu);
    await _tap(tester, find.text('恢复'));
    expect(restored, _first);
    expect(deleted, isNull);
    await _tap(tester, menu);
    await _tap(tester, find.text('删除'));
    expect(deleted, _first);
  });

  testWidgets('数量上限默认不限，验证任意整数输入，支持取消和恢复不限', (tester) async {
    final changes = <int>[];
    Widget app() => _app(
      StatefulBuilder(
        builder: (context, setState) => _panel(
          config: _config,
          retentionLimit: changes.lastOrNull ?? 0,
          onRetentionChanged: (value) => setState(() => changes.add(value)),
        ),
      ),
    );
    await tester.pumpWidget(app());
    final tile = find.widgetWithText(ListTile, '备份数量上限');
    final unlimited = find.widgetWithText(SwitchListTile, '不限');
    final save = find.widgetWithText(FilledButton, '保存');
    final field = find.byType(TextFormField);
    expect(find.text('不限'), findsOneWidget);
    await _tap(tester, tile);
    expect(find.text('上传成功后，若超过上限，自动删除最旧的远端备份。'), findsOneWidget);
    await _tap(tester, unlimited);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    for (final invalid in ['-2', '1.5', '0x10', 'invalid']) {
      await tester.enterText(field, invalid);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text('请输入正整数'), findsOneWidget);
    }
    await tester.enterText(field, '12345');
    await tester.pump();
    await _tap(tester, save);
    expect(changes, [12345]);
    expect(find.text('12345 份'), findsOneWidget);
    await _tap(tester, tile);
    await _tap(tester, unlimited);
    await _tap(tester, find.text('取消'));
    expect(changes, [12345]);
    await _tap(tester, tile);
    await _tap(tester, unlimited);
    await _tap(tester, save);
    expect(changes, [12345, 0]);
    expect(find.text('不限'), findsOneWidget);
  });

  testWidgets('输入 0 同样可恢复为不限，忙碌时不允许编辑上限', (tester) async {
    int? changed;
    Widget app({required bool interactive}) => _app(
      _panel(
        config: _config,
        interactive: interactive,
        retentionLimit: 13,
        onRetentionChanged: (value) => changed = value,
      ),
    );
    final tile = find.widgetWithText(ListTile, '备份数量上限');
    await tester.pumpWidget(app(interactive: false));
    expect(tester.widget<ListTile>(tile).enabled, isFalse);
    await _tap(tester, tile);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(app(interactive: true));
    await _tap(tester, tile);
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pump();
    await _tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(changed, 0);
  });
}
