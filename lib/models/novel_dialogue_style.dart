import 'package:flutter/foundation.dart';

import '../utils/json_helpers.dart';

enum NovelDialogueColorMode { automatic, body, custom }

enum NovelDialogueWeight { body, medium, bold }

/// 浅色或深色阅读模式的对白样式；引号类型共用，不改变原始正文。
@immutable
class NovelDialogueStyle {
  const NovelDialogueStyle({
    this.colorMode = NovelDialogueColorMode.body,
    int textColor = defaultTextColor,
    this.weight = NovelDialogueWeight.body,
    this.backgroundEnabled = true,
    int backgroundColor = defaultBackgroundColor,
    double backgroundOpacity = defaultBackgroundOpacity,
  }) : textColor = textColor < 0 || textColor > 0xFFFFFFFF
           ? defaultTextColor
           : textColor | 0xFF000000,
       backgroundColor = backgroundColor < 0 || backgroundColor > 0xFFFFFFFF
           ? defaultBackgroundColor
           : backgroundColor | 0xFF000000,
       backgroundOpacity = backgroundOpacity != backgroundOpacity
           ? defaultBackgroundOpacity
           : backgroundOpacity < 0
           ? 0
           : backgroundOpacity > 1
           ? 1
           : backgroundOpacity;

  static const defaultTextColor = 0xFF476B83;
  static const defaultBackgroundColor = 0xFF000000;
  static const defaultDarkBackgroundColor = 0xFFFFFFFF;
  static const defaultBackgroundOpacity = 0.1;

  final NovelDialogueColorMode colorMode;
  final int textColor;
  final NovelDialogueWeight weight;
  final bool backgroundEnabled;
  final int backgroundColor;
  final double backgroundOpacity;

  factory NovelDialogueStyle.fromJson(
    Map<String, dynamic> json, {
    NovelDialogueStyle defaults = const NovelDialogueStyle(),
  }) => NovelDialogueStyle(
    colorMode: NovelDialogueColorMode.values.firstWhere(
      (mode) => mode.name == jsonString(json, 'colorMode'),
      orElse: () => defaults.colorMode,
    ),
    textColor: jsonInt(json, 'textColor', fallback: defaults.textColor),
    weight: NovelDialogueWeight.values.firstWhere(
      (weight) => weight.name == jsonString(json, 'weight'),
      orElse: () => defaults.weight,
    ),
    backgroundEnabled: jsonBool(
      json,
      'backgroundEnabled',
      fallback: defaults.backgroundEnabled,
    ),
    backgroundColor: jsonInt(
      json,
      'backgroundColor',
      fallback: defaults.backgroundColor,
    ),
    backgroundOpacity: jsonDouble(
      json,
      'backgroundOpacity',
      fallback: defaults.backgroundOpacity,
    ),
  );

  Map<String, dynamic> toJson() => {
    'colorMode': colorMode.name,
    'textColor': textColor,
    'weight': weight.name,
    'backgroundEnabled': backgroundEnabled,
    'backgroundColor': backgroundColor,
    'backgroundOpacity': backgroundOpacity,
  };

  NovelDialogueStyle copyWith({
    NovelDialogueColorMode? colorMode,
    int? textColor,
    NovelDialogueWeight? weight,
    bool? backgroundEnabled,
    int? backgroundColor,
    double? backgroundOpacity,
  }) => NovelDialogueStyle(
    colorMode: colorMode ?? this.colorMode,
    textColor: textColor ?? this.textColor,
    weight: weight ?? this.weight,
    backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
  );

  @override
  bool operator ==(Object other) =>
      other is NovelDialogueStyle &&
      colorMode == other.colorMode &&
      textColor == other.textColor &&
      weight == other.weight &&
      backgroundEnabled == other.backgroundEnabled &&
      backgroundColor == other.backgroundColor &&
      backgroundOpacity == other.backgroundOpacity;

  @override
  int get hashCode => Object.hash(
    colorMode,
    textColor,
    weight,
    backgroundEnabled,
    backgroundColor,
    backgroundOpacity,
  );
}
