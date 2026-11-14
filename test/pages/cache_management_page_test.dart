import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_journal.dart';
import 'package:kira/models/copy_account_store.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/cache_management_page.dart';
import 'package:kira/repositories/novel_repository.dart';
import 'package:kira/utils/font_manager.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backup/backup_test_support.dart';
import '../test_helpers.dart';

/// 缓存管理页的真实文件 IO（目录扫描、删除）在 widget 测试的 fake async
/// 时钟里不会完成，所以加载与清理链路都要在 [tester.runAsync] 里跑。
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.temporaryPath,
    required this.supportPath,
  });

  final String temporaryPath;
  final String supportPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => supportPath;
}

late Directory _root;
late Directory _tempDir;
late Directory _supportDir;
PathProviderPlatform? _originalPathProvider;

Future<void> _setUpPaths(WidgetTester tester) async {
  _originalPathProvider = PathProviderPlatform.instance;
  await tester.runAsync(() async {
    _root = await Directory.systemTemp.createTemp('kira_cache_mgmt_test');
    _tempDir = Directory('${_root.path}/tmp')..createSync();
    _supportDir = Directory('${_root.path}/support')..createSync();
  });
  PathProviderPlatform.instance = _FakePathProviderPlatform(
    temporaryPath: _tempDir.path,
    supportPath: _supportDir.path,
  );
  // FontManager 单例缓存着上一个测试临时目录里的字体路径，必须重置，
  // 否则页面扫描失效目录会整体进错误视图。
  FontManager().reloadFromPrefs();
}

void _tearDownPaths() {
  PathProviderPlatform.instance = _originalPathProvider!;
  if (_root.existsSync()) {
    _root.deleteSync(recursive: true);
  }
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      wrapWithApp(const CacheManagementPage(), wrapInScaffold: false),
    );
    // 轮询到 initState 里的真实目录扫描完成、页面退出加载态为止。
    // 加载链路 rooted 在 runAsync 的真实 zone 里，fake async 时钟推不动它，
    // 固定延时等待会有竞态。
    for (var i = 0; i < 250; i++) {
      if (find.byType(ExpressiveLoadingIndicator).evaluate().isEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// 展开数据缓存分组里的某个 ExpansionTile（必要时先滚动到可见）。
Future<void> _expandSection(WidgetTester tester, String title) async {
  final tile = find.widgetWithText(ExpansionTile, title);
  await tester.scrollUntilVisible(
    tile,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // scrollUntilVisible 只保证元素进入列表，标题可能仍卡在视口边缘，
  // 直接 tap 会命中不到，因此再对齐一次。
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  final entries = find.descendant(of: tile, matching: find.byType(ListView));
  if (entries.evaluate().isEmpty) {
    // Tapping an expanded tile's center can hit a data row and open its dialog.
    await tester.tap(find.descendant(of: tile, matching: find.text(title)));
    await tester.pumpAndSettle();
  }
}

const _credentialPrefix = SecureCredentialStore.preferencePrefix;

Future<void> _prepareCredentialPage(
  WidgetTester tester, {
  Object primaryToken = 'primary-session-token',
}) async {
  await _setUpPaths(tester);
  addTearDown(_tearDownPaths);
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const copy = CopyAccountSession(
    token: 'copy-session-token',
    userId: 'copy-id',
  );
  final copyRecord = jsonEncode({
    'migrationHandled': true,
    'accounts': [copy.toJson()],
    'activeId': copy.id,
  });
  final rollbackKey = base64Encode(List<int>.filled(32, 7));
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({
      'user_token': 'stale-primary-token',
      '${_credentialPrefix}user_token': primaryToken,
      'user_id': 'primary-id',
      'login_source': 'copy',
      'copy_account_v1': copyRecord,
      '${_credentialPrefix}copy_account_v1': copyRecord,
      'credentials_migrated_to_secure': true,
      '${_credentialPrefix}credentials_migrated_to_secure': 'true',
      'backup_rollback_key_v1': rollbackKey,
      '${_credentialPrefix}backup_rollback_key_v1': rollbackKey,
      'backup_webdav_credentials_v1': 'legacy-dav-secret',
      '${_credentialPrefix}backup_webdav_credentials_v1': 'dav-secret',
      'backup_password_v1': 'legacy-backup-password',
      '${_credentialPrefix}backup_password_v1': 'backup-password',
      'banner_visible': false,
      'cache_home': 'cached-home',
    });
    SecureCredentialStore.resetInstance();
    await UserManager().init(persistMigrations: false);
  });
  await _pumpPage(tester);
}

Future<Finder> _credentialEntry(WidgetTester tester, String key) async {
  final section = find.widgetWithText(ExpansionTile, '账号数据');
  final entry = find.descendant(of: section, matching: find.text(key));
  await tester.scrollUntilVisible(
    entry,
    120,
    scrollable: find.descendant(of: section, matching: find.byType(Scrollable)),
  );
  return find.ancestor(of: entry, matching: find.byType(ListTile)).first;
}

Future<void> _confirmDeletion(WidgetTester tester, Finder button) async {
  await tester.runAsync(() async {
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 400));
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '删除'),
    );
    await tester.tap(confirm);
    var completed = false;
    for (var i = 0; i < 250; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.textContaining('已删除').evaluate().isNotEmpty &&
          find.byType(ExpressiveLoadingIndicator).evaluate().isEmpty) {
        completed = true;
        break;
      }
    }
    expect(
      completed,
      isTrue,
      reason: 'deletion and runtime reload must finish',
    );
  });
  await tester.pumpAndSettle();
  final toast = find.textContaining('已删除');
  if (toast.evaluate().isNotEmpty) {
    await tester.tap(toast.first);
    await tester.pumpAndSettle();
  }
}

