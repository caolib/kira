import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/main.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Future<ThemeData> _appTheme(WidgetTester tester, Brightness brightness) async {
  // 读取生产主题，但避开首页的数据请求。
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/general';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  await UserManager().init();
  await tester.pumpWidget(const ProviderScope(child: KiraApp()));
  await tester.pumpAndSettle();
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  final theme = brightness == Brightness.light ? app.theme! : app.darkTheme!;
  await tester.pumpWidget(const SizedBox.shrink());
  tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
  return theme;
}

Future<void> _pumpSearchBar(
  WidgetTester tester,
  ThemeData theme, {
  required TextEditingController controller,
  double textScale = 1,
  ValueChanged<String>? onSubmitted,
}) async {
  await tester.pumpWidget(
    wrapWithApp(
      Theme(
        data: theme,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 320,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => SearchBar(
                  controller: controller,
                  hintText: '搜索作品',
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.search),
                  ),
                  trailing: value.text.isEmpty
                      ? null
                      : [
                          IconButton(
                            tooltip: '清空搜索',
                            icon: const Icon(Icons.clear),
                            onPressed: controller.clear,
                          ),
                        ],
                  onSubmitted: onSubmitted,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Material _searchMaterial(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(of: find.byType(SearchBar), matching: find.byType(Material))
      .first,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await (await AppStorage.sharedPreferences()).clear();
  });

  tearDown(() {
    teardownSecureCredentialStoreForTest();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '$brightness 搜索栏高度为 48，清除按钮不撑高且可点击',
      (tester) async {
        final theme = await _appTheme(tester, brightness);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? submitted;
        await _pumpSearchBar(
          tester,
          theme,
          controller: controller,
          onSubmitted: (value) => submitted = value,
        );

        expect(tester.getSize(find.byType(SearchBar)), const Size(320, 48));
        expect(_searchMaterial(tester).elevation, 0);
        expect(
          _searchMaterial(tester).color,
          theme.colorScheme.surfaceContainerHigh,
        );
        expect(
          _searchMaterial(tester).shape,
          StadiumBorder(
            side: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
          ),
        );
        final field = tester.widget<TextField>(find.byType(TextField));
        final resolvedTheme = Theme.of(tester.element(find.byType(SearchBar)));
        expect(
          field.style?.fontSize,
          resolvedTheme.textTheme.bodyLarge?.fontSize,
        );
        expect(tester.getSize(find.byIcon(Icons.search)), const Size(24, 24));

        await tester.enterText(find.byType(TextField), '作品');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(submitted, '作品');
        expect(tester.getSize(find.byType(SearchBar)).height, 48);
        final clearRect = tester.getRect(
          find.widgetWithIcon(IconButton, Icons.clear),
        );
        expect(clearRect.size, const Size(48, 48));
        expect(_searchMaterial(tester).elevation, 0);
        await tester.tapAt(clearRect.topCenter + const Offset(0, 2));
        await tester.pumpAndSettle();
        expect(controller.text, isEmpty);
        expect(find.byTooltip('清空搜索'), findsNothing);
        expect(tester.getSize(find.byType(SearchBar)).height, 48);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      '$brightness 大字号搜索栏可增高而不裁切',
      (tester) async {
        final theme = await _appTheme(tester, brightness);
        final controller = TextEditingController(text: '作品');
        addTearDown(controller.dispose);
        await _pumpSearchBar(
          tester,
          theme,
          controller: controller,
          textScale: 3,
        );

        final barRect = tester.getRect(find.byType(SearchBar));
        final textRect = tester.getRect(find.byType(EditableText));
        expect(barRect.height, greaterThan(48));
        expect(textRect.top, greaterThanOrEqualTo(barRect.top));
        expect(textRect.bottom, lessThanOrEqualTo(barRect.bottom));
        expect(_searchMaterial(tester).elevation, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
