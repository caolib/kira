part of '../network_page.dart';

extension _NetworkProxySection on _NetworkPageState {
  /// 代理设置：tile 组（模式 SelectTile + 手动代理行内配置）。
  Widget _buildProxySection(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final mode = _user.networkProxyMode;

    return SettingTileGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(l10n.networkProxySettings),
          subtitle: Text(
            NetworkProxy.activeProxyDescription(l10n),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SelectTile<NetworkProxyMode>(
            value: mode,
            items: [
              SelectItem(NetworkProxyMode.system, l10n.networkProxySystem),
              SelectItem(NetworkProxyMode.manual, l10n.networkProxyManual),
              SelectItem(NetworkProxyMode.direct, l10n.networkProxyDirect),
            ],
            onChanged: _setProxyMode,
          ),
        ),
        if (mode == NetworkProxyMode.manual)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                    border: const OutlineInputBorder(),
                    isDense: true,
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
          ),
        if (mode == NetworkProxyMode.direct)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.networkProxyDirectHint,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
