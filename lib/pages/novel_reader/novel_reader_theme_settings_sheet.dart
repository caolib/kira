part of 'novel_reader_settings_sheet.dart';

class _NovelThemeSettingsSheet extends StatefulWidget {
  const _NovelThemeSettingsSheet({
    required this.settings,
    required this.systemBrightness,
    required this.topInset,
    required this.onDraftChanged,
    this.fontFamily,
  });

  final NovelReaderSettings settings;
  final Brightness systemBrightness;
  final double topInset;
  final ValueChanged<NovelReaderSettings> onDraftChanged;

  /// 宿主已加载的正文有效字体族；null 跟随应用字体。
  final String? fontFamily;

  @override
  State<_NovelThemeSettingsSheet> createState() =>
      _NovelThemeSettingsSheetState();
}

class _NovelThemeSettingsSheetState extends State<_NovelThemeSettingsSheet> {
  late NovelReaderSettings _settings = widget.settings;
  late bool _dark = widget.systemBrightness == Brightness.dark;

  void _change(NovelReaderSettings settings) {
    setState(() => _settings = settings);
    widget.onDraftChanged(settings);
  }

  String _themeName(String id) {
    final l10n = AppLocalizations.of(context)!;
    for (final theme in _settings.customThemes) {
      if (theme.id == id) return theme.name;
    }
    return switch (id) {
      'paper' => l10n.novelReaderThemePaper,
      'dark' => l10n.novelReaderThemeDark,
      'white' => l10n.novelReaderThemeWhite,
      'green' => l10n.novelReaderThemeGreen,
      'gray' => l10n.novelReaderThemeGray,
      _ => l10n.novelReaderThemeWhite,
    };
  }

  List<String> get _allThemes => [
    'paper',
    'dark',
    'white',
    'green',
    'gray',
    for (final theme in _settings.customThemes) theme.id,
  ];

  void _selectTheme(bool dark, String id) {
    _change(
      dark
          ? _settings.copyWith(darkThemeId: id)
          : _settings.copyWith(lightThemeId: id),
    );
  }

