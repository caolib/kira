part of '../network_page.dart';

extension _NetworkProxyCard on _NetworkPageState {
  Widget _buildProxyCard(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    final mode = _user.networkProxyMode;
    final isManual = mode == NetworkProxyMode.manual;

    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: cs.tertiary, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.networkProxySettings,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _ProxyPill(
                  active: _hasActiveProxy,
                  label: NetworkProxy.activeProxyDescription(l10n),
                  tt: tt,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<NetworkProxyMode>(
                segments: [
                  ButtonSegment(
                    value: NetworkProxyMode.system,
                    icon: const Icon(Icons.desktop_windows_rounded, size: 18),
                    label: Text(l10n.networkProxySystem),
                  ),
                  ButtonSegment(
                    value: NetworkProxyMode.manual,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(l10n.networkProxyManual),
                  ),
                  ButtonSegment(
                    value: NetworkProxyMode.direct,
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: Text(l10n.networkProxyDirect),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (v) => _setProxyMode(v.first),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isManual
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<NetworkProxyType>(
                            segments: const [
                              ButtonSegment(
                                value: NetworkProxyType.http,
                                label: Text('HTTP'),
                              ),
                              ButtonSegment(
                                value: NetworkProxyType.socks,
                                label: Text('SOCKS5'),
                              ),
                            ],
                            selected: {_manualProxyType},
                            onSelectionChanged: (v) {
                              _setState(() => _manualProxyType = v.first);
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _proxyAddressController,
                          decoration: InputDecoration(
                            labelText: l10n.networkProxyAddress,
                            hintText: l10n.networkProxyAddressHint,
                            prefixIcon: const Icon(Icons.link_rounded),
                            border: const OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saveManualProxy(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saveManualProxy,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(l10n.networkSaveAndEnableManualProxy),
                          ),
                        ),
                      ],
                    ),
                  )
                : mode == NetworkProxyMode.direct
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.networkProxyDirectHint,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveProxy {
    switch (_user.networkProxyMode) {
      case NetworkProxyMode.manual:
        return _user.hasManualProxy;
      case NetworkProxyMode.system:
        return NetworkProxy.systemProxy != null;
      case NetworkProxyMode.direct:
        return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 高级设置卡片（默认折叠，点击标题展开）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildAdvancedCard(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  _setState(() => _advancedExpanded = !_advancedExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: cs.secondary, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.networkAdvancedSettings,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
                    AnimatedRotation(
                      turns: _advancedExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _advancedExpanded
                ? _buildAdvancedContent(l10n, tt, cs)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 高级设置(COPY API 配置)的本体内容。
  Widget _buildAdvancedContent(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.networkCopyAutoUpdate, style: tt.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
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
                  ],
                ),
              ),
              Switch(
                value: _user.copyAutoUpdate,
                onChanged: (v) => _user.setCopyAutoUpdate(v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _user.copyLoginHost,
            decoration: InputDecoration(
              labelText: l10n.networkCopyLoginDomain,
              helperText: l10n.networkCopyLoginDomainHint,
              prefixIcon: const Icon(Icons.login_rounded),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final host in copyLoginHostOptions)
                DropdownMenuItem<String>(value: host, child: Text(host)),
            ],
            onChanged: (value) {
              if (value != null) _setCopyLoginHost(value);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _copyApiHostController,
            decoration: const InputDecoration(
              labelText: 'COPY API URL',
              hintText: defaultCopyApiHost,
              prefixIcon: Icon(Icons.dns_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _copyAppVersionController,
            decoration: InputDecoration(
              labelText: l10n.networkCopyAppVersion,
              hintText: defaultCopyAppVersion,
              prefixIcon: const Icon(Icons.numbers_rounded),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveCopyAdvancedSettings(),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildAdvancedActions(cs),
        ],
      ),
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

  // ─────────────────────────────────────────────────────────────────────
  // 延迟计算辅助
  // ─────────────────────────────────────────────────────────────────────

  double? _averageLatency(Map<String, int?>? results) {
    final values = results?.values.whereType<int>().toList() ?? const <int>[];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
