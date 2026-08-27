part of '../reader_page.dart';

class _ReaderSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;
  const _ReaderSettingsPanel({required this.onChanged});

  @override
  State<_ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<_ReaderSettingsPanel> {
  final _user = UserManager();
  final _stats = ImageLoadStats();
  bool _isDraggingBrightness = false;

  List<String> get _scrollDirectionLabels => [
    AppLocalizations.of(context)!.readerLeftToRight,
    AppLocalizations.of(context)!.readerRightToLeft,
    AppLocalizations.of(context)!.readerTopToBottom,
  ];

  @override
  void initState() {
    super.initState();
    _stats.addListener(_onStatsChanged);
  }

  @override
  void dispose() {
    _stats.removeListener(_onStatsChanged);
    super.dispose();
  }

  void _onStatsChanged() {
    if (mounted) setState(() {});
  }

  /// 当前状态显示段位顺序（由持久化配置决定）。
  List<String> get _statusSegments => _user.reader.statusOverlayOrder;

  /// 拖动调整状态显示段位的显示顺序。
  void _onStatusSegmentReorder(int oldIndex, int newIndex) {
    setState(() {
      final order = [..._user.reader.statusOverlayOrder];
      final item = order.removeAt(oldIndex);
      order.insert(newIndex, item);
      _user.reader.setStatusOverlayOrder(order);
    });
    widget.onChanged();
  }

  Widget _buildStatusSegmentRow(AppLocalizations l10n, String id, int index) {
    final (title, value, onChanged) = switch (id) {
      'time' => (
        l10n.readerStatusTime,
        _user.reader.statusOverlayTime,
        _user.reader.setStatusOverlayTime,
      ),
      'network' => (
        l10n.readerStatusNetwork,
        _user.reader.statusOverlayNetwork,
        _user.reader.setStatusOverlayNetwork,
      ),
      'battery' => (
        l10n.readerStatusBattery,
        _user.reader.statusOverlayBattery,
        _user.reader.setStatusOverlayBattery,
      ),
      'page' => (
        l10n.readerStatusPage,
        _user.reader.statusOverlayPage,
        _user.reader.setStatusOverlayPage,
      ),
      'fps' => (
        l10n.readerStatusFps,
        _user.reader.statusOverlayFps,
        _user.reader.setStatusOverlayFps,
      ),
      _ => (l10n.readerStatusTime, false, _user.reader.setStatusOverlayTime),
    };
    return Padding(
      key: ValueKey(id),
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Icon(Icons.drag_handle, size: 18),
            ),
          ),
          Expanded(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(title),
              value: value,
              onChanged: (v) {
                onChanged(v);
                setState(() {});
                widget.onChanged();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme cs, TextTheme tt) {
    final line = Divider(
      height: 1,
      color: cs.outlineVariant.withValues(alpha: 0.5),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              title,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: line),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isPageMode = _user.readerMode == 1;
    final isHorizontalScroll = !isPageMode && _user.readerScrollDirection != 2;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isDraggingBrightness ? 0 : 1.0,
      child: Material(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.readerSettingsTitle,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xl),
                // 阅读模式
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.view_day),
                        label: Text(l10n.readerScrollMode),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.auto_stories),
                        label: Text(l10n.readerPageMode),
                      ),
                    ],
                    selected: {_user.readerMode},
                    onSelectionChanged: (v) {
                      _user.setReaderMode(v.first);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(l10n.readerLeftToRight),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(l10n.readerRightToLeft),
                      ),
                      ButtonSegment(
                        value: 2,
                        icon: const Icon(Icons.arrow_downward),
                        label: Text(l10n.readerTopToBottom),
                      ),
                    ],
                    selected: {_user.readerScrollDirection},
                    onSelectionChanged: (v) {
                      _user.setReaderScrollDirection(v.first);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // 滚动设置
                if (!isPageMode) ...[
                  _buildSectionHeader(l10n.readerScrollSection, cs, tt),
                  Row(
                    children: [
                      Text(l10n.readerImageGap, style: tt.bodyMedium),
                      const Spacer(),
                      Text(
                        '${_scrollDirectionLabels[_user.readerScrollDirection]} · ${_user.readerImageGap.round()} px',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _user.readerImageGap,
                    max: 20,
                    divisions: 20,
                    onChanged: (v) {
                      _user.setReaderImageGap(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                  if (isHorizontalScroll) ...[
                    Row(
                      children: [
                        Text(
                          l10n.readerHorizontalImageScale,
                          style: tt.bodyMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${(_user.readerHorizontalImageScale * 100).round()}%',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _user.readerHorizontalImageScale,
                      min: 0.7,
                      divisions: 6,
                      label:
                          '${(_user.readerHorizontalImageScale * 100).round()}%',
                      onChanged: (v) {
                        _user.setReaderHorizontalImageScale(v);
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                    Text(
                      l10n.readerHorizontalImageScaleDesc,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.readerContinuousReading),
                    subtitle: Text(l10n.readerContinuousReadingDesc),
                    value: _user.readerContinuousReading,
                    onChanged: (v) {
                      _user.setReaderContinuousReading(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.readerAutoScroll),
                    subtitle: Text(l10n.readerAutoScrollDesc),
                    value: _user.readerAutoScrollEnabled,
                    onChanged: (v) {
                      _user.setReaderAutoScrollEnabled(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                  if (_user.readerAutoScrollEnabled) ...[
                    Row(
                      children: [
                        const Icon(Icons.unfold_more, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          l10n.readerAutoScrollDistance,
                          style: tt.bodyMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${(_user.readerAutoScrollDistance * 100).round()}%',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _user.readerAutoScrollDistance,
                      min: 0.2,
                      divisions: 16,
                      label:
                          '${(_user.readerAutoScrollDistance * 100).round()}%',
                      onChanged: (v) {
                        _user.setReaderAutoScrollDistance(v);
                        setState(() {});
                      },
                    ),
                    Row(
                      children: [
                        const Icon(Icons.pause_circle_outline, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text(l10n.readerAutoScrollPause, style: tt.bodyMedium),
                        const Spacer(),
                        Text(
                          l10n.readerSeconds(
                            _user.readerAutoScrollPause.toStringAsFixed(1),
                          ),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _user.readerAutoScrollPause,
                      min: 0.5,
                      max: 8,
                      divisions: 15,
                      label: l10n.readerSeconds(
                        _user.readerAutoScrollPause.toStringAsFixed(1),
                      ),
                      onChanged: (v) {
                        _user.setReaderAutoScrollPause(v);
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.readerAutoResume),
                      subtitle: Text(l10n.readerAutoResumeDesc),
                      value: _user.readerAutoScrollResume,
                      onChanged: (v) {
                        _user.setReaderAutoScrollResume(v);
                        setState(() {});
                      },
                    ),
                    if (_user.readerAutoScrollResume) ...[
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 18),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            l10n.readerAutoResumeDelay,
                            style: tt.bodyMedium,
                          ),
                          const Spacer(),
                          Text(
                            l10n.readerSeconds(
                              _user.readerAutoScrollResumeDelay.toStringAsFixed(
                                1,
                              ),
                            ),
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _user.readerAutoScrollResumeDelay.clamp(
                          1.0,
                          5.0,
                        ),
                        min: 1,
                        max: 5,
                        divisions: 8,
                        label: l10n.readerSeconds(
                          _user.readerAutoScrollResumeDelay.toStringAsFixed(1),
                        ),
                        onChanged: (v) {
                          _user.setReaderAutoScrollResumeDelay(v);
                          setState(() {});
                        },
                      ),
                    ],
                  ],
                ],
                // 翻页设置
                if (isPageMode) ...[
                  _buildSectionHeader(l10n.readerPageSection, cs, tt),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.readerVolumeKeyPageTurn),
                    subtitle: Text(l10n.readerVolumeKeyPageTurnDesc),
                    value: _user.readerVolumeKey,
                    onChanged: (v) {
                      _user.setReaderVolumeKey(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.readerInstantPageTurn),
                    value: _user.readerInstantPageTurn,
                    onChanged: (v) {
                      _user.setReaderInstantPageTurn(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ],
                // 显示
                _buildSectionHeader(l10n.readerDisplaySection, cs, tt),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.readerStatusOverlay),
                  value: _user.reader.statusOverlay,
                  onChanged: (v) {
                    _user.reader.setStatusOverlay(v);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
                if (_user.reader.statusOverlay) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: Row(
                      children: [
                        Text(l10n.readerStatusOverlayPosition),
                        const Spacer(),
                        Text(
                          switch (_user.reader.statusOverlayPosition) {
                            0 => l10n.readerStatusOverlayTopLeft,
                            1 => l10n.readerStatusOverlayTopCenter,
                            2 => l10n.readerStatusOverlayTopRight,
                            3 => l10n.readerStatusOverlayBottomRight,
                            4 => l10n.readerStatusOverlayBottomCenter,
                            5 => l10n.readerStatusOverlayBottomLeft,
                            _ => l10n.readerStatusOverlayTopRight,
                          },
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, icon: Icon(Icons.north_west)),
                          ButtonSegment(value: 1, icon: Icon(Icons.north)),
                          ButtonSegment(value: 2, icon: Icon(Icons.north_east)),
                          ButtonSegment(value: 3, icon: Icon(Icons.south_east)),
                          ButtonSegment(value: 4, icon: Icon(Icons.south)),
                          ButtonSegment(value: 5, icon: Icon(Icons.south_west)),
                        ],
                        selected: {_user.reader.statusOverlayPosition},
                        onSelectionChanged: (v) {
                          _user.reader.setStatusOverlayPosition(v.first);
                          setState(() {});
                          widget.onChanged();
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: Row(
                      children: [
                        Text(l10n.readerStatusOverlayOpacity),
                        const Spacer(),
                        Text(
                          '${(_user.reader.statusOverlayOpacity * 100).round()}%',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: Slider(
                      value: _user.reader.statusOverlayOpacity,
                      divisions: 10,
                      label:
                          '${(_user.reader.statusOverlayOpacity * 100).round()}%',
                      onChanged: (v) {
                        _user.reader.setStatusOverlayOpacity(v);
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorderItem: _onStatusSegmentReorder,
                      children: [
                        for (var i = 0; i < _statusSegments.length; i++)
                          _buildStatusSegmentRow(l10n, _statusSegments[i], i),
                      ],
                    ),
                  ),
                ],
                if (isDark) ...[
                  Row(
                    children: [
                      const Icon(Icons.brightness_low, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Text(l10n.readerDimming, style: tt.bodyMedium),
                      const Spacer(),
                      Text(
                        '${(_user.readerDimming * 100).round()}%',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _user.readerDimming,
                    max: 0.7,
                    divisions: 14,
                    onChangeStart: (_) =>
                        setState(() => _isDraggingBrightness = true),
                    onChangeEnd: (_) =>
                        setState(() => _isDraggingBrightness = false),
                    onChanged: (v) {
                      _user.setReaderDimming(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ],
                // 图片加载
                _buildSectionHeader(l10n.readerImageLoadingSection, cs, tt),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Text(l10n.readerTimeout, style: tt.bodyMedium),
                    const Spacer(),
                    Text(
                      '${_user.imageLoadTimeout} s',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Slider(
                  value: _user.imageLoadTimeout.toDouble(),
                  min: 3,
                  max: 60,
                  divisions: 57,
                  label: '${_user.imageLoadTimeout} s',
                  onChanged: (v) {
                    _user.setImageLoadTimeout(v.round());
                    setState(() {});
                    widget.onChanged();
                  },
                ),
                Text(
                  l10n.readerTimeoutDesc,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Builder(
                  builder: (_) {
                    final avg = _stats.averageMs;
                    final count = _stats.sampleCount;
                    if (avg == null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l10n.readerNoLoadStats,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.readerRecentLoadStats(
                          count,
                          (avg / 1000).toStringAsFixed(1),
                        ),
                        style: tt.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(Icons.refresh, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Text(l10n.readerRetryCount, style: tt.bodyMedium),
                    const Spacer(),
                    Text(
                      _user.imageRetryCount == 0
                          ? l10n.offButton
                          : l10n.readerTimes(_user.imageRetryCount),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Slider(
                  value: _user.imageRetryCount.toDouble(),
                  max: 5,
                  divisions: 5,
                  label: _user.imageRetryCount == 0
                      ? l10n.offButton
                      : l10n.readerTimes(_user.imageRetryCount),
                  onChanged: (v) {
                    _user.setImageRetryCount(v.round());
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
