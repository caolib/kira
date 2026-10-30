import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/json_helpers.dart';
import 'novel_dialogue_style.dart';

enum NovelReaderTheme { paper, dark, white, green, gray }

/// 阅读模式：连续滚动 / 整页翻页。翻页模式固定左到右横向翻页。
enum NovelReaderMode { scroll, paged }

/// ID 与名称分离：重命名不会改变浅色/深色模式的选择。
@immutable
class NovelReaderCustomTheme {
  const NovelReaderCustomTheme({
    required this.id,
    required this.name,
    int backgroundColor = NovelReaderSettings.defaultCustomBackgroundColor,
    int textColor = NovelReaderSettings.defaultCustomTextColor,
  }) : backgroundColor = backgroundColor < 0 || backgroundColor > 0xFFFFFFFF
           ? NovelReaderSettings.defaultCustomBackgroundColor
           : backgroundColor | 0xFF000000,
       textColor = textColor < 0 || textColor > 0xFFFFFFFF
           ? NovelReaderSettings.defaultCustomTextColor
           : textColor | 0xFF000000;

  final String id;
  final String name;
  final int backgroundColor;
  final int textColor;

  factory NovelReaderCustomTheme.fromJson(Map<String, dynamic> json) =>
      NovelReaderCustomTheme(
        id: jsonString(json, 'id').trim(),
        name: jsonString(json, 'name').trim(),
        backgroundColor: jsonInt(
          json,
          'backgroundColor',
          fallback: NovelReaderSettings.defaultCustomBackgroundColor,
        ),
        textColor: jsonInt(
          json,
          'textColor',
          fallback: NovelReaderSettings.defaultCustomTextColor,
        ),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'backgroundColor': backgroundColor,
    'textColor': textColor,
  };

  NovelReaderCustomTheme copyWith({
    String? name,
    int? backgroundColor,
    int? textColor,
  }) => NovelReaderCustomTheme(
    id: id,
    name: name ?? this.name,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    textColor: textColor ?? this.textColor,
  );

  @override
  bool operator ==(Object other) =>
      other is NovelReaderCustomTheme &&
      id == other.id &&
      name == other.name &&
      backgroundColor == other.backgroundColor &&
      textColor == other.textColor;

  @override
  int get hashCode => Object.hash(id, name, backgroundColor, textColor);
}

/// 仅保存小说排版、配色与常亮偏好；状态组件直接使用 ReaderSettings。
@immutable
class NovelReaderSettings {
  const NovelReaderSettings({
    double fontSize = defaultFontSize,
    double lineHeight = defaultLineHeight,
    double paragraphSpacing = defaultParagraphSpacing,
    double contentWidth = defaultContentWidth,
    this.lightThemeId = defaultLightThemeId,
    this.darkThemeId = defaultDarkThemeId,
    this.keepScreenOn = true,
    this.mode = NovelReaderMode.scroll,
    this.realisticPageTurn = true,
    this.instantPageTurn = false,
    this.volumeKey = true,
    this.ignoreBlankParagraphs = defaultIgnoreBlankParagraphs,
    this.focusModeEnabled = defaultFocusModeEnabled,
    this.focusKeepStatusVisible = defaultFocusKeepStatusVisible,
    this.dialogueEnabled = false,
    this.lightDialogueStyle = const NovelDialogueStyle(),
    this.darkDialogueStyle = const NovelDialogueStyle(
      backgroundColor: NovelDialogueStyle.defaultDarkBackgroundColor,
    ),
    double focusTopRatio = defaultFocusTopRatio,
    double focusBottomRatio = defaultFocusBottomRatio,
    double focusOpacity = defaultFocusOpacity,
  }) : _customThemes = const [],
       fontSize = fontSize != fontSize
           ? defaultFontSize
           : fontSize < minFontSize
           ? minFontSize
           : fontSize > maxFontSize
           ? maxFontSize
           : fontSize,
       lineHeight = lineHeight != lineHeight
           ? defaultLineHeight
           : lineHeight < minLineHeight
           ? minLineHeight
           : lineHeight > maxLineHeight
           ? maxLineHeight
           : lineHeight,
       paragraphSpacing = paragraphSpacing != paragraphSpacing
           ? defaultParagraphSpacing
           : paragraphSpacing < minParagraphSpacing
           ? minParagraphSpacing
           : paragraphSpacing > maxParagraphSpacing
           ? maxParagraphSpacing
           : paragraphSpacing,
       contentWidth = contentWidth != contentWidth
           ? defaultContentWidth
           : contentWidth < minContentWidth
           ? minContentWidth
           : contentWidth > maxContentWidth
           ? maxContentWidth
           : contentWidth,
       focusTopRatio = focusTopRatio != focusTopRatio
           ? defaultFocusTopRatio
           : focusTopRatio < minFocusTopRatio
           ? minFocusTopRatio
           : focusTopRatio > maxFocusTopRatio
           ? maxFocusTopRatio
           : focusTopRatio,
       _focusBottomRatio = focusBottomRatio != focusBottomRatio
           ? defaultFocusBottomRatio
           : focusBottomRatio < minFocusBottomRatio
           ? minFocusBottomRatio
           : focusBottomRatio > maxFocusBottomRatio
           ? maxFocusBottomRatio
           : focusBottomRatio,
       focusOpacity = focusOpacity != focusOpacity
           ? defaultFocusOpacity
           : focusOpacity < minFocusOpacity
           ? minFocusOpacity
           : focusOpacity > maxFocusOpacity
           ? maxFocusOpacity
           : focusOpacity;

