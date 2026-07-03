part of '../chapter_comments_sheet.dart';

class CommentSettingsPanel extends StatefulWidget {
  final bool useCompactLayout;
  final bool showUserAvatar;
  final bool showUserName;
  final bool showCommentTime;
  final double commentFontScale;
  final bool commentPreload;
  final bool commentAutoLoadAll;

  /// 章节评论专属区块（布局/预加载/自动加载全部/AI 总结）仅在此为 true 时显示。
  /// 漫画评论复用本面板时传 false。
  final bool isChapterComments;
  final ValueChanged<bool> onLayoutChanged;
  final ValueChanged<bool> onShowAvatarChanged;
  final ValueChanged<bool> onShowUserNameChanged;
  final ValueChanged<bool> onShowCommentTimeChanged;
  final ValueChanged<double> onFontScaleChanged;
  final ValueChanged<bool> onPreloadChanged;
  final ValueChanged<bool> onAutoLoadAllChanged;

  const CommentSettingsPanel({
    super.key,
    required this.useCompactLayout,
    required this.showUserAvatar,
    required this.showUserName,
    required this.showCommentTime,
    required this.commentFontScale,
    required this.commentPreload,
    required this.commentAutoLoadAll,
    this.isChapterComments = true,
    required this.onLayoutChanged,
    required this.onShowAvatarChanged,
    required this.onShowUserNameChanged,
    required this.onShowCommentTimeChanged,
    required this.onFontScaleChanged,
    required this.onPreloadChanged,
    required this.onAutoLoadAllChanged,
  });

  @override
  State<CommentSettingsPanel> createState() => _CommentSettingsPanelState();
}

class _CommentSettingsPanelState extends State<CommentSettingsPanel> {
  late bool _useCompactLayout;
  late bool _showUserAvatar;
  late bool _showUserName;
  late bool _showCommentTime;
  late double _commentFontScale;
  late bool _commentPreload;
  late bool _commentAutoLoadAll;

  @override
  void initState() {
    super.initState();
    _useCompactLayout = widget.useCompactLayout;
    _showUserAvatar = widget.showUserAvatar;
    _showUserName = widget.showUserName;
    _showCommentTime = widget.showCommentTime;
    _commentFontScale = widget.commentFontScale;
    _commentPreload = widget.commentPreload;
    _commentAutoLoadAll = widget.commentAutoLoadAll;
  }

