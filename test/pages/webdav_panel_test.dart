import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_schedule.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/pages/backup/webdav_panel.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

final _config = WebDavConfig(serverUrl: 'https://dav.example/dav/');

WebDavPanel _panel({
  bool enabled = true,
  bool interactive = true,
  WebDavConfig? config,
  List<WebDavBackupEntry> entries = const [],
  BackupSchedule schedule = const BackupSchedule(),
  String? error,
  bool listed = false,
  ValueChanged<bool>? onToggle,
  VoidCallback? onConfigure,
}) => WebDavPanel(
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
  onRefresh: () {},
  onRestore: (_) {},
  onDelete: (_) {},
  onScheduleChanged: (_) {},
);

/// 定时备份也是 SwitchListTile，总开关按标题定位。
final _masterSwitch = find.ancestor(
  of: find.text('WebDAV'),
  matching: find.byType(SwitchListTile),
);

void main() {
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
}
