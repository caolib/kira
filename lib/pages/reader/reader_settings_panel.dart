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
  static const _scrollDirectionLabels = ['左到右', '右到左', '上到下'];
  bool _isDraggingBrightness = false;

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isPageMode = _user.readerMode == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isDraggingBrightness ? 0 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
                const SizedBox(height: 16),
                Text(
                  '阅读设置',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                // 阅读模式
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.view_day),
                        label: Text('滚动'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.auto_stories),
                        label: Text('翻页'),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.arrow_forward),
                        label: Text('左到右'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.arrow_back),
                        label: Text('右到左'),
                      ),
                      ButtonSegment(
                        value: 2,
                        icon: Icon(Icons.arrow_downward),
                        label: Text('上到下'),
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
                // 滚动设置
                if (!isPageMode) ...[
                  _buildSectionHeader('滚动', cs, tt),
                  Row(
                    children: [
                      Text('图片间距', style: tt.bodyMedium),
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
                    min: 0,
                    max: 20,
                    divisions: 20,
                    onChanged: (v) {
                      _user.setReaderImageGap(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动滚动'),
                    subtitle: const Text('开启后在导航栏显示自动滚动按钮'),
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
                        const Icon(Icons.pause_circle_outline, size: 18),
                        const SizedBox(width: 8),
                        Text('停顿时长', style: tt.bodyMedium),
                        const Spacer(),
                        Text(
                          '${_user.readerAutoScrollPause.toStringAsFixed(1)} 秒',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _user.readerAutoScrollPause,
                      min: 1,
                      max: 8,
                      divisions: 14,
                      label:
                          '${_user.readerAutoScrollPause.toStringAsFixed(1)} 秒',
                      onChanged: (v) {
                        _user.setReaderAutoScrollPause(v);
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动恢复'),
                      subtitle: const Text('一段时间无动作后自动恢复滚动'),
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
                          const SizedBox(width: 8),
                          Text('恢复延迟', style: tt.bodyMedium),
                          const Spacer(),
                          Text(
                            '${_user.readerAutoScrollResumeDelay.toStringAsFixed(1)} 秒',
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
                        label:
                            '${_user.readerAutoScrollResumeDelay.toStringAsFixed(1)} 秒',
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
                  _buildSectionHeader('翻页', cs, tt),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('音量键翻页'),
                    subtitle: const Text('音量+上一页，音量-下一页'),
                    value: _user.readerVolumeKey,
                    onChanged: (v) {
                      _user.setReaderVolumeKey(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('无动画翻页'),
                    value: _user.readerInstantPageTurn,
                    onChanged: (v) {
                      _user.setReaderInstantPageTurn(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ],
                // 显示
                if (isDark) ...[
                  _buildSectionHeader('显示', cs, tt),
                  Row(
                    children: [
                      const Icon(Icons.brightness_low, size: 18),
                      const SizedBox(width: 8),
                      Text('降低亮度', style: tt.bodyMedium),
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
                    min: 0,
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
                _buildSectionHeader('图片加载', cs, tt),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('超时时间', style: tt.bodyMedium),
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
                  '设置太小可能导致图片加载失败，太大可能导致长时间转圈',
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
                          '暂无加载记录（阅读图片后此处显示平均耗时供参考）',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '最近10分钟内加载了 $count 张，平均 ${(avg / 1000).toStringAsFixed(1)} s',
                        style: tt.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.refresh, size: 18),
                    const SizedBox(width: 8),
                    Text('重试次数', style: tt.bodyMedium),
                    const Spacer(),
                    Text(
                      _user.imageRetryCount == 0
                          ? '关闭'
                          : '${_user.imageRetryCount} 次',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Slider(
                  value: _user.imageRetryCount.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: _user.imageRetryCount == 0
                      ? '关闭'
                      : '${_user.imageRetryCount} 次',
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
