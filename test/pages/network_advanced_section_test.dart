import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/api_transport.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/api/network/network_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/network_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _NetworkApi implements NetworkApi {
  final connectivityCalls = <List<String>>[];
  Completer<String>? fillHost;

  @override
  List<String> getRouteHosts(int routeIndex) => const ['route.test'];

  @override
  List<String> getExtraApiHosts() => const [];

  @override
  Future<Map<String, int?>> testRouteLatency(
    int routeIndex, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    onHostResult?.call('route.test', 100);
    return {'route.test': 100};
  }

  @override
  Future<Map<String, int?>> testExtraApiLatency({
    void Function(String host, int? latency)? onHostResult,
  }) async => {};

  @override
  Future<Map<String, int?>> testHostsConnectivity(
    List<String> hosts, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    connectivityCalls.add(List.of(hosts));
    for (final host in hosts) {
      onHostResult?.call(host, 120);
    }
    return {for (final host in hosts) host: 120};
  }

  @override
  Future<String> fetchCopyApiHost() async =>
      fillHost?.future ?? Future.value('api.filled.test');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MangaApi implements MangaApi {
  @override
  Future<String> fetchCopyLatestAppVersion() async => '4.0.0';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements ApiClient {
  @override
  final _NetworkApi network = _NetworkApi();
  @override
  final manga = _MangaApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ApiClient original;
  late _Client client;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    original = ApiClient();
    client = _Client();
    ApiClient.setTestInstance(client);
  });

  tearDown(() {
    ApiClient.setTestInstance(original);
    teardownSecureCredentialStoreForTest();
  });

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  Finder getAddField() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == null,
  );
  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  Future<void> tap(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 300);
    }
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    double width = 375,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: wrapWithApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: Theme(
                data: ThemeData(brightness: brightness),
                child: const NetworkPage(),
              ),
            ),
          ),
          wrapInScaffold: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('拷贝登录域名'), findsNothing);
    expect(client.network.connectivityCalls, isEmpty);
    await tap(tester, find.text('高级设置'));
  }

  for (final width in [375.0, 900.0]) {
    testWidgets(
      'advanced layout groups hosts first and pairs versions at $width',
      (tester) async {
        await pumpPage(tester, width: width);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NetworkPage)),
        )!;
        expect(find.text(l10n.networkCopyLoginDomainHint), findsNothing);
        expect(find.text('COPY'), findsNothing);
        expect(find.text(l10n.networkCopyLoginDomainDefault), findsNothing);
        expect(find.text(l10n.networkCopyLoginDomainCustom), findsNothing);
        expect(getAddField(), findsNothing);
        expect(button('添加'), findsNothing);
        expect(find.text('copy4000.com'), findsOneWidget);
        expect(find.text('copy5000.com'), findsOneWidget);
        expect(UserManager().copyLoginHost, 'copy4000.com');
        expect(client.network.connectivityCalls, [copyLoginHostOptions]);
        expect(
          tester.getTopLeft(find.text(l10n.networkCopyLoginDomain)).dy,
          lessThan(tester.getTopLeft(find.text(l10n.networkCopyAutoUpdate)).dy),
        );
        final addButton = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '添加',
        );
        final addBackground = tester.widget<Material>(
          find.descendant(of: addButton, matching: find.byType(Material)),
        );
        expect(addBackground.color, isNot(Colors.transparent));
        expect(addBackground.color, isNotNull);
        for (final label in ['API URL', '请求版本号', 'versionCode']) {
          final input = field(label);
          final labelText = find.descendant(
            of: input,
            matching: find.text(label),
          );
          expect(
            tester.getTopRight(labelText).dx,
            closeTo(tester.getTopRight(input).dx - 16, 2),
          );
          final widget = tester.widget<TextField>(input);
          expect(widget.textDirection, TextDirection.ltr);
          expect(widget.textAlign, TextAlign.left);
        }
        final selectedText = tester.widget<Text>(find.text('copy4000.com'));
        final otherText = tester.widget<Text>(find.text('copy5000.com'));
        expect(selectedText.style, otherText.style);
        for (final host in ['copy4000.com', 'copy5000.com']) {
          final material = find
              .ancestor(of: find.text(host), matching: find.byType(Material))
              .first;
          expect(tester.widget<Material>(material).color, Colors.transparent);
        }
        final api = tester.getRect(field('API URL'));
        final version = tester.getRect(field(l10n.networkCopyAppVersion));
        final code = tester.getRect(field(l10n.networkCopyVersionCode));
        expect(version.top, code.top);
        expect(version.width, code.width);
        expect(version.left, api.left);
        expect(code.right, closeTo(api.right, 0.01));
        final save = tester.getRect(button(l10n.commentSettingsSaveButton));
        final fill = tester.getRect(button(l10n.networkFill));
        final reset = tester.getRect(button(l10n.commentSettingsResetButton));
        expect(fill.left, api.left);
        expect(save.right, api.right);
        expect(fill.top, reset.top);
        expect(fill.top, save.top);
        for (final rect in [fill, reset, save]) {
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        expect(tester.widget(button(l10n.networkFill)), isA<TextButton>());
        expect(
          tester.widget(button(l10n.commentSettingsSaveButton)),
          isA<FilledButton>(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (width, scale) in [(320.0, 1.0), (375.0, 2.0)]) {
    testWidgets(
      'narrow/large text stacks versions without overflow $width/$scale',
      (tester) async {
        await UserManager().addCustomCopyLoginHost('custom.example.test');
        await pumpPage(
          tester,
          width: width,
          scale: scale,
          brightness: Brightness.dark,
        );
        final version = tester.getRect(field('请求版本号'));
        final code = tester.getRect(field('versionCode'));
        expect(code.top, greaterThanOrEqualTo(version.bottom));
        expect(code.left, version.left);
        expect(code.width, version.width);
        await tester.ensureVisible(button('保存'));
        await tester.pump();
        expect(button('填充'), findsOneWidget);
        expect(button('重置'), findsOneWidget);
        expect(button('保存'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'add form stays hidden until requested and closes only on success',
    (tester) async {
      await pumpPage(tester);
      expect(getAddField(), findsNothing);
      await tap(tester, find.byTooltip('添加'));
      expect(getAddField(), findsOneWidget);
      await tester.enterText(getAddField(), 'copy5000.com');
      await tap(tester, button('添加'));
      expect(getAddField(), findsOneWidget);
      expect(UserManager().customCopyLoginHosts, isEmpty);
      await tap(tester, find.byTooltip('取消'));
      expect(getAddField(), findsNothing);
      await tap(tester, find.byTooltip('添加'));
      await tester.enterText(getAddField(), 'new.example.test');
      await tap(tester, button('添加'));
      expect(getAddField(), findsNothing);
      expect(button('添加'), findsNothing);
      expect(find.text('new.example.test'), findsOneWidget);
      expect(find.text('自定义'), findsNothing);
      expect(UserManager().copyLoginHost, 'copy4000.com');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save/reset preserve immediate domain and auto-update behavior', (
    tester,
  ) async {
    await pumpPage(tester);
    final user = UserManager();
    await tap(tester, find.byTooltip('添加'));
    await tester.enterText(getAddField(), 'custom.example.test');
    await tap(tester, button('添加'));
    expect(user.customCopyLoginHosts, ['custom.example.test']);
    expect(client.network.connectivityCalls.last, ['custom.example.test']);
    await tap(tester, find.text('custom.example.test'));
    expect(user.copyLoginHost, 'custom.example.test');
    await tap(tester, find.text('每天自动更新'));
    expect(user.copyAutoUpdate, isFalse);

    await tester.enterText(field('API URL'), 'api.edited.test');
    await tester.enterText(field('请求版本号'), '5.0.0');
    await tester.enterText(field('versionCode'), '99');
    expect(user.copyApiHost, defaultCopyApiHost);
    expect(user.copyAppVersion, defaultCopyAppVersion);
    await tap(tester, button('保存'));
    expect(user.copyApiHost, 'api.edited.test');
    expect(user.copyAppVersion, '5.0.0');
    expect(user.copyVersionCode, '99');
    await tap(tester, button('重置'));
    expect(user.copyApiHost, defaultCopyApiHost);
    expect(user.copyAppVersion, defaultCopyAppVersion);
    expect(user.copyVersionCode, defaultCopyVersionCode);
    expect(user.copyLoginHost, 'custom.example.test');
    expect(user.copyAutoUpdate, isFalse);

    await tap(tester, find.text('高级设置'));
    expect(find.text('拷贝登录域名'), findsNothing);
    await tap(tester, find.text('高级设置'));
    expect(client.network.connectivityCalls.last, user.copyLoginHostChoices);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom domain edit and delete remain accessible on a phone', (
    tester,
  ) async {
    final user = UserManager();
    await user.addCustomCopyLoginHost('custom.example.test');
    await user.setCopyLoginHost('custom.example.test');
    await pumpPage(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(NetworkPage)))!;
    final edit = find.byTooltip(l10n.aiConfigEdit);
    final delete = find.byTooltip(l10n.deleteButton);
    expect(tester.getSize(edit).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(delete).height, greaterThanOrEqualTo(48));
    await tap(tester, edit);
    await tester.pump(const Duration(milliseconds: 300));
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'renamed.example.test',
    );
    await tap(tester, find.descendant(of: dialog, matching: button('保存')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(user.copyLoginHost, 'renamed.example.test');
    expect(client.network.connectivityCalls.last, ['renamed.example.test']);
    await tap(tester, delete);
    expect(user.copyLoginHost, defaultCopyLoginHost);
    expect(user.customCopyLoginHosts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fill keeps draft-only behavior and loading button states', (
    tester,
  ) async {
    await pumpPage(tester);
    client.network.fillHost = Completer<String>();
    await tap(tester, button('填充'));
    expect(tester.widget<TextButton>(button('填充')).onPressed, isNull);
    expect(tester.widget<TextButton>(button('重置')).onPressed, isNull);
    expect(tester.widget<FilledButton>(button('保存')).onPressed, isNotNull);
    client.network.fillHost!.complete('api.filled.test');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<TextField>(field('API URL')).controller!.text,
      'api.filled.test',
    );
    expect(tester.widget<TextField>(field('请求版本号')).controller!.text, '4.0.0');
    expect(
      tester.widget<TextField>(field('versionCode')).controller!.text,
      defaultCopyVersionCode,
    );
    expect(UserManager().copyApiHost, defaultCopyApiHost);
    expect(UserManager().copyAppVersion, defaultCopyAppVersion);
    expect(tester.widget<TextButton>(button('填充')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
