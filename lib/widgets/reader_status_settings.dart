import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/reader_settings.dart';
import '../models/reader_status_prefs.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'collapsible_content.dart';
import 'collapsible_switch_tile.dart';
import 'settings_section.dart';

/// 阅读器状态组件设置区：开关、六位摆放、不透明度、前景/背景色与段位
/// 顺序。通过 [prefs] 读写配置（漫画侧全局 [ReaderSettings]、轻小说侧
/// 独立 store），修改即持久化并通过 store 通知所有监听者；宿主只需在
/// [onChanged] 里刷新自己的其余 UI。
class ReaderStatusSettingsSection extends StatefulWidget {
  const ReaderStatusSettingsSection({
    super.key,
    required this.onChanged,
    this.prefs,
  });

  /// 配置来源；null 时用漫画侧全局 [ReaderSettings]。
  final ReaderStatusPrefs? prefs;

  /// 任意设置变化后的回调。
  final VoidCallback onChanged;

  @override
  State<ReaderStatusSettingsSection> createState() =>
      _ReaderStatusSettingsSectionState();
}

class _ReaderStatusSettingsSectionState
    extends State<ReaderStatusSettingsSection> {
  ReaderStatusPrefs get _reader => widget.prefs ?? ReaderSettings();
  bool _expanded = false;

  void _changed() {
    if (mounted) setState(() {});
    widget.onChanged();
  }

  /// 当前状态显示段位顺序（由持久化配置决定）。
  List<String> get _segments => _reader.statusOverlayOrder;

  /// 拖动调整状态显示段位的显示顺序。
  void _onSegmentReorder(int oldIndex, int newIndex) {
    setState(() {
      final order = [..._reader.statusOverlayOrder];
      final item = order.removeAt(oldIndex);
      order.insert(newIndex, item);
      _reader.setStatusOverlayOrder(order);
    });
    widget.onChanged();
  }

  Widget _buildSegmentRow(AppLocalizations l10n, String id, int index) {
    final (title, value, onChanged) = switch (id) {
      'time' => (
        l10n.readerStatusTime,
        _reader.statusOverlayTime,
        _reader.setStatusOverlayTime,
      ),
      'network' => (
        l10n.readerStatusNetwork,
        _reader.statusOverlayNetwork,
        _reader.setStatusOverlayNetwork,
      ),
      'battery' => (
        l10n.readerStatusBattery,
        _reader.statusOverlayBattery,
        _reader.setStatusOverlayBattery,
      ),
      'chapter' => (
        l10n.readerStatusChapter,
        _reader.statusOverlayChapter,
        _reader.setStatusOverlayChapter,
      ),
      'page' => (
        // 小说侧该段位是百分比进度而非页码，换用「进度」文案。
        _reader.statusOverlaySegmentIds.contains('chapter')
            ? l10n.readerStatusProgress
            : l10n.readerStatusPage,
        _reader.statusOverlayPage,
        _reader.setStatusOverlayPage,
      ),
      'fps' => (
        l10n.readerStatusFps,
        _reader.statusOverlayFps,
        _reader.setStatusOverlayFps,
      ),
      _ => (l10n.readerStatusTime, false, _reader.setStatusOverlayTime),
    };
    return Row(
      key: ValueKey(id),
      children: [
        ReorderableDragStartListener(
          index: index,
          child: const SizedBox.square(
            dimension: 48,
            child: Icon(Icons.drag_handle, size: AppIconSize.md),
          ),
        ),
        Expanded(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CollapsibleSwitchTile(
            title: l10n.readerStatusOverlay,
            switchKey: const ValueKey('reader-status-overlay-switch'),
            expandKey: const ValueKey('reader-status-details-toggle'),
            value: _reader.statusOverlay,
            expanded: _expanded,
            onChanged: (v) {
              _reader.setStatusOverlay(v);
              _changed();
            },
            onToggleExpanded: () => setState(() => _expanded = !_expanded),
          ),
          CollapsibleContent(
            expanded: _expanded,
            child: _buildDetails(context, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final positionLabels = [
      l10n.readerStatusOverlayTopLeft,
      l10n.readerStatusOverlayTopCenter,
      l10n.readerStatusOverlayTopRight,
      l10n.readerStatusOverlayBottomRight,
      l10n.readerStatusOverlayBottomCenter,
      l10n.readerStatusOverlayBottomLeft,
    ];
    const positionIcons = [
      Icons.north_west,
      Icons.north,
      Icons.north_east,
      Icons.south_east,
      Icons.south,
      Icons.south_west,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.readerStatusOverlayPosition)),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  positionLabels[_reader.statusOverlayPosition],
                  style: metaStyle,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: constraints.maxWidth.clamp(288, double.infinity),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 0; i < positionIcons.length; i++)
                      ButtonSegment(
                        value: i,
                        icon: Icon(positionIcons[i]),
                        tooltip: positionLabels[i],
                      ),
                  ],
                  selected: {_reader.statusOverlayPosition},
                  onSelectionChanged: (v) {
                    _reader.setStatusOverlayPosition(v.first);
                    _changed();
                  },
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: Text(l10n.readerStatusOverlayOpacity)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(_reader.statusOverlayOpacity * 100).round()}%',
                style: metaStyle,
              ),
            ],
          ),
          Slider(
            value: _reader.statusOverlayOpacity,
            divisions: 10,
            label: '${(_reader.statusOverlayOpacity * 100).round()}%',
            onChanged: (v) {
              _reader.setStatusOverlayOpacity(v);
              setState(() {});
              widget.onChanged();
            },
          ),
          if (_reader.supportsStatusOverlayFollowTheme)
            SwitchListTile.adaptive(
              key: const ValueKey('reader-status-follow-theme'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.readerStatusOverlayFollowTheme),
              value: _reader.statusOverlayFollowTheme,
              onChanged: (v) {
                _reader.setStatusOverlayFollowTheme(v);
                _changed();
              },
            ),
          if (!_reader.statusOverlayFollowTheme) ...[
            _buildColorTile(
              context,
              label: l10n.readerStatusOverlayForeground,
              value: _reader.statusOverlayForeground,
              onReset: () => _reader.setStatusOverlayForeground(null),
              onChanged: (color) =>
                  _reader.setStatusOverlayForeground(color.toARGB32()),
            ),
            _buildColorTile(
              context,
              label: l10n.readerStatusOverlayBackground,
              value: _reader.statusOverlayBackground,
              onReset: () => _reader.setStatusOverlayBackground(null),
              onChanged: (color) =>
                  _reader.setStatusOverlayBackground(color.toARGB32()),
            ),
          ],
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // 新回调给出删除旧条目后的最终索引，可直接插入（含末尾）。
            onReorderItem: _onSegmentReorder,
            children: [
              for (var i = 0; i < _segments.length; i++)
                _buildSegmentRow(l10n, _segments[i], i),
            ],
          ),
        ],
      ),
    );
  }

  /// 颜色行：色块展示当前值，「默认」可一键清除手动色（null），
  /// 点色块弹出取色器（与小说自定义主题同一取色器）。
  Widget _buildColorTile(
    BuildContext context, {
    required String label,
    required int? value,
    required VoidCallback onReset,
    required ValueChanged<Color> onChanged,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(child: Text(label)),
        if (value != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: TextButton(
              onPressed: () {
                onReset();
                _changed();
              },
              child: Text(l10n.readerStatusOverlayDefaultColor),
            ),
          ),
        GestureDetector(
          onTap: () => _pickColor(context, value, onChanged),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: value == null ? null : Color(value),
              gradient: value == null
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.grey, Colors.white70],
                    )
                  : null,
              borderRadius: AppRadius.smR,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickColor(
    BuildContext context,
    int? initial,
    ValueChanged<Color> onChanged,
  ) async {
    var selected = initial == null ? Colors.white : Color(initial);
    final l10n = AppLocalizations.of(context)!;
    final didFinish = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerStatusOverlayColorPicker),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: selected,
            onColorChanged: (color) => selected = color,
            pickersEnabled: const {
              ColorPickerType.primary: false,
              ColorPickerType.accent: false,
              ColorPickerType.wheel: true,
            },
            enableShadesSelection: false,
            showColorCode: true,
            colorCodeHasColor: true,
            wheelDiameter: 220,
            wheelWidth: AppSpacing.xl,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    if (didFinish == true) {
      onChanged(selected);
      _changed();
    }
  }
}
