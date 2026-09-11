part of '../about_page.dart';

extension _UpdateCardBuilders on _UpdateCardState {
  Widget _buildReleaseNotes(String notes, ColorScheme cs) {
    if (notes.trim().isEmpty) {
      return Text(
        AppLocalizations.of(context)!.updateNoReleaseNotes,
        style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
      );
    }
    return GitHubMarkdown(
      data: notes,
      styleSheet: githubMarkdownStyleSheet(
        context,
        foreground: cs.onSurfaceVariant,
      ),
    );
  }

  /// Compact card showing the changelog for the *currently installed* version.
  /// Rendered when the update check found no update but still returned release
  /// notes. Pure entry: tapping the card (or the 更新说明 button) opens the
  /// notes in a fullscreen dialog — notes never render inline.
  Widget _buildCurrentVersionCard(
    ColorScheme cs,
    TextTheme tt,
    AppUpdateInfo info,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showNotesFullscreen(cs, info.releaseNotes),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.updateCurrentVersionNotes,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.latestVersion,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      _showNotesFullscreen(cs, info.releaseNotes),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(l10n.updateViewNotes),
                ),
                IconButton(
                  tooltip: l10n.updateOpenReleasePage,
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  onPressed: _isInstalling
                      ? null
                      : () => _openUrl(info.releasePageUrl),
                  icon: Icon(
                    Icons.open_in_new,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstallButtons(
    ReleaseAsset asset,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final s = InAppInstaller.instance.state.value;
    final isThisAsset = s.assetName == asset.name;

    // Progress view when this asset is the active install.
    if (isThisAsset && s.isBusy) {
      final downloading = s.status == InstallStatus.downloading;
      final label = downloading
          ? (InAppInstaller.instance.progressLabel().isNotEmpty
                ? '${InAppInstaller.instance.progressLabel()}  ·  ${l10n.updateDownloading(s.total > 0 ? (s.received * 100 / s.total).round().clamp(0, 100) : 0)}'
                : l10n.updateDownloadPreparing)
          : (s.status == InstallStatus.preparing
                ? l10n.updateDownloadPreparing
                : l10n.updateInstalling);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadius.xsR,
            child: LinearProgressIndicator(
              value: downloading && s.total > 0 ? s.received / s.total : null,
              minHeight: 6,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    final disabled = _isInstalling;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: disabled ? null : () => _installInApp(asset),
            icon: _sourceIcon(cs, cs.onPrimary),
            label: Text(l10n.updateButtonUpdate),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          // 无浏览器 logo 资产，按需不显示图标，仅文字。
          child: FilledButton.tonal(
            onPressed: disabled
                ? null
                : () => _openUrl(
                    _useMirror ? asset.mirrorUrl : asset.downloadUrl,
                  ),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            child: Text(l10n.updateManualDownload),
          ),
        ),
      ],
    );
  }

  /// Shared source icon for update/download buttons. GitHub mark when using
  /// the direct URL, network icon when the mirror checkbox is ticked.
  Widget _sourceIcon(ColorScheme cs, Color color, {double size = 16}) {
    if (_useMirror) {
      return Icon(Icons.public, size: size + 2, color: color);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: SvgPicture.asset(
        'assets/github.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }

  Widget _buildAssetTile(
    ReleaseAsset asset,
    ColorScheme cs,
    TextTheme tt, {
    bool minimal = false,
  }) {
    // minimal：安装包列表统一紧凑样式——只显示文件名（小一号），
    // 不显示平台 logo / 平台名 / 文件大小。
    final subtitleParts = <String>[
      if (!minimal) asset.platform.label,
      if (!minimal && asset.sizeLabel.isNotEmpty) asset.sizeLabel,
    ];
    final canInstallInApp = _canInstallInApp(asset);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.mdR,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!minimal) ...[
                Icon(asset.platform.icon, size: 20, color: cs.primary),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            asset.name,
                            style: (minimal ? tt.bodySmall : tt.bodyMedium)
                                ?.copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (canInstallInApp) ...[
            const SizedBox(height: 10),
            _buildInstallButtons(asset, cs, tt),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            // 非当前平台包（如 Windows）：单个手动下载按钮，
            // 下载源跟随「使用镜像」勾选。
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.tonal(
                  onPressed: _isInstalling
                      ? null
                      : () => _openUrl(
                          _useMirror ? asset.mirrorUrl : asset.downloadUrl,
                        ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    textStyle: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.updateManualDownload,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMirrorCheckbox(
    ColorScheme cs,
    TextTheme tt, {
    bool dense = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: _isInstalling ? null : () => _setMirror(!_useMirror),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: dense ? 2 : 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: _useMirror,
                onChanged: _isInstalling ? null : (v) => _setMirror(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l10n.updateUseMirror,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
