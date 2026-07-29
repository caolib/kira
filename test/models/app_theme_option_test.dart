import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/app_theme_option.dart';

void main() {
  test('resolveAppThemeOption returns matching preset', () {
    final option = resolveAppThemeOption('bright_blue');

    // label 是英文回退值；面向用户的名字走 localizedLabel。
    expect(option.id, 'bright_blue');
    expect(option.label, 'Bright Blue');
    expect(option.seedColor, const Color(0xFF166FF3));
  });

  test('resolveAppThemeOption falls back to default preset', () {
    final option = resolveAppThemeOption('unknown-theme');

    expect(option.id, appThemeOptions.first.id);
  });

  testWidgets('localizedLabel resolves through l10n', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context)!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolveAppThemeOption('bright_blue').localizedLabel(l10n), '亮蓝');
    expect(
      resolveAppThemeOption('teal').localizedLabel(l10n),
      l10n.themeColorTeal,
    );
  });

  testWidgets('every preset has a localized label', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context)!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // 新增预设时若漏加 l10n 分支，localizedLabel 会静默回退到英文 label。
    for (final option in appThemeOptions) {
      expect(
        option.localizedLabel(l10n),
        isNot(option.label),
        reason: '${option.id} 缺少本地化名称，回退到了英文 label',
      );
    }
  });
}