  NovelReaderSettings._withThemes(
    NovelReaderSettings base,
    List<NovelReaderCustomTheme> themes,
  ) : fontSize = base.fontSize,
      lineHeight = base.lineHeight,
      paragraphSpacing = base.paragraphSpacing,
      contentWidth = base.contentWidth,
      lightThemeId = base.lightThemeId,
      darkThemeId = base.darkThemeId,
      keepScreenOn = base.keepScreenOn,
      mode = base.mode,
      realisticPageTurn = base.realisticPageTurn,
      instantPageTurn = base.instantPageTurn,
      volumeKey = base.volumeKey,
      ignoreBlankParagraphs = base.ignoreBlankParagraphs,
      focusModeEnabled = base.focusModeEnabled,
      focusKeepStatusVisible = base.focusKeepStatusVisible,
      dialogueEnabled = base.dialogueEnabled,
      lightDialogueStyle = base.lightDialogueStyle,
      darkDialogueStyle = base.darkDialogueStyle,
      focusTopRatio = base.focusTopRatio,
      _focusBottomRatio = base.focusBottomRatio,
      focusOpacity = base.focusOpacity,
      _customThemes = List.unmodifiable(themes);

  static const storageKey = 'reader_novel_settings_v1';
  static const minFontSize = 10.0;
  static const maxFontSize = 48.0;
  static const defaultFontSize = 20.0;
  // height < 1 时行盒小于字形高度，中文上下行会重叠，下限只能到 1。
  static const minLineHeight = 1.0;
  static const maxLineHeight = 3.0;
  static const defaultLineHeight = 1.8;
  static const minParagraphSpacing = 0.0;
  static const maxParagraphSpacing = 64.0;
  static const defaultParagraphSpacing = 16.0;
  static const minContentWidth = 320.0;
  static const maxContentWidth = 1200.0;
  static const defaultContentWidth = 720.0;
  static const defaultLightThemeId = 'white';

  /// 内置「灰」主题（#222222/#C8C8C8）为深色模式默认。
  static const defaultDarkThemeId = 'gray';
  static const legacyCustomThemeId = 'custom-legacy';
  static const defaultCustomBackgroundColor = 0xFFF3EEDC;
  static const defaultCustomTextColor = 0xFF38352D;

  /// 网译源 txt 常以空行分隔段落；默认保留空行，开启后仅隐藏显示，
  /// 源数据与段落下标不变。
  static const defaultIgnoreBlankParagraphs = false;

