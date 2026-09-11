part of '../appearance_page.dart';

class _AppFontCard extends StatefulWidget {
  final UserManager user;

  const _AppFontCard({required this.user});

  @override
  State<_AppFontCard> createState() => _AppFontCardState();
}

class _AppFontCardState extends State<_AppFontCard> {
  final _fontManager = FontManager();
  List<RemoteFontInfo> _fonts = const [];
  Map<String, bool> _downloadedCache = {};
  final _downloadStates = <String, bool>{};
  double? _previewDefaultFontSize;
  bool _fontCatalogLoaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refreshDownloadStates();
  }

  Future<void> _refreshDownloadStates() async {
    final downloaded = await _fontManager.listDownloadedFonts();
    final results = <String, bool>{};
    for (final name in downloaded) {
      results[name] = true;
    }
    if (mounted) setState(() => _downloadedCache = results);
  }

  Future<void> _loadFonts({bool force = false}) async {
    if (_loading) return;
    if (!force && _fontCatalogLoaded) return;
    setState(() => _loading = true);
    final fonts = await _fontManager.fetchAvailableFonts(force: force);
    await _refreshDownloadStates();
    if (mounted) {
      setState(() {
        _fonts = fonts;
        _fontCatalogLoaded = true;
        _loading = false;
      });
    }
  }

  Future<void> _selectFont(String fontName) async {
    if (_downloadStates[fontName] == true) return;

    final currentFont = widget.user.theme.appFontFamily;

    if (fontName == FontManager.defaultFontId) {
      if (currentFont.isEmpty) return;
      await widget.user.theme.setAppFontFamily(FontManager.defaultFontId);
      return;
    }

    if (currentFont == fontName) return;

    final isDownloaded = _downloadedCache[fontName] ?? false;
    if (!isDownloaded) {
      final font = _fontManager.infoForName(fontName);
      if (font == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final l10n = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text(l10n.appearanceFontDownloadTitle),
            content: Text(l10n.appearanceFontDownloadPrompt(font.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.appearanceFontDownloadTooltip),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      await _downloadFont(fontName);
      if (!(_downloadedCache[fontName] ?? false)) return;
    }

    final loaded = await _fontManager.loadFont(fontName);
    if (loaded != null) {
      await widget.user.theme.setAppFontFamily(fontName);
    }
  }

  Future<void> _downloadFont(String fontName) async {
    if (_downloadStates[fontName] == true) return;

    final font = _fontManager.infoForName(fontName);
    if (font == null) return;

    setState(() => _downloadStates[fontName] = true);
    try {
      final ok = await _fontManager.downloadFont(font);
      if (ok) {
        await _fontManager.loadFont(fontName);
      } else if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceFontDownloadFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloadStates[fontName] = false);
        await _refreshDownloadStates();
      }
    }
  }

  Future<void> _deleteFont(RemoteFontInfo font) async {
    final l10n = AppLocalizations.of(context)!;
    final isCustom = font.isCustom;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isCustom
              ? l10n.appearanceCustomFontRemoveTitle
              : l10n.appearanceFontDeleteTitle,
        ),
        content: Text(
          isCustom
              ? l10n.appearanceCustomFontRemoveContent(font.name)
              : l10n.appearanceFontDeleteContent(font.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (widget.user.theme.appFontFamily == font.name) {
      await widget.user.theme.setAppFontFamily(FontManager.defaultFontId);
    }
    if (isCustom) {
      await _fontManager.removeCustomFont(font.name);
    } else {
      await _fontManager.deleteFont(font.name);
    }
    await _refreshDownloadStates();
    if (mounted) {
      setState(() {
        _fonts = List<RemoteFontInfo>.from(_fontManager.cachedList);
      });
    }
  }

  Future<void> _showAddCustomFontDialog() async {
    final l10n = AppLocalizations.of(context)!;

    // 控制器交给 TextControllerScope 托管：弹窗退出动画期间子树仍会重建，
    // 提前 dispose 会命中 “used after being disposed” 断言。
    final submitted = await showDialog<({String name, String url})>(
      context: context,
      builder: (ctx) => TextControllerScope(
        builder: (ctx, nameController) => TextControllerScope(
          builder: (ctx, urlController) => AlertDialog(
            title: Text(l10n.appearanceAddCustomFont),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: l10n.appearanceCustomFontNameLabel,
                      hintText: l10n.appearanceCustomFontNameHint,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: urlController,
                    decoration: InputDecoration(
                      labelText: l10n.appearanceCustomFontUrlLabel,
                      hintText: l10n.appearanceCustomFontUrlHint,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, (
                  name: nameController.text.trim(),
                  url: urlController.text.trim(),
                )),
                child: Text(l10n.confirmButton),
              ),
            ],
          ),
        ),
      ),
    );

    if (submitted == null || !mounted) return;

    final fontName = submitted.name;
    final added = await _fontManager.addCustomFont(
      name: fontName,
      url: submitted.url,
    );
    if (!mounted) return;

    if (!added) {
      showToast(context, l10n.appearanceCustomFontInvalid, isError: true);
      return;
    }

    await _refreshDownloadStates();
    if (!mounted) return;
    setState(() {
      _fonts = List<RemoteFontInfo>.from(_fontManager.cachedList);
    });
    showToast(context, l10n.appearanceCustomFontAdded(fontName));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final currentFont = widget.user.theme.appFontFamily;
    final currentLabel = currentFont.isEmpty
        ? l10n.appearanceSystemDefault
        : currentFont;
    final defaultFontSize =
        _previewDefaultFontSize ?? widget.user.theme.defaultFontSize;

    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 字体大小设置常驻显示，不随字体列表折叠。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _AppearanceSliderControl(
              icon: Icons.format_size_rounded,
              title: l10n.appearanceDefaultFontSize,
              description: l10n.appearanceDefaultFontSizeDesc,
              valueText: defaultFontSize.toStringAsFixed(0),
              value: defaultFontSize,
              min: ThemeSettings.minDefaultFontSize,
              max: ThemeSettings.maxDefaultFontSize,
              divisions:
                  (ThemeSettings.maxDefaultFontSize -
                          ThemeSettings.minDefaultFontSize)
                      .round(),
              onChanged: (value) {
                setState(() => _previewDefaultFontSize = value);
              },
              onChangeEnd: (value) {
                setState(() => _previewDefaultFontSize = null);
                unawaited(widget.user.theme.setDefaultFontSize(value));
              },
            ),
          ),
          const Divider(height: 1),
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(Icons.text_fields, color: cs.onSurfaceVariant),
            title: Text(l10n.appearanceAppFont),
            subtitle: Text(
              currentLabel,
              style: tt.bodySmall?.copyWith(
                fontFamily: currentFont.isEmpty ? null : currentFont,
              ),
            ),
            trailing: SizedBox(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.appearanceAddCustomFont,
                    onPressed: _showAddCustomFontDialog,
                    icon: Icon(Icons.add_rounded, color: cs.primary),
                    iconSize: 22,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (_loading)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: l10n.refreshButton,
                      onPressed: () => _loadFonts(force: true),
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      iconSize: 22,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Icon(
                        Icons.expand_more,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            onExpansionChanged: (expanded) {
              if (expanded && !_fontCatalogLoaded && !_loading) {
                _loadFonts();
              }
            },
            children: [
              const Divider(height: 1),
              if (_loading && _fonts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              else ...[
                RadioGroup<String>(
                  groupValue: currentFont.isEmpty
                      ? FontManager.defaultFontId
                      : currentFont,
                  onChanged: (value) {
                    if (value != null) _selectFont(value);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        value: FontManager.defaultFontId,
                        title: Text(l10n.appearanceSystemDefault),
                      ),
                      for (final font in _fonts)
                        RadioListTile<String>(
                          value: font.name,
                          title: Text(font.name),
                          subtitle: _buildFontSubtitle(font, l10n, cs),
                          secondary: _buildFontActions(font, l10n, cs),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget? _buildFontSubtitle(
    RemoteFontInfo font,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final isDownloaded = _downloadedCache[font.name] == true;
    if (!font.isCustom && isDownloaded) return null;

    final parts = <Widget>[];
    if (font.isCustom) {
      parts.add(
        Text(
          l10n.appearanceCustomFontBadge,
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (!isDownloaded) {
      if (parts.isNotEmpty) {
        parts.add(
          Text(' · ', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        );
      }
      parts.add(Text(l10n.appearanceFontNotDownloaded));
    }

    if (parts.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }

  Widget _buildFontActions(
    RemoteFontInfo font,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    if (_downloadStates[font.name] == true) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final isDownloaded = _downloadedCache[font.name] == true;
    final actions = <Widget>[];

    if (!isDownloaded) {
      actions.add(
        IconButton(
          icon: Icon(
            Icons.download_outlined,
            size: 20,
            color: colorScheme.primary,
          ),
          tooltip: l10n.appearanceFontDownloadTooltip,
          onPressed: () => _downloadFont(font.name),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    // Custom fonts can always be removed (even before download).
    // Built-in remote fonts only expose delete after they are downloaded.
    if (font.isCustom || isDownloaded) {
      actions.add(
        IconButton(
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          tooltip: font.isCustom
              ? l10n.appearanceCustomFontRemoveTitle
              : l10n.appearanceFontDeleteTitle,
          onPressed: () => _deleteFont(font),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (actions.length == 1) return actions.single;
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }
}
