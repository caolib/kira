import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/toast.dart';
import '../widgets/app_sheet.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/select_tile.dart';
import '../widgets/settings_section.dart';

class AppLogPage extends StatefulWidget {
  const AppLogPage({super.key, this.logger});

  final AppLogger? logger;

  @override
  State<AppLogPage> createState() => _AppLogPageState();
}

class _AppLogPageState extends State<AppLogPage> {
  late Future<List<AppLogEntry>> _entriesFuture;
  bool _exporting = false;
  bool _clearing = false;
  bool _loggingEnabled = AppLogger.defaultLoggingEnabled;
  AppLogLevel _minimumLevel = AppLogger.defaultMinimumLevel;
  AppLogLevel? _levelFilter;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  AppLogger get _logger => widget.logger ?? AppLogger.instance;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loggingEnabled = _logger.loggingEnabled;
    _minimumLevel = _logger.minimumLevel;
    _entriesFuture = _logger.readEntries();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    await _logger.init();
    if (!mounted) return;
    setState(() {
      _loggingEnabled = _logger.loggingEnabled;
      _minimumLevel = _logger.minimumLevel;
    });
  }

  Future<void> _refresh() async {
    final future = _logger.readEntries();
    setState(() {
      _entriesFuture = future;
    });
    await future;
  }

  /// 目录初始化失败后的重试：先让 logger 重新初始化，再重新读取。
  Future<void> _retry() async {
    await _logger.retryInit();
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _exportLogs() async {
    final l10n = AppLocalizations.of(context)!;
    if (_exporting) return;
    setState(() {
      _exporting = true;
    });

    try {
      final text = await _logger.exportText();
      if (!mounted) return;
      if (text.trim().isEmpty) {
        showToast(context, l10n.appLogEmpty, isError: true);
        return;
      }

      final saved = await FilePicker.saveFile(
        fileName: _exportFileName(),
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
      );
      if (saved != null && mounted) {
        showToast(context, l10n.appLogExported);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.appLogExportFailed('$e'), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  static String _exportFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'kira_logs_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
  }

  Future<void> _clearLogs() async {
    final l10n = AppLocalizations.of(context)!;
    if (_clearing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.appLogClearTitle),
        content: Text(l10n.appLogClearContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.cacheClearButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _clearing = true;
    });
    try {
      await _logger.clear();
      await _refresh();
      if (mounted) {
        showToast(context, l10n.appLogCleared);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.appLogClearFailed('$e'), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
        });
      }
    }
  }

  Future<void> _setLoggingEnabled(bool enabled) async {
    setState(() {
      _loggingEnabled = enabled;
    });
    await _logger.setLoggingEnabled(enabled);
  }

  Future<void> _setMinimumLevel(AppLogLevel? level) async {
    if (level == null || level == _minimumLevel) return;
    setState(() {
      _minimumLevel = level;
    });
    await _logger.setMinimumLevel(level);
  }

  void _showSettings(BuildContext context) {
    showAppSheet<void>(
      context,
      maxHeightFactor: 0.9,
      child: _LogSettingsPanel(
        loggingEnabled: _loggingEnabled,
        minimumLevel: _minimumLevel,
        onLoggingEnabledChanged: _setLoggingEnabled,
        onMinimumLevelChanged: (level) {
          _setMinimumLevel(level);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.errorLogTitle)),
      body: Column(
        children: [
          _LogFilterPanel(
            controller: _searchController,
            levelFilter: _levelFilter,
            searchQuery: _searchQuery,
            exporting: _exporting,
            clearing: _clearing,
            onLevelChanged: (level) => setState(() => _levelFilter = level),
            onSearchChanged: (query) => setState(() => _searchQuery = query),
            onSettings: () => _showSettings(context),
            onRefresh: _refresh,
            onExport: _exportLogs,
            onClear: _clearLogs,
          ),
          Expanded(
            child: FutureBuilder<List<AppLogEntry>>(
              future: _entriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: ExpressiveLoadingIndicator());
                }

                // 读取失败必须与「没有日志」区分开：否则目录不可用会被当成
                // 一切正常，用户拿不到任何可提供的证据。
                if (snapshot.hasError) {
                  return ErrorRetryView(
                    message: '${snapshot.error}',
                    onRetry: () => unawaited(_retry()),
                  );
                }

                final entries = snapshot.data ?? const <AppLogEntry>[];
                final query = _searchQuery.trim().toLowerCase();
                final filtered = entries.where((entry) {
                  if (_levelFilter != null && entry.level != _levelFilter) {
                    return false;
                  }
                  if (query.isEmpty) return true;
                  return _entryMatches(entry, query, l10n);
                }).toList();

                // 关闭记录时不能跟平时长得一样：否则用户会把「没开记录」看成
                // 「没有出错」，反而拿不到本该留下的证据。已有记录仍然可读、
                // 可导出，所以只在完全没内容时用整屏空态。
                if (!_loggingEnabled && entries.isEmpty) {
                  return _LogDisabledView(
                    onEnable: () => unawaited(_setLoggingEnabled(true)),
                  );
                }

                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 96),
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Center(
                          child: Text(
                            l10n.appLogEmpty,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    // 关闭记录但仍有历史记录时，先给一条提示再列出来。
                    itemCount: filtered.length + (_loggingEnabled ? 0 : 1),
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      if (!_loggingEnabled && index == 0) {
                        return _LogDisabledBanner(
                          onEnable: () => unawaited(_setLoggingEnabled(true)),
                        );
                      }
                      final entry = filtered[index - (_loggingEnabled ? 0 : 1)];
                      return _LogEntryCard(entry: entry);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogSettingsPanel extends StatefulWidget {
  const _LogSettingsPanel({
    required this.loggingEnabled,
    required this.minimumLevel,
    required this.onLoggingEnabledChanged,
    required this.onMinimumLevelChanged,
  });

  final bool loggingEnabled;
  final AppLogLevel minimumLevel;
  final ValueChanged<bool> onLoggingEnabledChanged;
  final ValueChanged<AppLogLevel?> onMinimumLevelChanged;

  @override
  State<_LogSettingsPanel> createState() => _LogSettingsPanelState();
}

class _LogSettingsPanelState extends State<_LogSettingsPanel> {
  late bool _loggingEnabled;
  late AppLogLevel _minimumLevel;

  @override
  void initState() {
    super.initState();
    _loggingEnabled = widget.loggingEnabled;
    _minimumLevel = widget.minimumLevel;
  }

  @override
  void didUpdateWidget(covariant _LogSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loggingEnabled != widget.loggingEnabled) {
      _loggingEnabled = widget.loggingEnabled;
    }
    if (oldWidget.minimumLevel != widget.minimumLevel) {
      _minimumLevel = widget.minimumLevel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.appLogSettingsTitle, style: tt.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          SettingsSection(
            key: const ValueKey('log-recording-settings-card'),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.fact_check_outlined),
                  title: Text(l10n.appLogRecordLogs),
                  value: _loggingEnabled,
                  onChanged: (value) {
                    setState(() => _loggingEnabled = value);
                    widget.onLoggingEnabledChanged(value);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_rounded),
                  title: Text(l10n.appLogLevel),
                  trailing: SelectTile<AppLogLevel>(
                    value: _minimumLevel,
                    foregroundColor: _levelColor(
                      Theme.of(context).colorScheme,
                      _minimumLevel,
                    ),
                    leadingIcon: _levelIcon(_minimumLevel),
                    items: [
                      for (final level in AppLogLevel.values)
                        SelectItem(
                          level,
                          level.displayName(l10n),
                          icon: _levelIcon(level),
                          color: _levelColor(
                            Theme.of(context).colorScheme,
                            level,
                          ),
                        ),
                    ],
                    onChanged: (level) {
                      if (level == _minimumLevel) return;
                      setState(() => _minimumLevel = level);
                      widget.onMinimumLevelChanged(level);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogFilterPanel extends StatelessWidget {
  const _LogFilterPanel({
    required this.controller,
    required this.levelFilter,
    required this.searchQuery,
    required this.onLevelChanged,
    required this.onSearchChanged,
    required this.onSettings,
    required this.onRefresh,
    required this.onExport,
    required this.onClear,
    this.exporting = false,
    this.clearing = false,
  });

  final TextEditingController controller;
  final AppLogLevel? levelFilter;
  final String searchQuery;
  final ValueChanged<AppLogLevel?> onLevelChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSettings;
  final VoidCallback onRefresh;
  final VoidCallback onExport;
  final VoidCallback onClear;
  final bool exporting;
  final bool clearing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Column(
          children: [
            TextField(
              controller: controller,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.aiConfigClear,
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          controller.clear();
                          onSearchChanged('');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                IconButton(
                  tooltip: l10n.settingsTooltip,
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_rounded),
                ),
                IconButton(
                  tooltip: l10n.refreshButton,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: l10n.appLogExportTooltip,
                  onPressed: exporting ? null : onExport,
                  icon: const Icon(Icons.save_alt_rounded),
                ),
                IconButton(
                  tooltip: l10n.appLogClearLogsTooltip,
                  onPressed: clearing ? null : onClear,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const Spacer(),
                // 等级沿用卡片图标那套颜色，菜单项与胶囊保持一致。
                SelectTile<AppLogLevel?>(
                  value: levelFilter,
                  foregroundColor: levelFilter == null
                      ? cs.onSurfaceVariant
                      : _levelColor(cs, levelFilter!),
                  leadingIcon: levelFilter == null
                      ? Icons.layers_rounded
                      : _levelIcon(levelFilter!),
                  items: [
                    SelectItem(
                      null,
                      l10n.appLogAllLevels,
                      icon: Icons.layers_rounded,
                    ),
                    for (final level in AppLogLevel.values)
                      SelectItem(
                        level,
                        level.displayName(l10n),
                        icon: _levelIcon(level),
                        color: _levelColor(cs, level),
                      ),
                  ],
                  onChanged: onLevelChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 记录已关闭时的空态：一眼看出是「没在记」而不是「没出错」。
class _LogDisabledView extends StatelessWidget {
  const _LogDisabledView({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_outlined, size: 48, color: cs.outline),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.appLogDisabledTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonal(
              onPressed: onEnable,
              child: Text(l10n.appLogRecordLogs),
            ),
          ],
        ),
      ),
    );
  }
}

/// 记录已关闭但仍有历史记录：列表顶部提示，不遮挡已有内容。
class _LogDisabledBanner extends StatelessWidget {
  const _LogDisabledBanner({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 18, color: cs.outline),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.appLogDisabledTitle,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: onEnable, child: Text(l10n.appLogRecordLogs)),
        ],
      ),
    );
  }
}

class _LogEntryCard extends StatefulWidget {
  const _LogEntryCard({required this.entry});

  final AppLogEntry entry;

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _copying = false;
  bool _expanded = false;

  AppLogEntry get entry => widget.entry;

  Future<void> _copyEntry() async {
    final l10n = AppLocalizations.of(context)!;
    if (_copying) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: entry.toPlainText()));
      if (mounted) {
        showToast(context, l10n.appLogCopied);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.appLogCopyFailed('$e'), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _copying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final stackTrace = entry.stackTrace;

    return Card(
      color: cs.surfaceBright,
      child: ExpansionTile(
        leading: Icon(
          _levelIcon(entry.level),
          color: _levelColor(cs, entry.level),
        ),
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        title: Text(
          entry.message,
          // 展开后不再截断：长异常直接看全文，不必再去翻导出文件。
          maxLines: _expanded ? null : 2,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            color:
                (entry.level == AppLogLevel.warning ||
                    entry.level == AppLogLevel.error)
                ? _levelColor(cs, entry.level)
                : null,
          ),
        ),
        subtitle: Text(
          '${_formatLogTime(entry.timestamp)} · ${entry.level.displayName(l10n)} · ${entry.source}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: l10n.appLogCopyThisLogTooltip,
              onPressed: _copying ? null : _copyEntry,
              icon: _copying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.copy_rounded, size: 20),
            ),
          ),
          if (entry.context.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l10n.appLogContextTitle, style: tt.labelLarge),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final item in entry.context.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _LogTextBlock(text: '${item.key}: ${item.value}'),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (stackTrace != null && stackTrace.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l10n.appLogStackTitle, style: tt.labelLarge),
            ),
            const SizedBox(height: AppSpacing.sm),
            _LogTextBlock(text: stackTrace),
          ],
        ],
      ),
    );
  }
}

