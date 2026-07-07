part of '../anime_player_page.dart';

class _PlayerSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;
  final DanmakuController? danmakuController;
  final bool danmakuVisible;
  final ValueChanged<bool> onDanmakuVisibleChanged;

  const _PlayerSettingsPanel({
    required this.onChanged,
    this.danmakuController,
    required this.danmakuVisible,
    required this.onDanmakuVisibleChanged,
  });

  @override
  State<_PlayerSettingsPanel> createState() => _PlayerSettingsPanelState();
}

class _PlayerSettingsPanelState extends State<_PlayerSettingsPanel> {
  final _user = UserManager();
  late int _skipSeconds;
  late bool _playbackProgressEnabled;
  late double _fontSize;
  late double _area;
  late double _opacity;
  late bool _hideScroll;
  late bool _hideTop;
  late bool _hideBottom;

  @override
  void initState() {
    super.initState();
    _skipSeconds = _user.animeSkipSeconds;
    _playbackProgressEnabled = _user.animePlaybackProgressEnabled;
    _fontSize = _user.danmakuFontSize;
    _area = _user.danmakuArea;
    _opacity = _user.danmakuOpacity;
    _hideScroll = _user.danmakuHideScroll;
    _hideTop = _user.danmakuHideTop;
    _hideBottom = _user.danmakuHideBottom;
  }

  void _updateDanmakuOption() {
    widget.danmakuController?.updateOption(
      DanmakuOption(
        fontSize: _fontSize,
        duration: 8,
        opacity: _opacity,
        area: _area,
        hideScroll: _hideScroll,
        hideTop: _hideTop,
        hideBottom: _hideBottom,
      ),
    );
    _user.setDanmakuFontSize(_fontSize);
    _user.setDanmakuArea(_area);
    _user.setDanmakuOpacity(_opacity);
    _user.setDanmakuHideScroll(_hideScroll);
    _user.setDanmakuHideTop(_hideTop);
    _user.setDanmakuHideBottom(_hideBottom);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Playback settings
            Text(
              AppLocalizations.of(context)!.playerSettingsPlaybackTitle,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.playerSettingsSkipSeconds,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.playerSettingsSkipSecondsDesc,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: TextEditingController(text: _skipSeconds.toString()),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                )!.playerSettingsSecondsLabel,
                suffixText: AppLocalizations.of(context)!.readerSecondsSuffix,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                final value = int.tryParse(v);
                if (value != null && value > 0) {
                  _skipSeconds = value;
                  _user.setAnimeSkipSeconds(value);
                  widget.onChanged();
                }
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                AppLocalizations.of(context)!.playerSettingsRecordProgress,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                AppLocalizations.of(context)!.playerSettingsRecordProgressDesc,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: _playbackProgressEnabled,
              onChanged: (v) {
                setState(() => _playbackProgressEnabled = v);
                _user.setAnimePlaybackProgressEnabled(v);
                widget.onChanged();
              },
            ),

            const Divider(height: 32),

            // Danmaku settings
            Text(
              AppLocalizations.of(context)!.playerSettingsDanmakuTitle,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Danmaku toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                AppLocalizations.of(context)!.playerSettingsShowDanmaku,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              value: widget.danmakuVisible,
              onChanged: (v) {
                widget.onDanmakuVisibleChanged(v);
                setState(() {});
              },
            ),

            // Details shown when danmaku is enabled.
            if (widget.danmakuVisible) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.playerSettingsFontSize,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    _fontSize.toStringAsFixed(0),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _fontSize,
                min: 10,
                max: 30,
                divisions: 20,
                label: _fontSize.toStringAsFixed(0),
                onChanged: (v) => setState(() => _fontSize = v),
                onChangeEnd: (v) => _updateDanmakuOption(),
              ),

              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.playerSettingsDisplayArea,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${(_area * 100).toStringAsFixed(0)}%',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _area,
                min: 0.1,
                divisions: 9,
                label: '${(_area * 100).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _area = v),
                onChangeEnd: (v) => _updateDanmakuOption(),
              ),

              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.playerSettingsOpacity,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${(_opacity * 100).toStringAsFixed(0)}%',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _opacity,
                min: 0.1,
                divisions: 9,
                label: '${(_opacity * 100).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _opacity = v),
                onChangeEnd: (v) => _updateDanmakuOption(),
              ),

              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.playerSettingsDanmakuType,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AppLocalizations.of(context)!.playerSettingsScrollDanmaku,
                  style: tt.bodyMedium,
                ),
                value: !_hideScroll,
                onChanged: (v) {
                  setState(() => _hideScroll = !v);
                  _updateDanmakuOption();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AppLocalizations.of(context)!.playerSettingsTopDanmaku,
                  style: tt.bodyMedium,
                ),
                value: !_hideTop,
                onChanged: (v) {
                  setState(() => _hideTop = !v);
                  _updateDanmakuOption();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AppLocalizations.of(context)!.playerSettingsBottomDanmaku,
                  style: tt.bodyMedium,
                ),
                value: !_hideBottom,
                onChanged: (v) {
                  setState(() => _hideBottom = !v);
                  _updateDanmakuOption();
                },
              ),

              // Blocklist settings
              const SizedBox(height: 8),
              _DanmakuBlocklistEditor(
                blocklist: _user.danmakuBlocklist,
                onChanged: (list) {
                  _user.setDanmakuBlocklist(list);
                  widget.onChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DanmakuBlocklistEditor extends StatefulWidget {
  final List<String> blocklist;
  final ValueChanged<List<String>> onChanged;

  const _DanmakuBlocklistEditor({
    required this.blocklist,
    required this.onChanged,
  });

  @override
  State<_DanmakuBlocklistEditor> createState() =>
      _DanmakuBlocklistEditorState();
}

class _DanmakuBlocklistEditorState extends State<_DanmakuBlocklistEditor> {
  late List<String> _words;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _words = List.from(widget.blocklist);
  }

  void _addWord() {
    final text = _controller.text.trim();
    if (text.isEmpty || _words.contains(text)) return;
    setState(() {
      _words.add(text);
      _controller.clear();
    });
    widget.onChanged(List.from(_words));
  }

  Future<void> _convertSimplifiedTraditional() async {
    final text = _controller.text;
    if (text.isEmpty) return;
    try {
      final converted = await ChineseConverter.convertToSimplifiedChinese(text);
      if (converted == text) {
        _controller.text = await ChineseConverter.convertToTraditionalChinese(
          text,
        );
      } else {
        _controller.text = converted;
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'player_settings.convert_chinese',
        ),
      );
    }
  }

  void _removeWord(int index) {
    setState(() => _words.removeAt(index));
    widget.onChanged(List.from(_words));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.playerSettingsBlocklist,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)!.playerSettingsBlocklistDesc,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: AppLocalizations.of(
                    context,
                  )!.playerSettingsBlocklistHint,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _convertSimplifiedTraditional,
                    icon: const Icon(Icons.translate, size: 20),
                    tooltip: AppLocalizations.of(
                      context,
                    )!.playerSettingsChineseConvertTooltip,
                  ),
                ),
                onSubmitted: (_) => _addWord(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _addWord, icon: const Icon(Icons.add)),
          ],
        ),
        if (_words.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _words.length; i++)
                Chip(
                  label: Text(_words[i]),
                  onDeleted: () => _removeWord(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
