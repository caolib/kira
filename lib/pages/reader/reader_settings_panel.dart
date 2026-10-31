part of '../reader_page.dart';

class _ReaderSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;
  const _ReaderSettingsPanel({required this.onChanged});

  @override
  State<_ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<_ReaderSettingsPanel> {
  final _user = UserManager();
  final _stats = ImageLoadStats();
  bool _isDraggingBrightness = false;
  bool _autoScrollExpanded = false;
  bool _zoomExpanded = false;

  @override
  void initState() {
    super.initState();
    _stats.addListener(_onStatsChanged);
  }

  @override
  void dispose() {
    _stats.removeListener(_onStatsChanged);
    super.dispose();
  }

  void _onStatsChanged() {
    if (mounted) setState(() {});
  }

  Widget _details({required bool expanded, required Widget child}) =>
      CollapsibleContent(
        expanded: expanded,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: child,
        ),
      );

  Widget _slider({
    required String title,
    required String valueText,
    required double value,
    double min = 0,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeStart,
    ValueChanged<double>? onChangeEnd,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(title, style: theme.textTheme.bodyMedium),
            Text(
              valueText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
          onChangeStart: onChangeStart,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }

  Widget _buildAutoScrollSettings(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _slider(
          title: l10n.readerAutoScrollDistance,
          valueText: '${(_user.readerAutoScrollDistance * 100).round()}%',
          value: _user.readerAutoScrollDistance,
          min: 0.2,
          max: 1,
          divisions: 16,
          onChanged: (v) {
            _user.setReaderAutoScrollDistance(v);
            setState(() {});
          },
        ),
        _slider(
          title: l10n.readerAutoScrollPause,
          valueText: l10n.readerSeconds(
            _user.readerAutoScrollPause.toStringAsFixed(1),
          ),
          value: _user.readerAutoScrollPause,
          min: 0.5,
          max: 8,
          divisions: 15,
          onChanged: (v) {
            _user.setReaderAutoScrollPause(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.readerAutoResume),
          subtitle: Text(l10n.readerAutoResumeDesc),
          value: _user.readerAutoScrollResume,
          onChanged: (v) {
            _user.setReaderAutoScrollResume(v);
            setState(() {});
          },
        ),
        if (_user.readerAutoScrollResume)
          _slider(
            title: l10n.readerAutoResumeDelay,
            valueText: l10n.readerSeconds(
              _user.readerAutoScrollResumeDelay.toStringAsFixed(1),
            ),
            value: _user.readerAutoScrollResumeDelay.clamp(1.0, 5.0),
            min: 1,
            max: 5,
            divisions: 8,
            onChanged: (v) {
              _user.setReaderAutoScrollResumeDelay(v);
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _buildImageLoadingSettings(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final avg = _stats.averageMs;
    return ReaderSettingsFold(
      key: const ValueKey('reader-image-loading-settings'),
      title: l10n.readerImageLoadingSection,
      icon: Icons.image_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _slider(
            title: l10n.readerTimeout,
            valueText: '${_user.imageLoadTimeout} s',
            value: _user.imageLoadTimeout.toDouble(),
            min: 3,
            max: 60,
            divisions: 57,
            onChanged: (v) {
              _user.setImageLoadTimeout(v.round());
              setState(() {});
              widget.onChanged();
            },
          ),
          Text(
            l10n.readerTimeoutDesc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (avg != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.readerRecentLoadStats(
                _stats.sampleCount,
                (avg / 1000).toStringAsFixed(1),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _slider(
            title: l10n.readerRetryCount,
            valueText: _user.imageRetryCount == 0
                ? l10n.offButton
                : l10n.readerTimes(_user.imageRetryCount),
            value: _user.imageRetryCount.toDouble(),
            max: 5,
            divisions: 5,
            onChanged: (v) {
              _user.setImageRetryCount(v.round());
              setState(() {});
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    final isPageMode = _user.readerMode == 1;
    final isHorizontalScroll = !isPageMode && _user.readerScrollDirection != 2;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: adaptiveDuration(context, const Duration(milliseconds: 200)),
      opacity: _isDraggingBrightness ? 0 : 1.0,
      child: AppSheet(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.readerSettingsTitle,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xl),
              SettingsSection(
                key: const ValueKey('reader-mode-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: 0,
                          icon: const Icon(Icons.view_day),
                          label: Text(l10n.readerScrollMode),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: const Icon(Icons.auto_stories),
                          label: Text(l10n.readerPageMode),
                        ),
                      ],
                      selected: {_user.readerMode},
                      onSelectionChanged: (v) {
                        _user.setReaderMode(v.first);
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: 0,
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(l10n.readerLeftToRight),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: const Icon(Icons.arrow_back),
                          label: Text(l10n.readerRightToLeft),
                        ),
                        ButtonSegment(
                          value: 2,
                          icon: const Icon(Icons.arrow_downward),
                          label: Text(l10n.readerTopToBottom),
                        ),
                      ],
                      selected: {_user.readerScrollDirection},
                      onSelectionChanged: (v) {
                        _user.setReaderScrollDirection(v.first);
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (isDark) ...[
                SettingsSection(
                  child: _slider(
                    title: l10n.readerDimming,
                    valueText: '${(_user.readerDimming * 100).round()}%',
                    value: _user.readerDimming,
                    max: 0.7,
                    divisions: 14,
                    onChangeStart: (_) =>
                        setState(() => _isDraggingBrightness = true),
                    onChangeEnd: (_) =>
                        setState(() => _isDraggingBrightness = false),
                    onChanged: (v) {
                      _user.setReaderDimming(v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (!isPageMode) ...[
                SettingsSection(
                  key: const ValueKey('reader-scroll-card'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _slider(
                        title: l10n.readerImageGap,
                        valueText: '${_user.readerImageGap.round()} px',
                        value: _user.readerImageGap,
                        max: 20,
                        divisions: 20,
                        onChanged: (v) {
                          _user.setReaderImageGap(v);
                          setState(() {});
                          widget.onChanged();
                        },
                      ),
                      if (isHorizontalScroll)
                        _slider(
                          title: l10n.readerHorizontalImageScale,
                          valueText:
                              '${(_user.readerHorizontalImageScale * 100).round()}%',
                          value: _user.readerHorizontalImageScale,
                          min: 0.7,
                          max: 1,
                          divisions: 6,
                          onChanged: (v) {
                            _user.setReaderHorizontalImageScale(v);
                            setState(() {});
                            widget.onChanged();
                          },
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.readerContinuousReading),
                        subtitle: Text(l10n.readerContinuousReadingDesc),
                        value: _user.readerContinuousReading,
                        onChanged: (v) {
                          _user.setReaderContinuousReading(v);
                          setState(() {});
                          widget.onChanged();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SettingsSection(
                  key: const ValueKey('reader-auto-scroll-card'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CollapsibleSwitchTile(
                        title: l10n.readerAutoScroll,
                        subtitle: l10n.readerAutoScrollDesc,
                        switchKey: const ValueKey('reader-auto-scroll-switch'),
                        expandKey: const ValueKey(
                          'reader-auto-scroll-details-toggle',
                        ),
                        value: _user.readerAutoScrollEnabled,
                        expanded: _autoScrollExpanded,
                        onChanged: (v) {
                          _user.setReaderAutoScrollEnabled(v);
                          setState(() {});
                          widget.onChanged();
                        },
                        onToggleExpanded: () => setState(
                          () => _autoScrollExpanded = !_autoScrollExpanded,
                        ),
                      ),
                      _details(
                        expanded: _autoScrollExpanded,
                        child: _buildAutoScrollSettings(l10n),
                      ),
                    ],
                  ),
                ),
              ],
              if (isPageMode)
                SettingsSection(
                  key: const ValueKey('reader-page-turn-card'),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.readerVolumeKeyPageTurn),
                        subtitle: Text(l10n.readerVolumeKeyPageTurnDesc),
                        value: _user.readerVolumeKey,
                        onChanged: (v) {
                          _user.setReaderVolumeKey(v);
                          setState(() {});
                          widget.onChanged();
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.readerInstantPageTurn),
                        value: _user.readerInstantPageTurn,
                        onChanged: (v) {
                          _user.setReaderInstantPageTurn(v);
                          setState(() {});
                          widget.onChanged();
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              SettingsSection(
                key: const ValueKey('reader-long-press-zoom-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CollapsibleSwitchTile(
                      title: l10n.readerLongPressZoom,
                      subtitle: l10n.readerLongPressZoomDesc,
                      switchKey: const ValueKey(
                        'reader-long-press-zoom-switch',
                      ),
                      expandKey: const ValueKey(
                        'reader-long-press-zoom-details-toggle',
                      ),
                      value: _user.reader.longPressZoomEnabled,
                      expanded: _zoomExpanded,
                      onChanged: (value) async {
                        await _user.reader.setLongPressZoomEnabled(value);
                        if (!mounted) return;
                        setState(() {});
                        widget.onChanged();
                      },
                      onToggleExpanded: () =>
                          setState(() => _zoomExpanded = !_zoomExpanded),
                    ),
                    _details(
                      expanded: _zoomExpanded,
                      child: ReaderLongPressZoomSensitivityControl(
                        title: l10n.readerLongPressZoomPanSensitivity,
                        value: _user.reader.longPressZoomPanSensitivity,
                        onCommitted: (value) async {
                          await _user.reader.setLongPressZoomPanSensitivity(
                            value,
                          );
                          if (!mounted) return;
                          widget.onChanged();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SettingsSection(
                child: SwitchListTile.adaptive(
                  key: const ValueKey('reader-keep-screen-on'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.novelReaderKeepScreenOn),
                  value: _user.reader.keepScreenOn,
                  onChanged: (value) async {
                    await _user.reader.setKeepScreenOn(value);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ReaderStatusSettingsSection(onChanged: widget.onChanged),
              const SizedBox(height: AppSpacing.sm),
              _buildImageLoadingSettings(l10n),
            ],
          ),
        ),
      ),
    );
  }
}
