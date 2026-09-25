import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/pages/backup/webdav_connection_dialog.dart';

typedef Choice = (WebDavConfig?, WebDavCredentials);

void main() {
  late List<Choice?> results;

  Future<void> openDialog(
    WidgetTester tester, {
    WebDavConfig? config,
    WebDavCredentials credentials = const WebDavCredentials(
      username: '',
      password: '',
    ),
  }) async {
    results = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                results.add(
                  await showDialog<Choice>(
                    context: context,
                    builder: (_) => WebDavConnectionDialog(
                      config: config,
                      credentials: credentials,
                    ),
                  ),
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
  }

  TextField field(WidgetTester tester, String label) =>
      tester.widget<TextField>(
        find.ancestor(of: find.text(label), matching: find.byType(TextField)),
      );

  String textOf(WidgetTester tester, String label) =>
      field(tester, label).controller!.text;

  testWidgets('重置按钮清空服务器、用户名和密码', (tester) async {
    await openDialog(
      tester,
      config: WebDavConfig(
        serverUrl: 'https://dav.example/dav/',
        directory: 'kira/',
      ),
      credentials: const WebDavCredentials(
        username: 'user',
        password: 'secret',
      ),
    );
    expect(textOf(tester, '服务器地址'), 'https://dav.example/dav/');

    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();

    expect(textOf(tester, '服务器地址'), isEmpty);
    expect(textOf(tester, '用户名'), isEmpty);
    expect(textOf(tester, '密码'), isEmpty);
    // 文件夹不属于连接凭据，重置回到默认值。
    expect(textOf(tester, '备份文件夹（可选）'), 'kira/backups/');
  });

  testWidgets('三个字段都为空时允许保存并回传清除结果', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(results.single, isNotNull);
    expect(results.single!.$1, isNull);
    expect(results.single!.$2.username, isEmpty);
  });

  testWidgets('只填了部分字段时保存被拦下', (tester) async {
    await openDialog(tester);

    await tester.enterText(
      find.ancestor(of: find.text('服务器地址'), matching: find.byType(TextField)),
      'https://dav.example/dav/',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请填写用户名'), findsOneWidget);
    expect(find.text('请填写密码'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('清空已有配置后保存同样回传清除结果', (tester) async {
    await openDialog(
      tester,
      config: WebDavConfig(serverUrl: 'https://dav.example/dav/'),
      credentials: const WebDavCredentials(
        username: 'user',
        password: 'secret',
      ),
    );

    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(results.single!.$1, isNull);
  });
}
