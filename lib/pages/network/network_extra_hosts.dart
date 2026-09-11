part of '../network_page.dart';

extension _NetworkExtraHosts on _NetworkPageState {
  Widget _buildExtraGroup(
    Map<String, int?> extra, {
    bool wide = false,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final entries = extra.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: AppRadius.xsR,
                ),
                child: Text(
                  l10n.networkOtherRouteGroup,
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (wide)
          Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == entries.length - 1 ? 0 : 10,
                  ),
                  child: _buildExtraCard(
                    host: entries[i].key,
                    latency: entries[i].value,
                    horizontal: true,
                    l10n: l10n,
                    tt: tt,
                    cs: cs,
                  ),
                ),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              const columns = 3;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: List.generate(entries.length, (i) {
                  return SizedBox(
                    width: width,
                    child: _buildExtraCard(
                      host: entries[i].key,
                      latency: entries[i].value,
                      l10n: l10n,
                      tt: tt,
                      cs: cs,
                    ),
                  );
                }),
              );
            },
          ),
      ],
    );
  }

  Widget _buildExtraCard({
    required String host,
    required int? latency,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
    bool horizontal = false,
  }) {
    final isPending = _isLatencyPending(-1, host);
    final tone = isPending
        ? _Tone.pending
        : (latency == null
              ? _Tone.timeout
              : (latency <= 800
                    ? _Tone.good
                    : latency <= 2000
                    ? _Tone.warn
                    : _Tone.bad));
    final color = tone.color(cs);
    final title = _networkApi.getExtraApiHostLabel(host, l10n);
    final valueText = isPending
        ? l10n.networkTesting
        : (latency == null ? l10n.networkTimeout : '$latency ms');

    final valueChild = _testingLatency && isPending
        ? SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : Text(
            valueText,
            style: tt.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              height: 1,
            ),
          );

    return Card(
      color: Color.alphaBlend(
        cs.surfaceContainerHighest.withValues(alpha: 0.35),
        cs.surface,
      ),
      // 宽屏横向布局与线路节点卡同款内边距（fromLTRB(12,10,12,12)），
      // 同列高度保持一致。
      child: Padding(
        padding: horizontal
            ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: horizontal
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  valueChild,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  valueChild,
                ],
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 代理卡（行内展开）
  // ─────────────────────────────────────────────────────────────────────
}
