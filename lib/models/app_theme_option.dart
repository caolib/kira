import 'package:flutter/material.dart';

@immutable
class AppThemeOption {
  final String id;
  final String label;
  final Color seedColor;

  const AppThemeOption({
    required this.id,
    required this.label,
    required this.seedColor,
  });
}

const customThemeOptionId = 'custom';
const defaultCustomThemeColor = Color(0xFF166FF3);

const appThemeOptions = <AppThemeOption>[
  AppThemeOption(
    id: 'blue_grey',
    label: '蓝灰',
    seedColor: Colors.blueGrey,
  ),
  AppThemeOption(
    id: 'teal',
    label: '青绿',
    seedColor: Colors.teal,
  ),
  AppThemeOption(
    id: 'indigo',
    label: '靛蓝',
    seedColor: Colors.indigo,
  ),
  AppThemeOption(
    id: 'green',
    label: '森绿',
    seedColor: Colors.green,
  ),
  AppThemeOption(
    id: 'orange',
    label: '橙金',
    seedColor: Colors.orange,
  ),
  AppThemeOption(
    id: 'pink',
    label: '粉色',
    seedColor: Color(0xFFFB7299),
  ),
  AppThemeOption(
    id: 'bright_blue',
    label: '亮蓝',
    seedColor: Color(0xFF166FF3),
  ),
];

AppThemeOption resolveAppThemeOption(String? id) {
  for (final option in appThemeOptions) {
    if (option.id == id) return option;
  }
  return appThemeOptions.first;
}
