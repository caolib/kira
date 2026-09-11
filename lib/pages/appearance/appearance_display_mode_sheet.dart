part of '../appearance_page.dart';

class _DisplayModeSheet extends StatefulWidget {
  final UserManager user;

  const _DisplayModeSheet({required this.user});

  @override
  State<_DisplayModeSheet> createState() => _DisplayModeSheetState();
}

class _DisplayModeSheetState extends State<_DisplayModeSheet> {
  late Future<DisplayModeData> _future;
  int? _applyingRate;

  @override
  void initState() {
    super.initState();
    _future = DisplayModePreference.load();
  }

  Future<void> _selectRefreshRate(int refreshRate, DisplayModeData data) async {
    if (_applyingRate != null) return;

    setState(() => _applyingRate = refreshRate);
    await widget.user.setDisplayModeRefreshRate(refreshRate);
    final applied = await DisplayModePreference.applyRefreshRate(
      refreshRate,
      modes: data.modes,
      active: data.active,
    );

    if (!mounted) return;
    setState(() => _applyingRate = null);
    final l10n = AppLocalizations.of(context)!;
    showToast(
      context,
      applied
          ? l10n.appearanceRefreshRateRequested(
              _formatRefreshRate(refreshRate, l10n),
            )
          : l10n.appearanceRefreshRateSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: FutureBuilder<DisplayModeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 220,
              child: Center(child: ExpressiveLoadingIndicator()),
            );
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.appearanceRefreshRateTitle,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.appearanceRefreshRateLoadFailed(
                      (snapshot.error ?? l10n.appearanceUnknownError)
                          .toString(),
                    ),
                    style: tt.bodyMedium?.copyWith(color: cs.error),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final currentRate = widget.user.displayModeRefreshRate;
          final activeRate = data.active.refreshRate.round();
          final rates = DisplayModePreference.refreshRates(data.modes);
          final isApplying = _applyingRate != null;

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.appearanceRefreshRateTitle,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: RadioGroup<int>(
                      groupValue: currentRate,
                      onChanged: (value) {
                        if (isApplying || value == null) return;
                        _selectRefreshRate(value, data);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            value: UserManager.defaultDisplayModeRefreshRate,
                            title: Text(l10n.appearanceAutoSystem),
                          ),
                          for (final rate in rates)
                            RadioListTile<int>(
                              contentPadding: EdgeInsets.zero,
                              value: rate,
                              title: Text(
                                rate == activeRate
                                    ? l10n.appearanceRefreshRateCurrent(rate)
                                    : '${rate}Hz',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isApplying) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.appearanceApplyingRefreshRate(
                          _formatRefreshRate(_applyingRate!, l10n),
                        ),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.appearanceRefreshRateDesc,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
