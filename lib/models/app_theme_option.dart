import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

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

@immutable
class AppThemeVariantOption {
  final DynamicSchemeVariant variant;
  final String label;
  final String description;

  const AppThemeVariantOption({
    required this.variant,
    required this.label,
    required this.description,
  });

  String get id => variant.name;
}

const customThemeOptionId = 'custom';
const defaultCustomThemeColor = Color(0xFF166FF3);

const appThemeOptions = <AppThemeOption>[
  AppThemeOption(
    id: 'blue_grey',
    label: 'Blue Grey',
    seedColor: Colors.blueGrey,
  ),
  AppThemeOption(id: 'teal', label: 'Teal', seedColor: Colors.teal),
  AppThemeOption(id: 'indigo', label: 'Indigo', seedColor: Colors.indigo),
  AppThemeOption(id: 'green', label: 'Green', seedColor: Colors.green),
  AppThemeOption(id: 'orange', label: 'Orange', seedColor: Colors.orange),
  AppThemeOption(id: 'pink', label: 'Pink', seedColor: Color(0xFFFB7299)),
  AppThemeOption(
    id: 'bright_blue',
    label: 'Bright Blue',
    seedColor: Color(0xFF166FF3),
  ),
  AppThemeOption(id: 'violet', label: 'Violet', seedColor: Color(0xFF7E57C2)),
  AppThemeOption(id: 'orchid', label: 'Orchid', seedColor: Color(0xFFAB47BC)),
  AppThemeOption(id: 'cyan', label: 'Cyan', seedColor: Color(0xFF00ACC1)),
  AppThemeOption(id: 'emerald', label: 'Emerald', seedColor: Color(0xFF1F9D72)),
  AppThemeOption(id: 'lime', label: 'Lime', seedColor: Color(0xFF7CB342)),
  AppThemeOption(id: 'amber', label: 'Amber', seedColor: Color(0xFFF9A825)),
  AppThemeOption(id: 'coral', label: 'Coral', seedColor: Color(0xFFFF7043)),
];

const appThemeVariantOptions = <AppThemeVariantOption>[
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.tonalSpot,
    label: 'Tonal',
    description: 'Material default style.',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.vibrant,
    label: 'Vibrant',
    description: 'Higher primary color saturation.',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.expressive,
    label: 'Expressive',
    description: 'More expressive hue shift.',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.fidelity,
    label: 'Fidelity',
    description: 'Closer to the selected primary color.',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.content,
    label: 'Content',
    description: 'Container colors stay closer to primary.',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.neutral,
    label: 'Neutral',
    description: 'More neutral grayscale look.',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.monochrome,
    label: 'Monochrome',
    description: 'Fully grayscale.',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.rainbow,
    label: 'Rainbow',
    description: 'More colorful and lively.',
  ),
];

extension AppThemeOptionL10n on AppThemeOption {
  String localizedLabel(AppLocalizations l10n) => switch (id) {
    'blue_grey' => l10n.themeColorBlueGrey,
    'teal' => l10n.themeColorTeal,
    'indigo' => l10n.themeColorIndigo,
    'green' => l10n.themeColorGreen,
    'orange' => l10n.themeColorOrange,
    'pink' => l10n.themeColorPink,
    'bright_blue' => l10n.themeColorBrightBlue,
    'violet' => l10n.themeColorViolet,
    'orchid' => l10n.themeColorOrchid,
    'cyan' => l10n.themeColorCyan,
    'emerald' => l10n.themeColorEmerald,
    'lime' => l10n.themeColorLime,
    'amber' => l10n.themeColorAmber,
    'coral' => l10n.themeColorCoral,
    customThemeOptionId => l10n.themeColorCustom,
    _ => label,
  };
}

extension AppThemeVariantOptionL10n on AppThemeVariantOption {
  String localizedLabel(AppLocalizations l10n) => switch (variant) {
    DynamicSchemeVariant.tonalSpot => l10n.themeVariantTonalSpot,
    DynamicSchemeVariant.vibrant => l10n.themeVariantVibrant,
    DynamicSchemeVariant.expressive => l10n.themeVariantExpressive,
    DynamicSchemeVariant.fidelity => l10n.themeVariantFidelity,
    DynamicSchemeVariant.content => l10n.themeVariantContent,
    DynamicSchemeVariant.neutral => l10n.themeVariantNeutral,
    DynamicSchemeVariant.monochrome => l10n.themeVariantMonochrome,
    DynamicSchemeVariant.rainbow => l10n.themeVariantRainbow,
    _ => label,
  };

  String localizedDescription(AppLocalizations l10n) => switch (variant) {
    DynamicSchemeVariant.tonalSpot => l10n.themeVariantTonalSpotDesc,
    DynamicSchemeVariant.vibrant => l10n.themeVariantVibrantDesc,
    DynamicSchemeVariant.expressive => l10n.themeVariantExpressiveDesc,
    DynamicSchemeVariant.fidelity => l10n.themeVariantFidelityDesc,
    DynamicSchemeVariant.content => l10n.themeVariantContentDesc,
    DynamicSchemeVariant.neutral => l10n.themeVariantNeutralDesc,
    DynamicSchemeVariant.monochrome => l10n.themeVariantMonochromeDesc,
    DynamicSchemeVariant.rainbow => l10n.themeVariantRainbowDesc,
    _ => description,
  };
}

AppThemeOption resolveAppThemeOption(String? id) {
  for (final option in appThemeOptions) {
    if (option.id == id) return option;
  }
  return appThemeOptions.first;
}

AppThemeVariantOption resolveAppThemeVariantOption(String? id) {
  for (final option in appThemeVariantOptions) {
    if (option.id == id) return option;
  }
  return appThemeVariantOptions.first;
}