class _LogTextBlock extends StatelessWidget {
  const _LogTextBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: AppRadius.smR,
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

IconData _levelIcon(AppLogLevel level) {
  return switch (level) {
    AppLogLevel.debug => Icons.bug_report_outlined,
    AppLogLevel.info => Icons.info_outline_rounded,
    AppLogLevel.warning => Icons.warning_amber_rounded,
    AppLogLevel.error => Icons.error_outline_rounded,
  };
}

Color _levelColor(ColorScheme cs, AppLogLevel level) {
  return switch (level) {
    AppLogLevel.debug => cs.onSurfaceVariant,
    AppLogLevel.info => cs.primary,
    AppLogLevel.warning => Colors.amber.shade700,
    AppLogLevel.error => cs.error,
  };
}

String _formatLogTime(DateTime time) {
  final local = time.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

bool _entryMatches(AppLogEntry entry, String query, AppLocalizations l10n) {
  final lower = query.toLowerCase();
  bool contains(String? text) =>
      text != null && text.toLowerCase().contains(lower);

  if (contains(entry.message) ||
      contains(entry.source) ||
      contains(entry.level.idLabel) ||
      contains(entry.level.displayName(l10n)) ||
      contains(entry.stackTrace)) {
    return true;
  }
  for (final item in entry.context.entries) {
    if (contains(item.key) || contains(item.value)) return true;
  }
  return false;
}
