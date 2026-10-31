import 'dart:async';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

import '../../api/hitokoto_api.dart';
import '../../l10n/app_localizations.dart';
import '../../models/novel_dialogue_style.dart';
import '../../models/novel_reader_settings.dart';
import '../../models/novel_reader_status_settings.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_status_colors.dart';
import '../../theme/novel_reader_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/font_manager.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/collapsible_content.dart';
import '../../widgets/collapsible_switch_tile.dart';
import '../../widgets/reader_settings_fold.dart';
import '../../widgets/reader_status_settings.dart';
import '../../widgets/select_tile.dart';
import '../../widgets/settings_section.dart';
import 'novel_reader_dialogue.dart';
import 'novel_reader_font.dart';

part 'novel_reader_theme_settings_sheet.dart';

/// 小说阅读设置：排版、命名配色方案（内置 + 多个自定义）与常亮。
/// 阅读背景固定跟随系统亮暗，浅色/深色分别绑定方案；
/// 状态组件配置独立于漫画阅读器（键前缀 `novel_status_overlay*`）。
class NovelReaderSettingsSheet extends StatefulWidget {
  const NovelReaderSettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.systemBrightness,
    this.fontFamily,
    this.dragPreview,
  });

  final NovelReaderSettings settings;
  final ValueChanged<NovelReaderSettings> onChanged;

  /// 宿主已加载的正文有效字体族；null 跟随应用字体。
  final String? fontFamily;

  /// 当前系统亮暗，用于实时预览当前生效配色。
  final Brightness systemBrightness;

  /// 拖动专注遮罩参数时置 true：宿主据此让整个面板淡出，
  /// 读者可直接看到正文上的遮罩效果（与漫画阅读器的亮度调整一致）。
  final ValueNotifier<bool>? dragPreview;

  @override
  State<NovelReaderSettingsSheet> createState() =>
      _NovelReaderSettingsSheetState();
}