  Future<void> _editPreset(
    BuildContext context, {
    required PromptPreset preset,
    required bool isBuiltIn,
  }) async {
    final settings = AiSettings();
    final nameCtrl = TextEditingController(text: preset.name);
    final promptCtrl = TextEditingController(text: preset.prompt);
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBuiltIn ? '编辑内置提示词' : '编辑提示词'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: TextField(
                    controller: promptCtrl,
                    minLines: 6,
                    maxLines: 8,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: '提示词',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isBuiltIn)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'action': 'delete'}),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          if (isBuiltIn)
            TextButton(
              onPressed: () {
                final builtIn = AiSettings.builtInPresets
                    .where((p) => p.id == preset.id)
                    .firstOrNull;
                if (builtIn != null) {
                  nameCtrl.text = builtIn.name;
                  promptCtrl.text = builtIn.prompt;
                }
              },
              child: const Text('重置'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'name': nameCtrl.text,
              'prompt': promptCtrl.text,
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final action = result['action'];
    if (action == 'delete') {
      await settings.removePreset(preset.id);
    } else {
      await settings.updatePreset(
        preset.id,
        name: result['name']!.trim(),
        prompt: result['prompt']!.trim(),
      );
    }
  }

  Future<void> _addPreset(BuildContext context) async {
    final settings = AiSettings();
    final nameCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加提示词'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: TextField(
                    controller: promptCtrl,
                    minLines: 6,
                    maxLines: 8,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: '提示词',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty ||
                  promptCtrl.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, {
                'name': nameCtrl.text,
                'prompt': promptCtrl.text,
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null) {
      await settings.addPreset(
        result['name']!.trim(),
        result['prompt']!.trim(),
      );
    }
  }

  Widget _buildSectionHeader(String title, ColorScheme cs, TextTheme tt) {
    final line = Divider(
      height: 1,
      color: cs.outlineVariant.withValues(alpha: 0.5),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              title,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: line),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final defaultFontSizePx = _defaultCommentFontSizePx(
      tt,
      compact: _useCompactLayout,
    );
    final minFontSizePx = _commentFontMinPx(defaultFontSizePx);
    final maxFontSizePx = _commentFontMaxPx(defaultFontSizePx);
    final currentFontSizePx = _commentFontScaleToPx(
      defaultFontSizePx,
      _commentFontScale,
    ).clamp(minFontSizePx, maxFontSizePx);

    return Material(
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
              Text(
                '评论区设置',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (widget.isChapterComments) ...[
                _buildSectionHeader('布局', cs, tt),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.dashboard_outlined),
                        label: Text('紧凑布局'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_agenda_outlined),
                        label: Text('列表布局'),
                      ),
                    ],
                    selected: {_useCompactLayout},
                    onSelectionChanged: (values) {
                      final value = values.first;
                      setState(() => _useCompactLayout = value);
                      widget.onLayoutChanged(value);
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示头像'),
                value: _showUserAvatar,
                onChanged: (value) {
                  setState(() => _showUserAvatar = value);
                  widget.onShowAvatarChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示用户名'),
                value: _showUserName,
                onChanged: (value) {
                  setState(() => _showUserName = value);
                  widget.onShowUserNameChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示评论时间'),
                value: _showCommentTime,
                onChanged: (value) {
                  setState(() => _showCommentTime = value);
                  widget.onShowCommentTimeChanged(value);
                },
              ),
              if (widget.isChapterComments) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('预加载评论'),
                  subtitle: const Text('进入章节时提前加载评论并显示数量'),
                  value: _commentPreload,
                  onChanged: (value) {
                    setState(() => _commentPreload = value);
                    widget.onPreloadChanged(value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动加载全部评论'),
                  subtitle: const Text('打开评论区时自动加载所有评论'),
                  value: _commentAutoLoadAll,
                  onChanged: (value) {
                    setState(() => _commentAutoLoadAll = value);
                    widget.onAutoLoadAllChanged(value);
                  },
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('评论内容字体大小', style: tt.bodyMedium),
                  const Spacer(),
                  Text(
                    '${currentFontSizePx.round()} px',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: currentFontSizePx,
                min: minFontSizePx,
                max: maxFontSizePx,
                divisions: ((maxFontSizePx - minFontSizePx) / 1).round(),
                label: '${currentFontSizePx.round()} px',
                onChanged: (value) {
                  final nextScale = _commentFontPxToScale(
                    defaultFontSizePx,
                    value,
                  );
                  setState(() => _commentFontScale = nextScale);
                  widget.onFontScaleChanged(nextScale);
                },
              ),
              // AI 总结设置
              if (widget.isChapterComments)
                ListenableBuilder(
                  listenable: AiSettings(),
                  builder: (context, _) {
                    final zhipu = AiSettings();
                    final hasKey = zhipu.hasApiKey;
                    final enabled = zhipu.summaryEnabled;
                    final spoiler = zhipu.spoilerAnalysis;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('AI 总结', cs, tt),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('启用 AI 总结'),
                          subtitle: Text(
                            hasKey
                                ? (enabled ? '评论顶部显示 AI 总结按钮' : '未启用')
                                : '请先在「我的 → AI配置」中配置 API 密钥',
                            style: tt.bodySmall?.copyWith(
                              color: hasKey ? null : cs.error,
                            ),
                          ),
                          value: enabled && hasKey,
                          onChanged: hasKey
                              ? (v) => zhipu.setSummaryEnabled(v)
                              : null,
                        ),
                        if (enabled && hasKey) ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('折叠 AI 评论'),
                            subtitle: const Text('开启后 AI 评论默认折叠，生成中也保持折叠'),
                            value: zhipu.summaryCollapsed,
                            onChanged: (v) => zhipu.setSummaryCollapsed(v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('自动 AI 总结'),
                            subtitle: Text(
                              '评论数 ≥ ${zhipu.autoSummaryMin} 条时自动生成',
                            ),
                            value: zhipu.autoSummary,
                            onChanged: (v) => zhipu.setAutoSummary(v),
                          ),
                          if (zhipu.autoSummary)
                            Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('最少评论数', style: tt.bodySmall),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 64,
                                        child: TextFormField(
                                          initialValue: zhipu.autoSummaryMin
                                              .toString(),
                                          keyboardType: TextInputType.number,
                                          style: tt.bodySmall,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 6,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                          onFieldSubmitted: (v) {
                                            final n = int.tryParse(v);
                                            if (n != null && n > 0) {
                                              zhipu.setAutoSummaryMin(n);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text('调用时机', style: tt.bodySmall),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: double.infinity,
                                    child: SegmentedButton<AiAutoSummaryTiming>(
                                      segments: [
                                        const ButtonSegment(
                                          value: AiAutoSummaryTiming.onOpen,
                                          label: Text('打开评论区时'),
                                        ),
                                        ButtonSegment(
                                          value:
                                              AiAutoSummaryTiming.afterPreload,
                                          label: const Text('预加载完成后'),
                                          enabled: _commentPreload,
                                        ),
                                      ],
                                      selected: {
                                        _commentPreload
                                            ? zhipu.autoSummaryTiming
                                            : AiAutoSummaryTiming.onOpen,
                                      },
                                      onSelectionChanged: (values) {
                                        zhipu.setAutoSummaryTiming(
                                          values.first,
                                        );
                                      },
                                    ),
                                  ),
                                  if (!_commentPreload) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '选择“预加载完成后”需要先开启预加载评论。',
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('剧透分析'),
                            subtitle: const Text('开启后会在当前提示词后自动追加剧透分析要求'),
                            value: spoiler,
                            onChanged: (v) => zhipu.setSpoilerAnalysis(v),
                          ),
                          if (spoiler)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('打开剧透评论弹出提醒'),
                              value: zhipu.spoilerWarn,
                              onChanged: (v) => zhipu.setSpoilerWarn(v),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            '提示词预设',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          RadioGroup<String>(
                            groupValue: zhipu.activePresetId,
                            onChanged: (v) {
                              if (v != null) zhipu.setActivePreset(v);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final p in zhipu.presets)
                                  ListTile(
                                    contentPadding: const EdgeInsets.only(
                                      right: 8,
                                    ),
                                    leading: Radio<String>(value: p.id),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (p.isBuiltIn &&
                                            zhipu.isPresetModified(p.id))
                                          Icon(
                                            Icons.edit_note,
                                            size: 16,
                                            color: cs.primary,
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      p.prompt,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 20,
                                      ),
                                      tooltip: '编辑',
                                      onPressed: () => _editPreset(
                                        context,
                                        preset: p,
                                        isBuiltIn: p.isBuiltIn,
                                      ),
                                    ),
                                    onTap: () => zhipu.setActivePreset(p.id),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('添加提示词'),
                              onPressed: () => _addPreset(context),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
              _buildBlockedUsersSection(cs, tt),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedUsersSection(ColorScheme cs, TextTheme tt) {
    final user = UserManager();

    return ListenableBuilder(
      listenable: user,
      builder: (context, _) {
        final list = user.commentBlockedUsers;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('黑名单', cs, tt),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  '长按评论可选择「屏蔽用户」，被屏蔽的评论将不再显示。',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else ...[
              for (final raw in list)
                _BlockedUserTile(
                  rawKey: raw,
                  onRemove: () => user.unblockCommentUser(raw),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空黑名单'),
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  onPressed: () => user.clearCommentBlockedUsers(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  final String rawKey;
  final VoidCallback onRemove;

  const _BlockedUserTile({required this.rawKey, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sep = rawKey.indexOf('|');
    final userName = sep < 0 ? '' : rawKey.substring(sep + 1);
    final displayName = userName.isNotEmpty ? userName : '匿名用户';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: '移出黑名单',
        icon: const Icon(Icons.remove_circle_outline, size: 22),
        color: cs.error,
        onPressed: onRemove,
      ),
    );
  }
}
