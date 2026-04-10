import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/app_theme_option.dart';

void main() {
  test('resolveAppThemeOption returns matching preset', () {
    final option = resolveAppThemeOption('bright_blue');

    expect(option.label, '亮蓝');
    expect(option.seedColor, const Color(0xFF166FF3));
  });

  test('resolveAppThemeOption falls back to default preset', () {
    final option = resolveAppThemeOption('unknown-theme');

    expect(option.id, appThemeOptions.first.id);
  });
}
