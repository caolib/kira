part of '../network_page.dart';

extension _NetworkAdvancedSection on _NetworkPageState {
  /// 高级设置（COPY API 配置）：默认折叠，点击标题就地展开（无动画）。
  Widget _buildAdvancedSection(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return SettingsSection(
      color: cs.surfaceBright,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _setState(() => _advancedExpanded = !_advancedExpanded);
                // 展开时对拷贝登录域名做一次连通性测试。
                if (_advancedExpanded) _testLoginHostLatency();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Text(
                        l10n.networkAdvancedSettings,
                        style: tt.titleSmall ?? tt.titleMedium,
                      ),
                    ),
                    Text(
                      'COPY',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _advancedExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_advancedExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _buildAdvancedContent(l10n, tt, cs),
            ),
        ],
      ),
    );
  }

  Widget _buildAdvancedContent(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.networkCopyAutoUpdate, style: tt.bodyMedium),
          subtitle: Text(
            _user.copySettingsUpdatedAt == null
                ? l10n.networkCopyAutoUpdateNever
                : l10n.networkCopyAutoUpdateLast(
                    TimeFormat.relative(
                      DateTime.fromMillisecondsSinceEpoch(
                        _user.copySettingsUpdatedAt!,
                      ),
                      l10n,
                    ),
                  ),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          value: _user.copyAutoUpdate,
          onChanged: _user.setCopyAutoUpdate,
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildCopyLoginHostSection(l10n, tt, cs),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _copyApiHostController,
          decoration: const InputDecoration(
            labelText: 'COPY API URL',
            hintText: defaultCopyApiHost,
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _copyAppVersionController,
          decoration: InputDecoration(
            labelText: l10n.networkCopyAppVersion,
            hintText: defaultCopyAppVersion,
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saveCopyAdvancedSettings(),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildAdvancedActions(cs),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 拷贝登录域名：内置 + 自定义列表，可点选切换；自定义项可编辑/删除。
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildCopyLoginHostSection(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final current = _user.copyLoginHost;
    final entries = <MapEntry<String, bool>>[
      for (final host in copyLoginHostOptions) MapEntry(host, false),
      for (final host in _user.customCopyLoginHosts) MapEntry(host, true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.networkCopyLoginDomain,
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.networkCopyLoginDomainHint,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.smR,
            border: Border.all(color: cs.outline),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.smR,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  _buildLoginHostRow(
                    entries[i].key,
                    isCustom: entries[i].value,
                    isSelected: entries[i].key == current,
                    showDivider: i > 0,
                    l10n: l10n,
                    tt: tt,
                    cs: cs,
                  ),
                _buildLoginHostAddRow(l10n, tt, cs),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginHostRow(
    String host, {
    required bool isCustom,
    required bool isSelected,
    required bool showDivider,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final label = isCustom
        ? l10n.networkCopyLoginDomainCustom
        : (host == defaultCopyLoginHost
              ? l10n.networkCopyLoginDomainDefault
              : null);
    final isPending = _pendingLoginHosts.contains(host);
    final latency = _loginHostLatency[host];
    final tone = _nodeTone(isPending, latency);

    return Column(
      children: [
        if (showDivider)
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
        Material(
          color: isSelected
              ? Color.alphaBlend(cs.primary.withValues(alpha: 0.08), cs.surface)
              : Colors.transparent,
          child: InkWell(
            onTap: () => _setCopyLoginHost(host),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ),
                  _buildLatencyText(
                    isPending: isPending,
                    untested:
                        !isPending && !_loginHostLatency.containsKey(host),
                    latency: latency,
                    color: tone.color(cs),
                    tt: tt,
                    l10n: l10n,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (label != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isCustom
                            ? cs.secondaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: AppRadius.xsR,
                      ),
                      child: Text(
                        label,
                        style: tt.labelSmall?.copyWith(
                          color: isCustom
                              ? cs.onSecondaryContainer
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (isCustom) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _hostRowAction(
                      icon: Icons.edit_outlined,
                      tooltip: l10n.aiConfigEdit,
                      color: cs.onSurfaceVariant,
                      onTap: () => _editCustomLoginHost(host),
                    ),
                    _hostRowAction(
                      icon: Icons.delete_outline_rounded,
                      tooltip: l10n.deleteButton,
                      color: cs.error,
                      onTap: () => _removeCustomLoginHost(host),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hostRowAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: color,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildLoginHostAddRow(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Column(
      children: [
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customLoginHostController,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addCustomLoginHost(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonalIcon(
                onPressed: _addCustomLoginHost,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.commentSettingsAddButton),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedActions(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      child: _ConnectedButtonGroup(
        children: [
          _ConnectedButtonGroupItem(
            onPressed: _autoFillingCopySettings ? null : _autoFillCopySettings,
            loadingWidget: _autoFillingCopySettings
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : null,
            icon: _autoFillingCopySettings ? null : Icons.auto_fix_high,
            label: l10n.networkFill,
          ),
          _ConnectedButtonGroupItem(
            onPressed: _autoFillingCopySettings
                ? null
                : _resetCopyAdvancedSettings,
            icon: Icons.restart_alt,
            label: l10n.commentSettingsResetButton,
          ),
          _ConnectedButtonGroupItem(
            onPressed: _saveCopyAdvancedSettings,
            icon: Icons.save_outlined,
            label: l10n.commentSettingsSaveButton,
            isPrimary: true,
          ),
        ],
      ),
    );
  }
}
