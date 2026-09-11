part of '../network_page.dart';

extension _NetworkNodesSection on _NetworkPageState {
  /// 线路与节点：模式选择（线路 / 节点）+ 线路卡片 + 其他固定 host。
  ///
  /// 选中态统一用「主色 2px 描边 + 主色淡填充 + 使用中徽标」表达，
  /// 与外观页的主题色 / 图标选择卡片同语言。
  Widget _buildNodesSection(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final isFixed =
        _user.networkSelectionMode == NetworkSelectionMode.fixedNode;

    return SettingsSection(
      icon: Icons.alt_route_rounded,
      title: l10n.networkNodesSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.networkSelectionMode),
            subtitle: Text(
              isFixed
                  ? l10n.networkModeFixedNodeDesc
                  : l10n.networkModeRouteDesc,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            trailing: SelectTile<NetworkSelectionMode>(
              value: _user.networkSelectionMode,
              items: [
                SelectItem(NetworkSelectionMode.route, l10n.networkModeRoute),
                SelectItem(
                  NetworkSelectionMode.fixedNode,
                  l10n.networkModeFixedNodeShort,
                ),
              ],
              onChanged: _setSelectionMode,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isFixed
                ? l10n.networkNodeGridFixedHint
                : l10n.networkNodeGridRouteHint,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          // 两种模式都始终展示全部线路：未测速时延迟显示为「—」，
          // 用户无需等测速完成即可点选。
          for (var r = 0; r < routes.length; r++) ...[
            if (r > 0) const SizedBox(height: AppSpacing.md),
            _buildRouteCard(
              routeIndex: r,
              isFixed: isFixed,
              l10n: l10n,
              tt: tt,
              cs: cs,
            ),
          ],
          if (_latencyResults[-1]?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.md),
            _buildExtraGroup(l10n, tt, cs),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 线路卡片
  // ─────────────────────────────────────────────────────────────────────

  /// 线路模式：整张卡可点选，选中卡 = 主色描边 + 淡填充 + 「使用中」徽标，
  /// 卡内节点以信息条形式展示各自延迟。
  ///
  /// 节点模式：卡片降级为分组容器（描边弱化），标题行不可点，
  /// 节点条升级为可选中的胶囊。
  Widget _buildRouteCard({
    required int routeIndex,
    required bool isFixed,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final hosts = routes[routeIndex];
    final results = _latencyResults[routeIndex] ?? const <String, int?>{};
    final average = _averageLatency(results);
    final isSelected = !isFixed && _user.apiRoute == routeIndex;

    return Material(
      // 描边宽度恒定：宽度随选中态变化会引起内容 1px 位移（页面抖动）。
      color: isSelected
          ? Color.alphaBlend(cs.primary.withValues(alpha: 0.10), cs.surface)
          : Color.alphaBlend(
              cs.surfaceContainerHighest.withValues(alpha: 0.25),
              cs.surface,
            ),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgR,
        side: BorderSide(
          color: isSelected
              ? cs.primary
              : cs.outlineVariant.withValues(alpha: 0.7),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 线路模式整卡点选切换线路；节点模式卡片仅作分组容器，不可点。
        onTap: isFixed ? null : () => _user.setApiRoute(routeIndex),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRouteHeader(
                routeIndex: routeIndex,
                average: average,
                isSelected: isSelected,
                l10n: l10n,
                tt: tt,
                cs: cs,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (isFixed)
                // 节点模式：节点胶囊可点选。
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var i = 0; i < hosts.length; i++)
                      _buildNodeChip(
                        routeIndex: routeIndex,
                        localIndex: i,
                        host: hosts[i],
                        latency: results[hosts[i]],
                        l10n: l10n,
                        tt: tt,
                        cs: cs,
                      ),
                  ],
                )
              else
                // 线路模式：节点延迟仅作展示，整卡点选。
                Column(
                  children: [
                    for (var i = 0; i < hosts.length; i++)
                      _buildNodeInfoRow(
                        routeIndex: routeIndex,
                        localIndex: i,
                        host: hosts[i],
                        latency: results[hosts[i]],
                        l10n: l10n,
                        tt: tt,
                        cs: cs,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteHeader({
    required int routeIndex,
    required double? average,
    required bool isSelected,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final hasPending = _pendingLatencyHosts.any(
      (k) => k.startsWith('$routeIndex|'),
    );

    return Row(
      children: [
        // 不加随选中出现的勾选图标：图标的出现/消失会平移标题，
        // 选中态由描边 + 填充 + 「使用中」徽标表达。
        Text(
          l10n.networkRouteLabel(routeIndex + 1),
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: isSelected ? cs.primary : cs.onSurface,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            average == null
                ? (hasPending
                      ? l10n.networkAverageTesting
                      : l10n.networkAverageTimeout)
                : l10n.networkAverageLatency(average.round()),
            style: tt.labelMedium?.copyWith(
              color: average == null
                  ? cs.onSurfaceVariant
                  : _latencyTone(average, cs),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (isSelected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: AppRadius.xsR,
            ),
            child: Text(
              l10n.networkCurrentInUse,
              style: tt.labelSmall?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  /// 线路模式下的节点展示行：节点名 + 延迟，不响应点击。
  Widget _buildNodeInfoRow({
    required int routeIndex,
    required int localIndex,
    required String host,
    required int? latency,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final isPending = _isLatencyPending(routeIndex, host);
    final untested = !_testingLatency && _latencyResults[routeIndex] == null;
    final tone = _nodeTone(isPending, latency);
    final color = untested ? cs.onSurfaceVariant : tone.color(cs);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _LatencyDot(color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.networkNodeLabel(_nodeNumber(routeIndex, localIndex)),
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          _buildLatencyText(
            isPending: isPending,
            untested: untested,
            latency: latency,
            color: color,
            tt: tt,
            l10n: l10n,
          ),
        ],
      ),
    );
  }

  /// 节点模式下的可选节点胶囊：选中 = 主色描边 + 淡填充 + 勾选图标。
  Widget _buildNodeChip({
    required int routeIndex,
    required int localIndex,
    required String host,
    required int? latency,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final isPending = _isLatencyPending(routeIndex, host);
    final untested = !_testingLatency && _latencyResults[routeIndex] == null;
    final isSelected = _user.fixedNodeHost == host;
    final tone = _nodeTone(isPending, latency);
    final color = untested ? cs.onSurfaceVariant : tone.color(cs);
    final title = l10n.networkNodeLabel(_nodeNumber(routeIndex, localIndex));

    return Material(
      color: isSelected
          ? Color.alphaBlend(cs.primary.withValues(alpha: 0.12), cs.surface)
          : Color.alphaBlend(
              cs.surfaceContainerHighest.withValues(alpha: 0.35),
              cs.surface,
            ),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdR,
        // 描边宽度恒定，避免选中/取消时内容位移。
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isPending ? null : () => _user.setFixedNodeHost(host),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(Icons.check_rounded, size: 14, color: cs.primary),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                title,
                style: tt.labelMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurface,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildLatencyText(
                isPending: isPending,
                untested: untested,
                latency: latency,
                color: color,
                tt: tt,
                l10n: l10n,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLatencyText({
    required bool isPending,
    required bool untested,
    required int? latency,
    required Color color,
    required TextTheme tt,
    required AppLocalizations l10n,
  }) {
    if (untested) {
      return Text(
        '—',
        style: tt.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (isPending) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Text(
      latency == null ? l10n.networkTimeout : '$latency ms',
      style: tt.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 其他固定 host（COPY API / 拷贝登录 / 热辣登录 / 固定接口）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildExtraGroup(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    final entries = (_latencyResults[-1] ?? const <String, int?>{}).entries
        .toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          cs.surfaceContainerHighest.withValues(alpha: 0.25),
          cs.surface,
        ),
        borderRadius: AppRadius.lgR,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.networkOtherRouteGroup,
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final entry in entries)
            _buildExtraRow(
              host: entry.key,
              latency: entry.value,
              l10n: l10n,
              tt: tt,
              cs: cs,
            ),
        ],
      ),
    );
  }

  Widget _buildExtraRow({
    required String host,
    required int? latency,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final isPending = _isLatencyPending(-1, host);
    final color = _nodeTone(isPending, latency).color(cs);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _LatencyDot(color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _networkApi.getExtraApiHostLabel(host, l10n),
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          _buildLatencyText(
            isPending: isPending,
            untested: false,
            latency: latency,
            color: color,
            tt: tt,
            l10n: l10n,
          ),
        ],
      ),
    );
  }
}
