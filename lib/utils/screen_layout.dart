/// 列表页的宽屏（横屏 / 桌面窗口）布局约定。
///
/// 内容宽度钳制在 [maxContentWidth] 以内、两侧留白居中；
/// 可用宽度达到 [wideBreakpoint] 后卡片最大宽度放大到 [wideCardExtent]
/// （与首页 `_mangaHomeCardMaxExtent` 规则一致），避免大屏一排挤满小卡片。
class ScreenLayout {
  const ScreenLayout._();

  static const maxContentWidth = 1200.0;
  static const wideBreakpoint = 720.0;
  static const compactCardExtent = 130.0;
  static const wideCardExtent = 150.0;

  static double contentWidth(double screenWidth) =>
      screenWidth.clamp(0.0, maxContentWidth);

  /// 内容区两侧水平留白（含 16 的基础内边距）。
  static double horizontalPadding(double screenWidth) =>
      (screenWidth - contentWidth(screenWidth)) / 2 + 16;

  static double cardExtent(double screenWidth) =>
      contentWidth(screenWidth) >= wideBreakpoint
      ? wideCardExtent
      : compactCardExtent;
}
