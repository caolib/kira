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
        _buildCopyLoginHostSection(l10n, tt, cs),
        const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.md),
        _buildCopySettingField(
          controller: _copyApiHostController,
          label: l10n.networkCopyApiUrl,
          hint: defaultCopyApiHost,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildCopyVersionFields(l10n),
        const SizedBox(height: AppSpacing.md),
        _buildAdvancedActions(cs),
      ],
    );
  }

  Widget _buildCopySettingField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.done,
    ValueChanged<String>? onSubmitted,
  }) {
    // 浮动标签仅支持 start/center；装饰使用 RTL 把边框缺口放右侧，
    // 输入内容与提示仍显式保持 LTR，避免 URL 和数字的光标方向变化；
    // 方向覆盖仅限这三个输入框，不影响域名列表及操作区。
    return Directionality(
      textDirection: TextDirection.rtl,
      child: TextField(
        controller: controller,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintTextDirection: TextDirection.ltr,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          floatingLabelAlignment: FloatingLabelAlignment.start,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
      ),
    );
  }

  Widget _buildCopyVersionFields(AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = Theme.of(context).textTheme.bodyLarge!.fontSize!;
        final scale =
            MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
        // 两个短字段在普通手机上并排；窄屏/大字体保留足够的输入宽度。
        final twoColumns = constraints.maxWidth >= 288 * scale + AppSpacing.md;
        final width = twoColumns
            ? (constraints.maxWidth - AppSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: width,
              child: _buildCopySettingField(
                controller: _copyAppVersionController,
                label: l10n.networkCopyAppVersion,
                hint: defaultCopyAppVersion,
                onSubmitted: (_) => _saveCopyAdvancedSettings(),
              ),
            ),
            SizedBox(
              width: width,
              child: _buildCopySettingField(
                controller: _copyVersionCodeController,
                label: l10n.networkCopyVersionCode,
                hint: defaultCopyVersionCode,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _saveCopyAdvancedSettings(),
              ),
            ),
          ],
        );
      },
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
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.networkCopyLoginDomain,
                style: tt.labelLarge?.copyWith(fontWeight: FontWeight.normal),
              ),
            ),
            IconButton.filledTonal(
              tooltip: _addingLoginHost
                  ? l10n.cancelButton
                  : l10n.commentSettingsAddButton,
              onPressed: () {
                if (_addingLoginHost) FocusScope.of(context).unfocus();
                _setState(() => _addingLoginHost = !_addingLoginHost);
              },
              icon: Icon(
                _addingLoginHost ? Icons.close_rounded : Icons.add_rounded,
                size: AppIconSize.lg,
              ),
            ),
          ],
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
                if (_addingLoginHost) _buildLoginHostAddRow(l10n, tt, cs),
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
    final isPending = _pendingLoginHosts.contains(host);
    final latency = _loginHostLatency[host];
    final tone = _nodeTone(isPending, latency);

    final hostText = Text(
      host,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tt.bodyMedium?.copyWith(color: cs.onSurface),
    );
    final metadata = _buildLatencyText(
      isPending: isPending,
      untested: !isPending && !_loginHostLatency.containsKey(host),
      latency: latency,
      color: tone.color(cs),
      tt: tt,
      l10n: l10n,
    );
    return Column(
      children: [
        if (showDivider)
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _setCopyLoginHost(host),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fontSize = tt.bodyMedium!.fontSize!;
                    final scale =
                        MediaQuery.textScalerOf(context).scale(fontSize) /
                        fontSize;
                    final stacked =
                        constraints.maxWidth < (isCustom ? 360 : 220) * scale;
                    return Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: AppIconSize.lg,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: stacked
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    hostText,
                                    const SizedBox(height: AppSpacing.xs),
                                    metadata,
                                  ],
                                )
                              : hostText,
                        ),
                        if (!stacked) ...[
                          const SizedBox(width: AppSpacing.sm),
                          metadata,
                        ],
                        if (isCustom) ...[
                          const SizedBox(width: AppSpacing.sm),
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
                    );
                  },
                ),
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
      icon: Icon(icon, size: AppIconSize.md),
      tooltip: tooltip,
      color: color,
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
                    constraints: BoxConstraints(minHeight: 48),
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
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  visualDensity: VisualDensity.standard,
                ),
                icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
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
    final secondaryStyle = TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                onPressed: _autoFillingCopySettings
                    ? null
                    : _autoFillCopySettings,
                style: secondaryStyle,
                icon: _autoFillingCopySettings
                    ? SizedBox(
                        width: AppIconSize.md,
                        height: AppIconSize.md,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.auto_fix_high, size: AppIconSize.md),
                label: Text(l10n.networkFill),
              ),
              TextButton.icon(
                onPressed: _autoFillingCopySettings
                    ? null
                    : _resetCopyAdvancedSettings,
                style: secondaryStyle,
                icon: const Icon(Icons.restart_alt, size: AppIconSize.md),
                label: Text(l10n.commentSettingsResetButton),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.icon(
          onPressed: _saveCopyAdvancedSettings,
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          icon: const Icon(Icons.save_outlined, size: AppIconSize.md),
          label: Text(l10n.commentSettingsSaveButton),
        ),
      ],
    );
  }
}
