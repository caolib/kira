import 'package:flutter/painting.dart';

import '../../utils/font_manager.dart';

/// null 跟随应用，空字体族显式回退系统；绝不为阅读设置下载字体。
Future<String?> loadNovelReaderFont(String selection) async {
  if (selection.isEmpty) return null;
  if (selection == FontManager.defaultFontId) return '';
  return FontManager().loadFont(selection, rethrowErrors: true);
}

/// 只应用到内容文本，不改阅读器的 Theme，避免影响工具栏和目录。
TextStyle novelContentTextStyle(TextStyle base, String? fontFamily) =>
    fontFamily == null
    ? base
    : base.copyWith(fontFamily: fontFamily, fontFamilyFallback: const []);