  /// 专注模式：上下黑遮罩夹出中间可见区，两边界至少相隔 10% 屏高。
  static const defaultFocusModeEnabled = false;
  static const defaultFocusKeepStatusVisible = false;
  static const minFocusGapRatio = 0.1;
  static const minFocusTopRatio = 0.0;
  static const maxFocusTopRatio = 0.9;
  static const defaultFocusTopRatio = 0.2;
  static const minFocusBottomRatio = 0.1;
  static const maxFocusBottomRatio = 1.0;
  static const defaultFocusBottomRatio = 0.55;
  static const minFocusOpacity = 0.1;
  static const maxFocusOpacity = 0.9;
  static const defaultFocusOpacity = 0.5;

  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;

  /// 正文最大宽度（逻辑像素）；窄屏仍保留安全区与两侧最小留白。
  final double contentWidth;
  final String lightThemeId;
  final String darkThemeId;
  final bool keepScreenOn;
  final NovelReaderMode mode;

  /// 翻页模式下使用仿真翻页，关闭时使用平移动画；[instantPageTurn] 优先。
  final bool realisticPageTurn;

  /// 翻页模式下瞬时跳页（无过渡动画），与漫画阅读器的「无动画翻页」同一语义。
  final bool instantPageTurn;

  /// 翻页模式下允许音量键翻页（音量+上一页、音量-下一页）。
  final bool volumeKey;

  /// 隐藏正文里的空白段落（仅影响显示，不改变段落下标与锚点身份）。
  final bool ignoreBlankParagraphs;

  /// 专注模式开关：开启后上下各加一条半透明黑遮罩。
  final bool focusModeEnabled;

  /// 专注遮罩不遮挡状态组件；不改变状态组件自身的开关与显隐规则。
  final bool focusKeepStatusVisible;

  /// 全局对白样式开关；「」与『』共用样式。
  final bool dialogueEnabled;
  final NovelDialogueStyle lightDialogueStyle;
  final NovelDialogueStyle darkDialogueStyle;

  NovelDialogueStyle dialogueStyleFor({required bool dark}) =>
      dark ? darkDialogueStyle : lightDialogueStyle;

  /// 可见区上/下边界，占屏幕高度比例；遮罩触摸穿透，不挡翻页与点按。
  final double focusTopRatio;
  final double _focusBottomRatio;
  double get focusBottomRatio =>
      _focusBottomRatio < focusTopRatio + minFocusGapRatio
      ? focusTopRatio + minFocusGapRatio
      : _focusBottomRatio;

  /// 遮罩不透明度。
  final double focusOpacity;
  final List<NovelReaderCustomTheme> _customThemes;
  List<NovelReaderCustomTheme> get customThemes => _customThemes;

  static Future<void>? _queue;

  bool hasTheme(String id) =>
      NovelReaderTheme.values.any((theme) => theme.name == id) ||
      _customThemes.any((theme) => theme.id == id);

  /// 对未知/已删除 ID 的回退与存储分离，旧备份也能立即安全显示。
  String themeIdFor({required bool dark}) {
    final id = dark ? darkThemeId : lightThemeId;
    return hasTheme(id)
        ? id
        : (dark ? defaultDarkThemeId : defaultLightThemeId);
  }

  String newCustomThemeId() {
    final base = 'custom-${DateTime.now().microsecondsSinceEpoch}';
    var id = base;
    var suffix = 1;
    while (hasTheme(id)) {
      id = '$base-${suffix++}';
    }
    return id;
  }

