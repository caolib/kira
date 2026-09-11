part of '../comic_detail_page.dart';

/// 章节卡片内容高度 = 内边距 12 + 标题行高 16s + 间距 2 + 副标题行高 ~17.5s，
/// 实测约 15.5 + 33.5s（s 为文字缩放），再加安全余量取 18 + 33.5s。
/// 网格 mainAxisExtent 固定 52 时 s≈1.14 起即纵向溢出，
/// 故按缩放推导卡片高度，最低保持 52。
double chapterTileExtent(double textScale) {
  final extent = 18 + 33.5 * textScale;
  return extent > 52 ? extent : 52;
}

/// 详情页是否启用横屏左右分栏：宽 > 高（横屏/宽窗口）且宽度 ≥640。
/// 竖屏（包括平板竖持）维持单列滚动布局。
bool comicDetailUsesTwoPane(Size size) =>
    size.width > size.height && size.width >= 640;

/// 分栏布局左侧信息栏宽度：约为窗口 36%，夹在 300~420 之间，
/// 保证按钮和 chips 不会过窄也不会被拉满整行。
double comicDetailInfoPaneWidth(Size size) =>
    (size.width * 0.36).clamp(300.0, 420.0);

/// 详情页章节卡片：标题 + 状态副标题的紧凑卡片。
/// 在网格中使用时必须以 [chapterTileExtent] 的返回值作为 mainAxisExtent，
/// 否则大字号/高显示缩放下内容会纵向溢出。
class ChapterCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool isSelected;
  final bool isLastRead;
  final bool isRead;
  final bool isDownloaded;
  final double? progressRatio;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChapterCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.isSelected,
    required this.isLastRead,
    required this.isRead,
    required this.isDownloaded,
    required this.onTap,
    this.onLongPress,
    this.progressRatio,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final brightness = theme.brightness;

    final backgroundColor = isSelected
        ? cs.secondaryContainer
        : isLastRead
        ? cs.primaryContainer
        : isRead
        ? Color.alphaBlend(
            cs.primary.withValues(
              alpha: brightness == Brightness.dark ? 0.16 : 0.08,
            ),
            cs.surfaceContainerLow,
          )
        : cs.surfaceContainerLow;
    final foregroundColor = isSelected
        ? cs.onSecondaryContainer
        : isLastRead
        ? cs.onPrimaryContainer
        : isRead
        ? cs.onSurface.withValues(
            alpha: brightness == Brightness.dark ? 0.70 : 0.62,
          )
        : cs.onSurface;
    final subtitleColor = isSelected
        ? foregroundColor.withValues(alpha: 0.8)
        : isRead && !isLastRead
        ? cs.onSurfaceVariant.withValues(
            alpha: brightness == Brightness.dark ? 0.72 : 0.62,
          )
        : cs.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.mdR,
        border: Border.all(
          color: isSelected
              ? cs.primary
              : cs.outlineVariant.withValues(
                  alpha: brightness == Brightness.dark ? 0.22 : 0.45,
                ),
          width: isSelected ? 1.4 : 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: brightness == Brightness.dark ? 0.30 : 0.14,
            ),
            blurRadius: brightness == Brightness.dark ? 12 : 14,
            spreadRadius: brightness == Brightness.dark ? 0 : -1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: AppRadius.mdR,
            child: InkWell(
              borderRadius: AppRadius.mdR,
              onTap: onTap,
              onLongPress: onLongPress,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: foregroundColor,
                          fontWeight: isLastRead || isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: tt.labelSmall?.copyWith(
                          color: subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isDownloaded)
            const Positioned(top: 4, right: 4, child: _DownloadedBadge()),
          if (progressRatio != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(10),
                ),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: progressRatio,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(2),
        child: Icon(Icons.check, size: 12, color: Colors.white),
      ),
    );
  }
}