class _NovelReaderSettingsSheetState extends State<NovelReaderSettingsSheet> {
  late NovelReaderSettings _settings = widget.settings;
  bool _focusExpanded = false;
  List<String> _fonts = const [];
  bool _loadingFonts = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFonts());
  }

  /// 只列出本地已有字体；不在这里下载或导入。
  Future<void> _loadFonts() async {
    try {
      final fonts = await FontManager().listDownloadedFonts();
      if (!mounted) return;
      setState(
        () => _fonts =
            fonts
                .where(
                  (name) =>
                      name.isNotEmpty && name != FontManager.defaultFontId,
                )
                .toSet()
                .toList()
              ..sort(),
      );
    } catch (error, stack) {
      unawaited(AppLogger.instance.recordWarning(error, stackTrace: stack));
    } finally {
      if (mounted) setState(() => _loadingFonts = false);
    }
  }

  @override
  void didUpdateWidget(covariant NovelReaderSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) _settings = widget.settings;
  }

  void _change(NovelReaderSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  void _setDragPreview(bool dragging) => widget.dragPreview?.value = dragging;

  Future<void> _openThemeSettings() async {
    var draft = _settings;
    final initial = draft;
    await showAppSheet<void>(
      context,
      heightFactor: 1,
      maxHeightFactor: 1,
      child: _NovelThemeSettingsSheet(
        settings: initial,
        fontFamily: widget.fontFamily,
        systemBrightness: widget.systemBrightness,
        topInset:
            View.of(context).viewPadding.top /
            View.of(context).devicePixelRatio,
        onDraftChanged: (settings) => draft = settings,
      ),
    );
    // 返回、点屏障和拖拽收起共享同一提交点，正文仅重排一次。
    if (mounted && draft != initial) _change(draft);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.novelReaderSettings,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xl),
          SegmentedButton<NovelReaderMode>(
            showSelectedIcon: false,
            key: const ValueKey('novel-reader-mode'),
            segments: [
              ButtonSegment(
                value: NovelReaderMode.scroll,
                icon: const Icon(Icons.view_day),
                label: Text(l10n.readerScrollMode),
              ),
              ButtonSegment(
                value: NovelReaderMode.paged,
                icon: const Icon(Icons.auto_stories),
                label: Text(l10n.readerPageMode),
              ),
            ],
            selected: {_settings.mode},
            onSelectionChanged: (selection) =>
                _change(_settings.copyWith(mode: selection.first)),
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsSection(
            child: ListTile(
              key: const ValueKey('novel-theme-settings-entry'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: Text(l10n.novelReaderTheme),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openThemeSettings,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsSection(
            key: const ValueKey('novel-typography-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    key: const ValueKey('novel-font-family'),
                    children: [
                      Expanded(
                        child: Text(
                          l10n.novelReaderFontFamily,
                          style: tt.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SelectTile<String>(
                            value: _settings.fontFamily,
                            items: [
                              SelectItem('', l10n.novelReaderFontFollowApp),
                              SelectItem(
                                FontManager.defaultFontId,
                                l10n.appearanceSystemDefault,
                              ),
                              for (final font in _fonts) SelectItem(font, font),
                              if (_settings.fontFamily.isNotEmpty &&
                                  _settings.fontFamily !=
                                      FontManager.defaultFontId &&
                                  !_fonts.contains(_settings.fontFamily))
                                SelectItem(
                                  _settings.fontFamily,
                                  _loadingFonts
                                      ? _settings.fontFamily
                                      : l10n.novelReaderFontUnavailable(
                                          _settings.fontFamily,
                                        ),
                                ),
                            ],
                            onChanged: (value) =>
                                _change(_settings.copyWith(fontFamily: value)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _slider(
                  key: const ValueKey('novel-font-size'),
                  label: l10n.novelReaderFontSize,
                  value: _settings.fontSize,
                  min: NovelReaderSettings.minFontSize,
                  max: NovelReaderSettings.maxFontSize,
                  divisions:
                      (NovelReaderSettings.maxFontSize -
                              NovelReaderSettings.minFontSize)
                          .round(),
                  onChanged: (value) =>
                      _change(_settings.copyWith(fontSize: value)),
                ),
                _slider(
                  key: const ValueKey('novel-line-height'),
                  label: l10n.novelReaderLineHeight,
                  value: _settings.lineHeight,
                  min: NovelReaderSettings.minLineHeight,
                  max: NovelReaderSettings.maxLineHeight,
                  divisions: 20,
                  onChanged: (value) =>
                      _change(_settings.copyWith(lineHeight: value)),
                ),
                _slider(
                  key: const ValueKey('novel-paragraph-spacing'),
                  label: l10n.novelReaderParagraphSpacing,
                  value: _settings.paragraphSpacing,
                  min: NovelReaderSettings.minParagraphSpacing,
                  max: NovelReaderSettings.maxParagraphSpacing,
                  divisions: 32,
                  onChanged: (value) =>
                      _change(_settings.copyWith(paragraphSpacing: value)),
                ),
                _slider(
                  key: const ValueKey('novel-content-width'),
                  label: l10n.novelReaderContentWidth,
                  value: _settings.contentWidth,
                  min: NovelReaderSettings.minContentWidth,
                  max: NovelReaderSettings.maxContentWidth,
                  divisions: 22,
                  format: (value) => '${value.round()} dp',
                  onChanged: (value) =>
                      _change(_settings.copyWith(contentWidth: value)),
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('novel-ignore-blank-paragraphs'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.novelReaderIgnoreBlankParagraphs),
                  subtitle:
                      _settings.ignoreBlankParagraphs &&
                          _settings.paragraphSpacing < 20
                      ? Text(l10n.novelReaderIgnoreBlankParagraphsDenseHint)
                      : null,
                  value: _settings.ignoreBlankParagraphs,
                  onChanged: (value) =>
                      _change(_settings.copyWith(ignoreBlankParagraphs: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsSection(
            key: const ValueKey('novel-focus-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CollapsibleSwitchTile(
                  title: l10n.novelReaderFocusMode,
                  switchKey: const ValueKey('novel-focus-mode'),
                  expandKey: const ValueKey('novel-focus-details-toggle'),
                  adaptive: true,
                  value: _settings.focusModeEnabled,
                  expanded: _focusExpanded,
                  onChanged: (value) =>
                      _change(_settings.copyWith(focusModeEnabled: value)),
                  onToggleExpanded: () =>
                      setState(() => _focusExpanded = !_focusExpanded),
                ),
                CollapsibleContent(
                  key: const ValueKey('novel-focus-details'),
                  expanded: _focusExpanded,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          key: const ValueKey(
                            'novel-focus-keep-status-visible',
                          ),
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.novelReaderFocusKeepStatusVisible),
                          value: _settings.focusKeepStatusVisible,
                          onChanged: (value) => _change(
                            _settings.copyWith(focusKeepStatusVisible: value),
                          ),
                        ),
                        _slider(
                          key: const ValueKey('novel-focus-top'),
                          label: l10n.novelReaderFocusTopBound,
                          value: _settings.focusTopRatio,
                          min: NovelReaderSettings.minFocusTopRatio,
                          max: NovelReaderSettings.maxFocusTopRatio,
                          divisions: 90,
                          format: _focusPercent,
                          onChangeStart: (_) => _setDragPreview(true),
                          onChangeEnd: (_) => _setDragPreview(false),
                          onChanged: (value) =>
                              _change(_settings.copyWith(focusTopRatio: value)),
                        ),
                        _slider(
                          key: const ValueKey('novel-focus-bottom'),
                          label: l10n.novelReaderFocusBottomBound,
                          value: _settings.focusBottomRatio,
                          min: NovelReaderSettings.minFocusBottomRatio,
                          max: NovelReaderSettings.maxFocusBottomRatio,
                          divisions: 90,
                          format: _focusPercent,
                          onChangeStart: (_) => _setDragPreview(true),
                          onChangeEnd: (_) => _setDragPreview(false),
                          onChanged: (value) => _change(
                            _settings.copyWith(focusBottomRatio: value),
                          ),
                        ),
                        _slider(
                          key: const ValueKey('novel-focus-opacity'),
                          label: l10n.novelReaderFocusOpacity,
                          value: _settings.focusOpacity,
                          min: NovelReaderSettings.minFocusOpacity,
                          max: NovelReaderSettings.maxFocusOpacity,
                          divisions: 80,
                          format: _focusPercent,
                          onChangeStart: (_) => _setDragPreview(true),
                          onChangeEnd: (_) => _setDragPreview(false),
                          onChanged: (value) =>
                              _change(_settings.copyWith(focusOpacity: value)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_settings.mode == NovelReaderMode.paged) ...[
            const SizedBox(height: AppSpacing.sm),
            ReaderSettingsFold(
              key: const ValueKey('novel-page-turn-settings'),
              title: l10n.readerPageSection,
              icon: Icons.auto_stories_outlined,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey('novel-volume-key'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.readerVolumeKeyPageTurn),
                    subtitle: Text(l10n.readerVolumeKeyPageTurnDesc),
                    value: _settings.volumeKey,
                    onChanged: (value) =>
                        _change(_settings.copyWith(volumeKey: value)),
                  ),
                  SwitchListTile.adaptive(
                    key: const ValueKey('novel-realistic-page-turn'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.novelReaderRealisticPageTurn),
                    value: _settings.realisticPageTurn,
                    onChanged: (value) =>
                        _change(_settings.copyWith(realisticPageTurn: value)),
                  ),
                  SwitchListTile.adaptive(
                    key: const ValueKey('novel-instant-page-turn'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.readerInstantPageTurn),
                    value: _settings.instantPageTurn,
                    onChanged: (value) =>
                        _change(_settings.copyWith(instantPageTurn: value)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SettingsSection(
            child: SwitchListTile.adaptive(
              key: const ValueKey('novel-keep-screen-on'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.novelReaderKeepScreenOn),
              value: _settings.keepScreenOn,
              onChanged: (value) =>
                  _change(_settings.copyWith(keepScreenOn: value)),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ReaderStatusSettingsSection(
            prefs: NovelReaderStatusSettings(),
            onChanged: () => widget.onChanged(_settings),
          ),
        ],
      ),
    );
  }

  /// 专注模式比例按百分比展示（0.25 → 25%）。
  static String _focusPercent(double value) => '${(value * 100).round()}%';

  Widget _slider({
    required Key key,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeStart,
    ValueChanged<double>? onChangeEnd,
    String Function(double value)? format,
  }) {
    final display = format != null
        ? format(value)
        : value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label · $display'),
        Slider(
          key: key,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChangeStart: onChangeStart,
          onChangeEnd: onChangeEnd,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// 自定义方案编辑对话框：名称 + 背景/文字色 + 实时预览。
/// 新建与编辑共用，确认后返回 [_ThemeEditResult]。
class _ThemeEditDialog extends StatefulWidget {
  const _ThemeEditDialog({
    required this.title,
    required this.initialName,
    required this.initialBackground,
    required this.initialText,
  });

  final String title;
  final String initialName;
  final Color initialBackground;
  final Color initialText;

  @override
  State<_ThemeEditDialog> createState() => _ThemeEditDialogState();
}

class _ThemeEditDialogState extends State<_ThemeEditDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late Color _background = widget.initialBackground;
  late Color _text = widget.initialText;

  /// 一言（漫画类）预览文本；请求成功前保持本地文案。
  HitokotoSentence? _previewSentence;

  @override
  void initState() {
    super.initState();
    _loadPreviewSentence();
  }

  Future<void> _loadPreviewSentence() async {
    final sentence = await HitokotoApi().fetchSentence();
    if (!mounted || sentence == null) return;
    setState(() => _previewSentence = sentence);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sentence = _previewSentence;
    final previewText = sentence == null
        ? l10n.novelReaderPreviewText
        : sentence.from.isEmpty
        ? sentence.text
        : '${sentence.text} ——${sentence.from}';
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('novel-theme-name-field'),
                controller: _nameController,
                autofocus: widget.initialName.isEmpty,
                maxLength: 24,
                decoration: InputDecoration(
                  labelText: l10n.novelReaderThemeNameTitle,
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              _ColorField(
                key: const ValueKey('novel-theme-edit-background'),
                label: l10n.novelReaderBackgroundColor,
                color: _background,
                onChanged: (color) => setState(() => _background = color),
              ),
              _ColorField(
                key: const ValueKey('novel-theme-edit-text'),
                label: l10n.novelReaderTextColor,
                color: _text,
                onChanged: (color) => setState(() => _text = color),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                key: const ValueKey('novel-theme-edit-preview'),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: _background,
                  borderRadius: AppRadius.mdR,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Text(
                  previewText,
                  style: tt.bodyLarge?.copyWith(color: _text),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          key: const ValueKey('novel-theme-edit-confirm'),
          onPressed: _nameController.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _ThemeEditResult(
                    name: _nameController.text.trim(),
                    background: _background,
                    text: _text,
                  ),
                ),
          child: Text(l10n.confirmButton),
        ),
      ],
    );
  }
}

class _ThemeEditResult {
  const _ThemeEditResult({
    required this.name,
    required this.background,
    required this.text,
  });

  final String name;
  final Color background;
  final Color text;
}

class _ColorField extends StatelessWidget {
  const _ColorField({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  Future<void> _pick(BuildContext context) async {
    var selected = color;
    final didSelect =
        await ColorPicker(
          color: color,
          onColorChanged: (color) => selected = color,
          pickersEnabled: const <ColorPickerType, bool>{
            ColorPickerType.both: false,
            ColorPickerType.primary: false,
            ColorPickerType.accent: false,
            ColorPickerType.bw: false,
            ColorPickerType.custom: false,
            ColorPickerType.wheel: true,
          },
          enableShadesSelection: false,
          showColorCode: true,
          colorCodeHasColor: true,
          showEditIconButton: true,
          wheelDiameter: (MediaQuery.sizeOf(context).width - AppSpacing.lg * 4)
              .clamp(120.0, 220.0)
              .toDouble(),
          wheelWidth: AppSpacing.xl,
          wheelSquareBorderRadius: AppRadius.md,
          wheelHasBorder: true,
          heading: Text(label),
          borderRadius: AppRadius.md,
        ).showPickerDialog(
          context,
          constraints: const BoxConstraints(maxWidth: 460),
          insetPadding: const EdgeInsets.all(AppSpacing.lg),
        );
    if (didSelect) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.smR,
          border: Border.all(color: cs.outlineVariant),
        ),
      ),
      title: Text(label, style: tt.bodyMedium),
      subtitle: Text(
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      ),
      onTap: () => _pick(context),
    );
  }
}