  factory NovelReaderSettings.fromJson(Map<String, dynamic> json) {
    final legacyTheme = jsonString(json, 'theme');
    final themes = <NovelReaderCustomTheme>[];
    final seen = NovelReaderTheme.values.map((theme) => theme.name).toSet();
    final rawThemes = json['customThemes'];
    if (rawThemes is List) {
      for (final raw in rawThemes) {
        if (raw is! Map<String, dynamic>) continue;
        final theme = NovelReaderCustomTheme.fromJson(raw);
        if (theme.id.isEmpty || theme.name.isEmpty || !seen.add(theme.id)) {
          continue;
        }
        themes.add(theme);
      }
    } else if (legacyTheme == 'custom' ||
        json.containsKey('customBackgroundColor') ||
        json.containsKey('customTextColor')) {
      themes.add(
        NovelReaderCustomTheme(
          id: legacyCustomThemeId,
          name: '自定义',
          backgroundColor: jsonInt(
            json,
            'customBackgroundColor',
            fallback: defaultCustomBackgroundColor,
          ),
          textColor: jsonInt(
            json,
            'customTextColor',
            fallback: defaultCustomTextColor,
          ),
        ),
      );
    }
    final legacyId = legacyTheme == 'custom'
        ? legacyCustomThemeId
        : NovelReaderTheme.values.any((theme) => theme.name == legacyTheme)
        ? legacyTheme
        : null;
    return NovelReaderSettings(
      fontSize: jsonDouble(json, 'fontSize', fallback: defaultFontSize),
      lineHeight: jsonDouble(json, 'lineHeight', fallback: defaultLineHeight),
      paragraphSpacing: jsonDouble(
        json,
        'paragraphSpacing',
        fallback: defaultParagraphSpacing,
      ),
      contentWidth: jsonDouble(
        json,
        'contentWidth',
        fallback: defaultContentWidth,
      ),
      lightThemeId: jsonString(
        json,
        'lightThemeId',
        fallback: legacyId ?? defaultLightThemeId,
      ),
      darkThemeId: jsonString(
        json,
        'darkThemeId',
        fallback: legacyId ?? defaultDarkThemeId,
      ),
      keepScreenOn: jsonBool(json, 'keepScreenOn', fallback: true),
      // 未知/缺失的阅读模式回退滚动：旧版本记录与损坏数据都安全。
      mode: _modeFromJson(jsonString(json, 'mode')),
      realisticPageTurn: jsonBool(json, 'realisticPageTurn', fallback: true),
      instantPageTurn: jsonBool(json, 'instantPageTurn'),
      volumeKey: jsonBool(json, 'volumeKey', fallback: true),
      // 旧记录没有该键时保持默认（保留空行）。
      ignoreBlankParagraphs: jsonBool(json, 'ignoreBlankParagraphs'),
      // 旧记录没有专注模式各键时：默认关闭、默认区域与浓度。
      focusModeEnabled: jsonBool(json, 'focusModeEnabled'),
      focusKeepStatusVisible: jsonBool(json, 'focusKeepStatusVisible'),
      dialogueEnabled: jsonBool(json, 'dialogueEnabled'),
      lightDialogueStyle: NovelDialogueStyle.fromJson(
        jsonMap(json, 'lightDialogueStyle') ?? const {},
      ),
      darkDialogueStyle: NovelDialogueStyle.fromJson(
        jsonMap(json, 'darkDialogueStyle') ?? const {},
        defaults: const NovelDialogueStyle(
          backgroundColor: NovelDialogueStyle.defaultDarkBackgroundColor,
        ),
      ),
      focusTopRatio: jsonDouble(
        json,
        'focusTopRatio',
        fallback: defaultFocusTopRatio,
      ),
      focusBottomRatio: jsonDouble(
        json,
        'focusBottomRatio',
        fallback: defaultFocusBottomRatio,
      ),
      focusOpacity: jsonDouble(
        json,
        'focusOpacity',
        fallback: defaultFocusOpacity,
      ),
    ).copyWith(customThemes: themes);
  }

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paragraphSpacing': paragraphSpacing,
    'contentWidth': contentWidth,
    'lightThemeId': themeIdFor(dark: false),
    'darkThemeId': themeIdFor(dark: true),
    'customThemes': _customThemes.map((theme) => theme.toJson()).toList(),
    'keepScreenOn': keepScreenOn,
    'mode': mode.name,
    'realisticPageTurn': realisticPageTurn,
    'instantPageTurn': instantPageTurn,
    'volumeKey': volumeKey,
    'ignoreBlankParagraphs': ignoreBlankParagraphs,
    'focusModeEnabled': focusModeEnabled,
    'focusKeepStatusVisible': focusKeepStatusVisible,
    'dialogueEnabled': dialogueEnabled,
    'lightDialogueStyle': lightDialogueStyle.toJson(),
    'darkDialogueStyle': darkDialogueStyle.toJson(),
    'focusTopRatio': focusTopRatio,
    'focusBottomRatio': focusBottomRatio,
    'focusOpacity': focusOpacity,
  };

  NovelReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? contentWidth,
    String? lightThemeId,
    String? darkThemeId,
    List<NovelReaderCustomTheme>? customThemes,
    bool? keepScreenOn,
    NovelReaderMode? mode,
    bool? realisticPageTurn,
    bool? instantPageTurn,
    bool? volumeKey,
    bool? ignoreBlankParagraphs,
    bool? focusModeEnabled,
    bool? focusKeepStatusVisible,
    bool? dialogueEnabled,
    NovelDialogueStyle? lightDialogueStyle,
    NovelDialogueStyle? darkDialogueStyle,
    double? focusTopRatio,
    double? focusBottomRatio,
    double? focusOpacity,
  }) {
    final bottom = focusBottomRatio == null
        ? this.focusBottomRatio
        : focusBottomRatio.isNaN
        ? defaultFocusBottomRatio
        : focusBottomRatio.clamp(minFocusBottomRatio, maxFocusBottomRatio);
    // 单独下调下边界时联动上边界；上调上边界则由 getter 抬高下边界。
    final top =
        focusTopRatio ??
        (focusBottomRatio != null &&
                this.focusTopRatio + minFocusGapRatio > bottom
            ? (bottom - minFocusGapRatio).clamp(
                minFocusTopRatio,
                maxFocusTopRatio,
              )
            : this.focusTopRatio);
    final base = NovelReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      contentWidth: contentWidth ?? this.contentWidth,
      lightThemeId: lightThemeId ?? this.lightThemeId,
      darkThemeId: darkThemeId ?? this.darkThemeId,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      mode: mode ?? this.mode,
      realisticPageTurn: realisticPageTurn ?? this.realisticPageTurn,
      instantPageTurn: instantPageTurn ?? this.instantPageTurn,
      volumeKey: volumeKey ?? this.volumeKey,
      ignoreBlankParagraphs:
          ignoreBlankParagraphs ?? this.ignoreBlankParagraphs,
      focusModeEnabled:
          focusModeEnabled ??
          (mode == NovelReaderMode.paged && this.mode != NovelReaderMode.paged
              ? false
              : this.focusModeEnabled),
      focusKeepStatusVisible:
          focusKeepStatusVisible ?? this.focusKeepStatusVisible,
      dialogueEnabled: dialogueEnabled ?? this.dialogueEnabled,
      lightDialogueStyle: lightDialogueStyle ?? this.lightDialogueStyle,
      darkDialogueStyle: darkDialogueStyle ?? this.darkDialogueStyle,
      focusTopRatio: top,
      focusBottomRatio: bottom,
      focusOpacity: focusOpacity ?? this.focusOpacity,
    );
    final seen = NovelReaderTheme.values.map((theme) => theme.name).toSet();
    final themes = (customThemes ?? _customThemes)
        .where(
          (theme) =>
              theme.id.isNotEmpty &&
              theme.name.trim().isNotEmpty &&
              seen.add(theme.id),
        )
        .toList();
    // 绑定 ID 原样保留：upsert 顺序上主题可能刚要进入列表，此时不能把
    // 绑定改写成回退值；未知 ID 的兜底只发生在 themeIdFor 展示时。
    return NovelReaderSettings._withThemes(base, themes);
  }

  NovelReaderSettings upsertCustomTheme(NovelReaderCustomTheme theme) =>
      copyWith(
        customThemes: [
          for (final saved in _customThemes)
            if (saved.id != theme.id) saved,
          theme,
        ],
      );

  NovelReaderSettings removeCustomTheme(String id) => copyWith(
    customThemes: _customThemes.where((theme) => theme.id != id).toList(),
  );

  /// 每次读取当前 prefs，因此导入/重置后无需额外 reload 内存副本。
  static Future<NovelReaderSettings> load({
    Future<SharedPreferences>? prefs,
  }) => _enqueue(() async {
    final preferences = await (prefs ?? SharedPreferences.getInstance());
    try {
      final raw = preferences.get(storageKey);
      if (raw == null) return const NovelReaderSettings();
      if (raw is! String) {
        throw const FormatException('Novel reader settings must be JSON text');
      }
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Novel reader settings must be an object');
      }
      return NovelReaderSettings.fromJson(json);
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Ignored invalid novel reader settings (${error.runtimeType})',
          stackTrace: stack,
          source: 'novel_reader_settings.load',
        ),
      );
      return const NovelReaderSettings();
    }
  });

  Future<void> save({Future<SharedPreferences>? prefs}) => _enqueue(() async {
    final preferences = await (prefs ?? SharedPreferences.getInstance());
    if (!await preferences.setString(storageKey, jsonEncode(toJson()))) {
      throw StateError('Novel reader settings persistence failed');
    }
  });

  // 快速拖动字号滑块时，慢写入不能在较新设置之后才落盘。
  static Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = (_queue ?? Future<void>.value()).then((_) => action());
    late final Future<void> tail;
    void releaseIfIdle() {
      if (identical(_queue, tail)) _queue = null;
    }

    tail = operation.then<void>(
      (_) => releaseIfIdle(),
      onError: (Object error, StackTrace stack) {
        releaseIfIdle();
        unawaited(
          AppLogger.instance.recordWarning(
            error,
            stackTrace: stack,
            source: 'novel_reader_settings',
          ),
        );
      },
    );
    _queue = tail;
    return operation;
  }

  @override
  bool operator ==(Object other) =>
      other is NovelReaderSettings &&
      fontSize == other.fontSize &&
      lineHeight == other.lineHeight &&
      paragraphSpacing == other.paragraphSpacing &&
      contentWidth == other.contentWidth &&
      themeIdFor(dark: false) == other.themeIdFor(dark: false) &&
      themeIdFor(dark: true) == other.themeIdFor(dark: true) &&
      listEquals(_customThemes, other._customThemes) &&
      keepScreenOn == other.keepScreenOn &&
      mode == other.mode &&
      realisticPageTurn == other.realisticPageTurn &&
      instantPageTurn == other.instantPageTurn &&
      volumeKey == other.volumeKey &&
      ignoreBlankParagraphs == other.ignoreBlankParagraphs &&
      focusModeEnabled == other.focusModeEnabled &&
      focusKeepStatusVisible == other.focusKeepStatusVisible &&
      dialogueEnabled == other.dialogueEnabled &&
      lightDialogueStyle == other.lightDialogueStyle &&
      darkDialogueStyle == other.darkDialogueStyle &&
      focusTopRatio == other.focusTopRatio &&
      focusBottomRatio == other.focusBottomRatio &&
      focusOpacity == other.focusOpacity;

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    paragraphSpacing,
    contentWidth,
    themeIdFor(dark: false),
    themeIdFor(dark: true),
    Object.hashAll(_customThemes),
    keepScreenOn,
    mode,
    realisticPageTurn,
    instantPageTurn,
    volumeKey,
    ignoreBlankParagraphs,
    focusModeEnabled,
    focusKeepStatusVisible,
    focusTopRatio,
    focusBottomRatio,
    focusOpacity,
    Object.hash(dialogueEnabled, lightDialogueStyle, darkDialogueStyle),
  );
}

/// 未知/缺失的阅读模式一律回退到滚动，保证旧记录与损坏数据可读。
NovelReaderMode _modeFromJson(String raw) => NovelReaderMode.values.firstWhere(
  (mode) => mode.name == raw,
  orElse: () => NovelReaderMode.scroll,
);