  Future<void> _editCustomTheme(NovelReaderCustomTheme theme) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<_ThemeEditResult>(
      context: context,
      builder: (context) => _ThemeEditDialog(
        title: l10n.novelReaderThemeEditTitle(theme.name),
        initialName: theme.name,
        initialBackground: Color(theme.backgroundColor),
        initialText: Color(theme.textColor),
      ),
    );
    if (!mounted || result == null) return;
    _change(
      _settings.upsertCustomTheme(
        theme.copyWith(
          name: result.name,
          backgroundColor: result.background.toARGB32(),
          textColor: result.text.toARGB32(),
        ),
      ),
    );
  }

  Future<void> _addCustomTheme() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<_ThemeEditResult>(
      context: context,
      builder: (context) => _ThemeEditDialog(
        title: l10n.novelReaderThemeAdd,
        initialName: '',
        initialBackground: const Color(
          NovelReaderSettings.defaultCustomBackgroundColor,
        ),
        initialText: const Color(NovelReaderSettings.defaultCustomTextColor),
      ),
    );
    if (!mounted || result == null) return;
    _change(
      _settings.upsertCustomTheme(
        NovelReaderCustomTheme(
          id: _settings.newCustomThemeId(),
          name: result.name,
          backgroundColor: result.background.toARGB32(),
          textColor: result.text.toARGB32(),
        ),
      ),
    );
  }

  Future<void> _removeCustomTheme(NovelReaderCustomTheme theme) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.novelReaderThemeDeleteTitle),
        content: Text(l10n.novelReaderThemeDeleteContent(theme.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _change(_settings.removeCustomTheme(theme.id));
  }

  void _changeDialogue(NovelDialogueStyle style) => _change(
    _dark
        ? _settings.copyWith(darkDialogueStyle: style)
        : _settings.copyWith(lightDialogueStyle: style),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;
    final palette = NovelReaderPalette.resolve(
      _settings,
      _dark ? Brightness.dark : Brightness.light,
    );
    final dialogue = resolveNovelDialoguePresentation(
      _settings,
      dark: _dark,
      foreground: palette.foreground,
      background: palette.background,
    );
    final style = _settings.dialogueStyleFor(dark: _dark);
    final lowContrast =
        dialogue != null &&
        _contrastRatio(
              dialogue.foreground,
              dialogue.background == null
                  ? palette.background
                  : Color.alphaBlend(dialogue.background!, palette.background),
            ) <
            4.5;
    final baseStyle = novelContentTextStyle(
      (tt.bodyLarge ?? const TextStyle()).copyWith(
        color: palette.foreground,
        fontSize: _settings.fontSize,
        height: _settings.lineHeight,
      ),
      widget.fontFamily,
    );
    return Padding(
      // ModalBottomSheet 会移除顶 padding，使用弹层外采集的物理安全区。
      padding: EdgeInsets.only(top: widget.topInset),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          key: const ValueKey('novel-theme-settings-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('novel-theme-settings-back'),
                  tooltip: l10n.novelReaderBack,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.novelReaderTheme,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              key: const ValueKey('novel-settings-preview'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: AppRadius.lgR,
                border: Border.all(color: cs.outlineVariant),
              ),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              // 固定短样本；大字号保留缩放并在卡片内滚动。
              child: SingleChildScrollView(
                key: const ValueKey('novel-theme-preview-scroll'),
                child: NovelDialogueText.preview(
                  key: const ValueKey('novel-settings-preview-text'),
                  text: l10n.novelReaderDialoguePreviewText,
                  baseStyle: baseStyle,
                  dialogue: dialogue,
                  paragraphSpacing: _settings.paragraphSpacing,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('novel-theme-settings-scroll'),
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      key: const ValueKey('novel-theme-edit-mode'),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(l10n.appearanceLightMode),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(l10n.appearanceDarkMode),
                        ),
                      ],
                      selected: {_dark},
                      onSelectionChanged: (selection) =>
                          setState(() => _dark = selection.first),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _modeTile(
                      key: ValueKey(
                        _dark ? 'novel-dark-theme' : 'novel-light-theme',
                      ),
                      label: l10n.novelReaderColorScheme,
                      value: _dark
                          ? _settings.darkThemeId
                          : _settings.lightThemeId,
                      dark: _dark,
                      onChanged: (id) => _selectTheme(_dark, id),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SwitchListTile.adaptive(
                      key: const ValueKey('novel-dialogue-enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.novelReaderDialogueStyle),
                      value: _settings.dialogueEnabled,
                      onChanged: (value) =>
                          _change(_settings.copyWith(dialogueEnabled: value)),
                    ),
                    if (_settings.dialogueEnabled) ...[
                      _selectRow<NovelDialogueColorMode>(
                        key: const ValueKey('novel-dialogue-color-mode'),
                        label: l10n.novelReaderTextColor,
                        value: style.colorMode,
                        items: [
                          SelectItem(
                            NovelDialogueColorMode.automatic,
                            l10n.novelReaderDialogueAutomatic,
                          ),
                          SelectItem(
                            NovelDialogueColorMode.body,
                            l10n.novelReaderDialogueFollowBody,
                          ),
                          SelectItem(
                            NovelDialogueColorMode.custom,
                            l10n.novelReaderDialogueCustom,
                          ),
                        ],
                        onChanged: (value) =>
                            _changeDialogue(style.copyWith(colorMode: value)),
                      ),
                      if (style.colorMode == NovelDialogueColorMode.custom)
                        _ColorField(
                          key: const ValueKey('novel-dialogue-text-color'),
                          label: l10n.novelReaderTextColor,
                          color: Color(style.textColor),
                          onChanged: (color) => _changeDialogue(
                            style.copyWith(textColor: color.toARGB32()),
                          ),
                        ),
                      _selectRow<NovelDialogueWeight>(
                        key: const ValueKey('novel-dialogue-weight'),
                        label: l10n.novelReaderDialogueWeight,
                        value: style.weight,
                        items: [
                          SelectItem(
                            NovelDialogueWeight.body,
                            l10n.novelReaderDialogueFollowBody,
                          ),
                          SelectItem(
                            NovelDialogueWeight.medium,
                            l10n.novelReaderDialogueMedium,
                          ),
                          SelectItem(
                            NovelDialogueWeight.bold,
                            l10n.novelReaderDialogueBold,
                          ),
                        ],
                        onChanged: (value) =>
                            _changeDialogue(style.copyWith(weight: value)),
                      ),
                      SwitchListTile.adaptive(
                        key: const ValueKey(
                          'novel-dialogue-background-enabled',
                        ),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.novelReaderDialogueBackground),
                        value: style.backgroundEnabled,
                        onChanged: (value) => _changeDialogue(
                          style.copyWith(backgroundEnabled: value),
                        ),
                      ),
                      if (style.backgroundEnabled) ...[
                        _ColorField(
                          key: const ValueKey(
                            'novel-dialogue-background-color',
                          ),
                          label: l10n.novelReaderBackgroundColor,
                          color: Color(style.backgroundColor),
                          onChanged: (color) => _changeDialogue(
                            style.copyWith(backgroundColor: color.toARGB32()),
                          ),
                        ),
                        Text(
                          '${l10n.novelReaderDialogueBackgroundStrength} · ${(style.backgroundOpacity * 100).round()}%',
                        ),
                        Slider(
                          key: const ValueKey(
                            'novel-dialogue-background-opacity',
                          ),
                          value: style.backgroundOpacity,
                          divisions: 100,
                          label: '${(style.backgroundOpacity * 100).round()}%',
                          onChanged: (value) => _changeDialogue(
                            style.copyWith(backgroundOpacity: value),
                          ),
                        ),
                      ],
                      if (lowContrast)
                        Padding(
                          key: const ValueKey('novel-dialogue-low-contrast'),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: Text(
                            l10n.novelReaderDialogueLowContrast,
                            style: tt.bodySmall?.copyWith(
                              color: AppStatusColors.warning(cs),
                            ),
                          ),
                        ),
                    ],
                    const Divider(height: AppSpacing.xxl),
                    ReaderSettingsFold(
                      key: const ValueKey('novel-custom-theme-settings'),
                      title: l10n.novelReaderThemeCustom,
                      icon: Icons.tune_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              ActionChip(
                                key: const ValueKey('novel-theme-add'),
                                avatar: const Icon(
                                  Icons.add,
                                  size: AppIconSize.sm,
                                ),
                                label: Text(l10n.novelReaderThemeAdd),
                                onPressed: _addCustomTheme,
                              ),
                            ],
                          ),
                          if (_settings.customThemes.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            for (final theme in _settings.customThemes)
                              _customThemeTile(theme),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _contrastRatio(Color foreground, Color background) {
    final first = Color.alphaBlend(foreground, background).computeLuminance();
    final second = background.computeLuminance();
    return first > second
        ? (first + 0.05) / (second + 0.05)
        : (second + 0.05) / (first + 0.05);
  }

  Widget _selectRow<T>({
    required Key key,
    required String label,
    required T value,
    required List<SelectItem<T>> items,
    required ValueChanged<T> onChanged,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: SelectTile<T>(
              value: value,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _modeTile({
    required Key key,
    required String label,
    required String value,
    required bool dark,
    required ValueChanged<String> onChanged,
  }) => Builder(
    builder: (context) {
      final tt = Theme.of(context).textTheme;
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(label, style: tt.bodyMedium)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: SelectTile<String>(
                  // 绑定被删的自定义主题时回退到该模式的默认内置主题，
                  // 与渲染层 themeIdFor 的兜底一致，避免「显示白底、
                  // 实际夜间」的错位。
                  value: _settings.hasTheme(value)
                      ? value
                      : (dark
                            ? NovelReaderSettings.defaultDarkThemeId
                            : NovelReaderSettings.defaultLightThemeId),
                  items: [
                    for (final id in _allThemes) SelectItem(id, _themeName(id)),
                  ],
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _customThemeTile(NovelReaderCustomTheme theme) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final boundTo = [
      if (_settings.lightThemeId == theme.id) l10n.novelReaderThemeLightMode,
      if (_settings.darkThemeId == theme.id) l10n.novelReaderThemeDarkMode,
    ].join(' / ');
    return Padding(
      key: ValueKey('novel-custom-theme-${theme.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(theme.backgroundColor),
              borderRadius: AppRadius.smR,
              border: Border.all(color: cs.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Text(
              '文',
              style: tt.labelSmall?.copyWith(color: Color(theme.textColor)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(theme.name, style: tt.bodyMedium),
                if (boundTo.isNotEmpty)
                  Text(
                    boundTo,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('novel-custom-theme-edit-${theme.id}'),
            tooltip: l10n.novelReaderThemeEdit,
            onPressed: () => _editCustomTheme(theme),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey('novel-custom-theme-delete-${theme.id}'),
            tooltip: l10n.deleteButton,
            onPressed: () => _removeCustomTheme(theme),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