Future<void> _clearPreferenceSection(WidgetTester tester, String title) async {
  await _expandSection(tester, title);
  final button = find.descendant(
    of: find.widgetWithText(ExpansionTile, title),
    matching: find.widgetWithText(FilledButton, '清空'),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await _confirmDeletion(tester, button);
}

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  for (final logicalKey in ['user_token', 'copy_account_v1']) {
    for (final prefix in ['', _credentialPrefix]) {
      testWidgets('删除 $prefix$logicalKey 保留退出标记，重启不从别名复活', (tester) async {
        await _prepareCredentialPage(tester);
        await _expandSection(tester, '账号数据');
        final entry = await _credentialEntry(tester, '$prefix$logicalKey');
        await _confirmDeletion(
          tester,
          find.descendant(of: entry, matching: find.byTooltip('删除')),
        );
        await tester.runAsync(() async {
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.containsKey(logicalKey), isFalse);
          if (logicalKey == 'user_token') {
            expect(prefs.getString('${_credentialPrefix}user_token'), '');
          } else {
            final raw = prefs.getString('${_credentialPrefix}copy_account_v1');
            expect(raw, isNotNull);
            expect(jsonDecode(raw!)['cleared'], isTrue);
          }
          for (var start = 0; start < 2; start++) {
            SharedPreferences.resetStatic();
            SecureCredentialStore.resetInstance();
            await UserManager().init();
            expect(UserManager().isLoggedIn, logicalKey != 'user_token');
            expect(
              UserManager().copyAccount.isLoggedIn,
              logicalKey != 'copy_account_v1',
            );
          }
        });
      });
    }
  }

  for (final multiSelect in [false, true]) {
    testWidgets('${multiSelect ? '多选删除' : '分区清空'}账号保留退出与恢复密钥', (tester) async {
      await _prepareCredentialPage(tester);
      late String? rollbackKey;
      await tester.runAsync(() async {
        rollbackKey = await SecureCredentialStore().readBackupRollbackKey();
        await EncryptedBackupJournal(
          directory: () async => _supportDir,
        ).save(backupDocument({'banner_visible': true}));
      });
      if (multiSelect) {
        await tester.tap(find.byTooltip('多选卡片'));
        await tester.pumpAndSettle();
        final account = find.widgetWithText(ListTile, '账号数据');
        await tester.ensureVisible(account);
        await tester.tap(account);
        await tester.pumpAndSettle();
        await _confirmDeletion(tester, find.byTooltip('删除选中卡片'));
      } else {
        await _clearPreferenceSection(tester, '账号数据');
      }
      await tester.runAsync(() async {
        SharedPreferences.resetStatic();
        SecureCredentialStore.resetInstance();
        await UserManager().init();
        final credentials = SecureCredentialStore();
        expect(await credentials.readToken(), '');
        expect(UserManager().isLoggedIn, isFalse);
        expect(UserManager().copyAccount.isLoggedIn, isFalse);
        expect(
          jsonDecode((await credentials.readCopyAccountRecord())!)['cleared'],
          isTrue,
        );
        expect(await credentials.readWebDavCredentials(), isNull);
        expect(await credentials.readBackupPassword(), isNull);
        expect(await credentials.readBackupRollbackKey(), rollbackKey);
        final pending = await EncryptedBackupJournal(
          directory: () async => _supportDir,
        ).read();
        expect(pending?.preferences['banner_visible']?.value, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('cache_home'), 'cached-home');
        expect(prefs.getBool('banner_visible'), isFalse);
      });
    });
  }

  testWidgets('普通设置与业务缓存清理保留主账号、COPY 和本机凭据', (tester) async {
    await _prepareCredentialPage(tester);
    await _expandSection(tester, '账号数据');
    for (final key in ['backup_webdav_credentials_v1', 'backup_password_v1']) {
      final entry = await _credentialEntry(tester, key);
      expect(
        find.descendant(of: entry, matching: find.byTooltip('显示敏感内容')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: entry, matching: find.textContaining('legacy-')),
        findsNothing,
      );
    }
    await _clearPreferenceSection(tester, '应用设置');
    await _clearPreferenceSection(tester, '业务缓存 / home');
    await tester.runAsync(() async {
      SharedPreferences.resetStatic();
      SecureCredentialStore.resetInstance();
      await UserManager().init();
      expect(UserManager().token, 'primary-session-token');
      expect(UserManager().copyToken, 'copy-session-token');
      expect(
        await SecureCredentialStore().readWebDavCredentials(),
        'dav-secret',
      );
      expect(
        await SecureCredentialStore().readBackupPassword(),
        'backup-password',
      );
      expect(await SecureCredentialStore().readBackupRollbackKey(), isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('banner_visible'), isFalse);
      expect(prefs.containsKey('cache_home'), isFalse);
    });
  });

  for (final wrapped in [false, true]) {
    testWidgets('正式凭据默认脱敏，显隐状态同时控制详情与复制，列表=$wrapped', (tester) async {
      final token = wrapped
          ? 'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu-secret'
          : 'primary-session-token';
      await _prepareCredentialPage(
        tester,
        primaryToken: wrapped ? [token] : token,
      );
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments;
            if (arguments is Map && arguments['text'] is String) {
              copied.add(arguments['text'].toString());
            }
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _expandSection(tester, '账号数据');
      final entry = await _credentialEntry(
        tester,
        '${_credentialPrefix}user_token',
      );
      expect(
        find.descendant(of: entry, matching: find.textContaining(token)),
        findsNothing,
      );
      Future<void> copyDetail() async {
        await tester.tap(
          find.descendant(
            of: entry,
            matching: find.text('${_credentialPrefix}user_token'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, '复制'),
          ),
        );
        await tester.pumpAndSettle();
      }

      await copyDetail();
      expect(copied.last, '••••••');
      await tester.tap(
        find.descendant(of: entry, matching: find.byTooltip('显示敏感内容')),
      );
      await tester.pumpAndSettle();
      await copyDetail();
      if (wrapped) {
        expect(jsonDecode(copied.last), [token]);
      } else {
        expect(copied.last, token);
      }
      await tester.tap(
        find.descendant(of: entry, matching: find.byTooltip('隐藏敏感内容')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: entry, matching: find.textContaining(token)),
        findsNothing,
      );
    });
  }

  testWidgets('轻小说正文缓存独立成节，不再挂在图片缓存分组下', (tester) async {
    await _setUpPaths(tester);
    addTearDown(_tearDownPaths);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Directory(
      '${_supportDir.path}/${FileNovelCacheStore.directoryName}',
    ).createSync();
    File(
      '${_supportDir.path}/${FileNovelCacheStore.directoryName}/volume.json',
    ).writeAsStringSync('{"text":"hi"}');

    await _pumpPage(tester);

    expect(find.text('图片缓存'), findsOneWidget);
    // 旧组合标签「图片缓存 / xxx」不再出现。
    expect(find.textContaining('图片缓存 /'), findsNothing);
    expect(find.text('漫画阅读器'), findsOneWidget);
    expect(find.text('小说插图'), findsOneWidget);
    expect(find.text('封面与头像'), findsOneWidget);

    expect(find.text('轻小说缓存'), findsOneWidget);
    expect(find.text('轻小说正文缓存'), findsOneWidget);
    expect(find.textContaining('1 个文件'), findsOneWidget);

    // 图片缓存分组包含漫画、小说插图与封面，正文缓存独立成节。
    double dy(Finder finder) => tester.getTopLeft(finder).dy;
    final imageHeader = dy(find.text('图片缓存'));
    final readerCard = dy(find.text('漫画阅读器'));
    final illustrationCard = dy(find.text('小说插图'));
    final coverCard = dy(find.text('封面与头像'));
    final novelHeader = dy(find.text('轻小说缓存'));
    final novelCard = dy(find.text('轻小说正文缓存'));
    expect(readerCard, greaterThan(imageHeader));
    expect(illustrationCard, greaterThan(readerCard));
    expect(coverCard, greaterThan(illustrationCard));
    expect(novelHeader, greaterThan(coverCard));
    expect(novelCard, greaterThan(novelHeader));
  });

  testWidgets('轻小说书签归入轻小说阅读记录，而不是其他数据', (tester) async {
    await _setUpPaths(tester);
    addTearDown(_tearDownPaths);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'novel_bookmarks_v1': '{"items":[]}',
      'mystery_orphan_key': 'orphan-value',
    });

    await _pumpPage(tester);

    final warning = find.textContaining('删除会丢失');
    await tester.scrollUntilVisible(
      warning,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(warning, findsOneWidget);

    await _expandSection(tester, '轻小说阅读记录');
    expect(
      find.descendant(
        of: find.widgetWithText(ExpansionTile, '轻小说阅读记录'),
        matching: find.text('novel_bookmarks_v1'),
      ),
      findsOneWidget,
    );

    await _expandSection(tester, '其他数据');
    final otherTile = find.widgetWithText(ExpansionTile, '其他数据');
    expect(
      find.descendant(of: otherTile, matching: find.text('novel_bookmarks_v1')),
      findsNothing,
    );
    expect(
      find.descendant(of: otherTile, matching: find.text('mystery_orphan_key')),
      findsOneWidget,
    );
  });

  testWidgets('清除轻小说正文缓存只删除正文目录', (tester) async {
    await _setUpPaths(tester);
    addTearDown(_tearDownPaths);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final novelDir = Directory(
      '${_supportDir.path}/${FileNovelCacheStore.directoryName}',
    )..createSync();
    File('${novelDir.path}/volume.json').writeAsStringSync('{"text":"hi"}');

    await _pumpPage(tester);

    // 清空按钮和确认弹窗整段在 runAsync 内交互：弹窗由 fake zone 之外的
    // tap 打开，整条清理链路才 rooted 在真实 zone，目录 IO 才能完成。
    final novelCard = find
        .ancestor(of: find.text('轻小说正文缓存'), matching: find.byType(Card))
        .first;
    final cardClearButton = find.descendant(
      of: novelCard,
      matching: find.widgetWithText(FilledButton, '清空'),
    );
    final dialogClearButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '清空'),
    );
    await tester.runAsync(() async {
      await tester.tap(cardClearButton);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('清除已缓存的轻小说正文'), findsOneWidget);
      await tester.tap(dialogClearButton);
      // 等 Navigator.pop 之后的真实目录删除与页面刷新完成。
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(novelDir.existsSync(), isFalse);
  });
}
