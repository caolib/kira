part of '../search_page.dart';

extension _SearchHeader on _SearchPageState {
  /// 下滑浏览时把搜索框收起，上滑或回到顶部再放出来；输入过程中不收。
  /// 顶部判断对所有滚动通知生效（结果太少、不可滚动时不发 UserScroll，
  /// 否则切到短结果列表后搜索框会卡在收起态再也回不来）。
  void _updateHeaderVisibility(ScrollNotification n) {
    if (n.metrics.pixels <= n.metrics.minScrollExtent) {
      _setHeaderVisible(true);
      return;
    }
    if (n is! UserScrollNotification) return;
    switch (n.direction) {
      case ScrollDirection.forward:
        _setHeaderVisible(true);
      case ScrollDirection.reverse:
        _setHeaderVisible(_searchFocus.hasFocus);
      case ScrollDirection.idle:
        break;
    }
  }

  /// 悬浮头占位高度：上下内边距 + SearchBar（M3 默认 56）。
  double _headerContentHeight() {
    return 12.0 + 56.0 + AppSpacing.lg;
  }

  Widget _buildSearchHeader(BuildContext context, double hp) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 12, hp, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchBar(
            controller: _searchController,
            focusNode: _searchFocus,
            hintText: l10n.searchHint(_modeLabel(l10n)),
            leading: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.search),
            ),
            trailing: _canClearSearch
                ? [
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l10n.searchClearTooltip,
                      onPressed: _clearSearch,
                    ),
                  ]
                : null,
            onSubmitted: _doSearch,
          ),
        ],
      ),
    );
  }

  /// 选中 tag 后右下角浮出的工具条：上一行回到顶部，下一行 tag 胶囊 + 热度/更新排序。
  /// 样式参照章节评论区右下角悬浮按钮（chapter_comments_sheet）。
  Widget _buildFloatingToolbar(BuildContext context, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;

    // 胶囊（tag / 排序）：选中态用 primaryContainer，未选中用 surfaceContainerHighest。
    ButtonStyle chipStyle(bool selected) => FilledButton.styleFrom(
      backgroundColor: selected
          ? cs.primaryContainer
          : cs.surfaceContainerHighest,
      foregroundColor: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      elevation: selected ? 4 : 0,
      shadowColor: AppShadows.floatingTint(0.22),
      minimumSize: const Size(0, 44),
      maximumSize: const Size.fromHeight(44),
      fixedSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    // 方形按钮（回到顶部）。
    final squareStyle = FilledButton.styleFrom(
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      elevation: 6,
      shadowColor: AppShadows.floatingTint(0.22),
      minimumSize: const Size.square(48),
      maximumSize: const Size.square(48),
      fixedSize: const Size.square(48),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return SafeArea(
      top: false,
      child: AnimatedSlide(
        offset: _headerVisible ? Offset.zero : const Offset(0, 1.2),
        curve: Curves.easeInOutCubic,
        duration: const Duration(milliseconds: 200),
        child: AnimatedOpacity(
          opacity: _headerVisible ? 1.0 : 0.0,
          curve: Curves.easeInOutCubic,
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 回到顶部：任何可滚动列表都出现，不依赖 tag。
              if (_canScrollUp)
                SizedBox.square(
                  dimension: 48,
                  child: FilledButton(
                    style: squareStyle,
                    onPressed: _scrollToTop,
                    child: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              // 回到顶部与 tag 工具条同时存在时的间距。
              if (_canScrollUp && _selectedTag != null)
                const SizedBox(height: AppSpacing.sm),
              // tag 胶囊 + 排序：仅 tag 浏览态。
              if (_selectedTag != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      style: chipStyle(true),
                      onPressed: () => _selectTag(null),
                      icon: const Icon(Icons.label_outline),
                      label: Text(_selectedTagName),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      style: chipStyle(true),
                      onPressed: _toggleOrdering,
                      icon: Icon(
                        _ordering == ApiOrdering.popular
                            ? Icons.whatshot
                            : Icons.schedule,
                      ),
                      label: Text(
                        _ordering == ApiOrdering.popular
                            ? l10n.popularOrder
                            : l10n.updateOrder,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 可折叠区块的标题行：左侧图标 + 标题（+ 可选 trailing），右侧旋转箭头随展开/收起翻转。
  Widget _buildSectionHeader({
    required IconData icon,
    required Color color,
    required String title,
    required bool expanded,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.xsR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
            const Spacer(),
            AnimatedRotation(
              turns: expanded ? 0.0 : 0.5,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOutCubic,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
