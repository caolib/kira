part of '../about_page.dart';

extension _AboutPageUpdateSettings on _AboutPageState {
  /// 下拉里「自定义」项的哨兵值，正常镜像 URL 不会长这样。
  static const _customMirrorOption = '__custom__';

  bool _isValidUpdateMirrorPrefix(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// 自定义镜像输入框（保留原有能力），保存后即成为下拉当前项并进入自定义列表。
  Future<void> _editUpdateMirrorPrefix() async {
    final l10n = AppLocalizations.of(context)!;
    final formKey = GlobalKey<FormState>();

    // 控制器交给 TextControllerScope 托管：弹窗退出动画期间子树仍会重建，
    // 提前 dispose 会命中 “used after being disposed” 断言。
    final mirrorPrefix = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          initialText: _user.updateMirrorPrefix,
          builder: (dialogContext, controller) => AlertDialog(
            title: Text(l10n.aboutMirrorPrefixTitle),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.aboutMirrorPrefixLabel,
                  helperText: l10n.aboutMirrorPrefixHelper,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  if (!_isValidUpdateMirrorPrefix(trimmed)) {
                    return l10n.aboutInvalidMirrorPrefix;
                  }
                  return null;
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  UserManager.defaultUpdateMirrorPrefix,
                ),
                child: Text(l10n.aboutRestoreDefaultButton),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(dialogContext, controller.text);
                  }
                },
                child: Text(l10n.aboutSaveButton),
              ),
            ],
          ),
        );
      },
    );

    if (mirrorPrefix == null) return;
    // 非内置地址先记进自定义列表：切到别的源后它仍留在下拉里，可再选回或删除，
    // 不会因为一次切换就丢掉。内置地址与重复项会被 add 拒绝，只做切换。
    await _user.addCustomUpdateMirrorPrefix(mirrorPrefix);
    await _user.setUpdateMirrorPrefix(mirrorPrefix);
    if (!mounted) return;
    showToast(context, l10n.aboutMirrorPrefixSavedToast);
  }

  /// 镜像源弹出菜单（对齐账号中心列表项的 trailing 菜单）：内置项 + 自定义项
  /// （可逐条删除）+ 自定义入口。按钮上只显示当前镜像主机名并限宽，避免把
  /// ListTile 标题挤成多行。
  Widget _buildUpdateMirrorDropdown(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final current = _user.updateMirrorPrefix;
    return PopupMenuButton<String>(
      tooltip: l10n.aboutMirrorPrefixTitle,
      onSelected: (value) async {
        if (value == _customMirrorOption) {
          await _editUpdateMirrorPrefix();
          return;
        }
        if (value == current) return;
        await _user.setUpdateMirrorPrefix(value);
        if (!mounted) return;
        showToast(context, l10n.aboutMirrorPrefixSavedToast);
      },
      itemBuilder: (_) => [
        for (final option in UserManager.updateMirrorPrefixOptions)
          PopupMenuItem(value: option, child: Text(option)),
        for (final custom in _user.customUpdateMirrorPrefixes)
          PopupMenuItem(
            value: custom,
            child: Builder(
              // 菜单项自己的 context 才能 pop 掉菜单本身（删除后立即收起，
              // 下次打开就是删除后的列表）。
              builder: (itemContext) => Row(
                children: [
                  Expanded(
                    child: Text(
                      custom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: AppIconSize.md,
                    ),
                    tooltip: l10n.deleteButton,
                    color: cs.error,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () {
                      Navigator.pop(itemContext);
                      unawaited(_user.removeCustomUpdateMirrorPrefix(custom));
                    },
                  ),
                ],
              ),
            ),
          ),
        PopupMenuItem(
          value: _customMirrorOption,
          child: Text(l10n.networkCopyLoginDomainCustom),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              _mirrorHostLabel(current),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.arrow_drop_down_rounded,
            size: AppIconSize.lg,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// 按钮上的短标签：只取镜像地址的主机名，解析失败回退原串。
  String _mirrorHostLabel(String prefix) {
    final uri = Uri.tryParse(prefix);
    return (uri?.host.isNotEmpty ?? false) ? uri!.host : prefix;
  }

  Widget _buildUpdateChannelSelect(ColorScheme cs, AppLocalizations l10n) {
    final isBeta = _user.isBetaUpdateChannel;
    // 设备吃不下 beta(非 Android 或非 arm64)时,徽标改为警告色 + 警告图标,
    // 与提示文案里的红色警示对应。
    final unsupported = isBeta && !isBetaChannelSupported();
    final Color fg;
    final Color border;
    if (unsupported) {
      // 用错误红而非警告橙:与提示文案里的红色警示保持一致。
      fg = AppStatusColors.danger(cs);
      border = AppStatusColors.danger(cs);
    } else if (isBeta) {
      fg = AppStatusColors.onBetaAccent;
      border = AppStatusColors.betaAccent;
    } else {
      fg = cs.onSurfaceVariant;
      border = cs.outlineVariant;
    }
    final Color background = isBeta
        ? AppStatusColors.fill(border, alpha: 0.14)
        : cs.surfaceContainerHighest;
    return SelectTile<String>(
      value: _user.updateChannel,
      foregroundColor: fg,
      backgroundColor: background,
      borderSide: BorderSide(color: border),
      leadingIcon: unsupported
          ? Icons.error_outline_rounded
          : (isBeta ? Icons.science_outlined : Icons.flag_outlined),
      items: [
        SelectItem('stable', l10n.aboutStableChannelShort),
        const SelectItem('beta', 'beta'),
      ],
      onChanged: _onUpdateChannelSelected,
    );
  }

  Future<void> _onUpdateChannelSelected(String value) async {
    if (value == _user.updateChannel) return;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    // 切到预览版:先确认(说明 beta 的风险与仅 arm64 APK),取消则保持原渠道。
    if (value == 'beta') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.aboutBetaChannelConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.aboutBetaChannelNote),
              // 仅当设备不支持(非 Android 或非 arm64)时补一条红色警示;
              // 支持的设备不显示,避免多余噪音。
              if (!isBetaChannelSupported()) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.aboutBetaChannelArm64Only,
                  style: TextStyle(color: AppStatusColors.danger(cs)),
                ),
                // 探测到当前系统与架构时补一行;探测失败(返回 null)就整行不显示,
                // 不影响提示的其余部分。
                if (deviceEnvironment() case final environment?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.aboutBetaChannelDevice(
                      environment.os,
                      environment.arch ?? '?',
                    ),
                    style: TextStyle(color: AppStatusColors.danger(cs)),
                  ),
                ],
              ],
            ],
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
      if (confirmed != true || !mounted) return;
    }
    await _user.setUpdateChannel(value);
    if (!mounted) return;
    // 切渠道后立刻按新渠道复查一次,避免卡片还停留在旧渠道的结果上。
    unawaited(AppUpdateService.checkAndPrompt(context));
  }

  Future<void> _onUpdateCheckFrequencySelected(
    UpdateCheckFrequency value,
  ) async {
    try {
      await _user.setUpdateCheckFrequency(value);
    } catch (error, stack) {
      await AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'about.update_frequency',
      );
      if (mounted) showToast(context, error.toString(), isError: true);
    }
  }

  /// 更新设置卡：检查更新 / 自动检查 / 更新镜像。
  Widget _buildUpdateSettingsCard(ColorScheme cs, AppLocalizations l10n) {
    return SettingTileGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_alt),
          title: Text(l10n.aboutCheckUpdateTitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUpdateChannelSelect(cs, l10n),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => AppUpdateService.checkAndPrompt(context),
        ),
        ListTile(
          leading: const Icon(Icons.autorenew),
          title: Text(l10n.aboutAutoCheckUpdateTitle),
          trailing: Semantics(
            label: l10n.aboutAutoCheckUpdateTitle,
            child: SelectTile<UpdateCheckFrequency>(
              value: _user.updateCheckFrequency,
              items: [
                SelectItem(UpdateCheckFrequency.never, l10n.updateCheckNever),
                SelectItem(
                  UpdateCheckFrequency.startup,
                  l10n.updateCheckStartup,
                ),
                SelectItem(UpdateCheckFrequency.daily, l10n.updateCheckDaily),
                SelectItem(UpdateCheckFrequency.weekly, l10n.updateCheckWeekly),
                SelectItem(
                  UpdateCheckFrequency.monthly,
                  l10n.updateCheckMonthly,
                ),
              ],
              onChanged: _onUpdateCheckFrequencySelected,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: Text(l10n.aboutMirrorPrefixTitle),
          trailing: _buildUpdateMirrorDropdown(l10n),
        ),
      ],
    );
  }

  /// 法律/致谢卡：免责声明 / 鸣谢 / 许可证。
  Widget _buildLegalCard(ColorScheme cs, AppLocalizations l10n) {
    return SettingTileGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(l10n.disclaimerTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.disclaimer),
        ),
        ListTile(
          leading: const Icon(Icons.copyright_outlined),
          title: Text(l10n.aboutLicenseTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.license),
        ),
      ],
    );
  }
}
