import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/toast.dart';

class AppLogPage extends StatefulWidget {
  const AppLogPage({super.key, this.logger});

  final AppLogger? logger;

  @override
  State<AppLogPage> createState() => _AppLogPageState();
}

class _AppLogPageState extends State<AppLogPage> {
  late Future<List<AppLogEntry>> _entriesFuture;
  bool _copying = false;
  bool _clearing = false;
  bool _loggingEnabled = AppLogger.defaultLoggingEnabled;
  AppLogLevel _minimumLevel = AppLogger.defaultMinimumLevel;
  AppLogLevel? _levelFilter;

  AppLogger get _logger => widget.logger ?? AppLogger.instance;

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

  Future<void> _copyLogs() async {
    if (_copying) return;
    setState(() {
      _copying = true;
    });

    try {
      final text = await _logger.exportText();
      if (!mounted) return;
      if (text.trim().isEmpty) {
        showToast(context, '暂无错误日志', isError: true);
        return;
      }

      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        showToast(context, '日志已复制到剪贴板');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '复制失败：$e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _copying = false;
        });
      }
    }
  }

  Future<void> _clearLogs() async {
    if (_clearing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空错误日志'),
        content: const Text('确定要删除本地保存的错误日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
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
        showToast(context, '错误日志已清空');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '清空失败：$e', isError: true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('错误日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '复制日志',
            onPressed: _copying ? null : _copyLogs,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: '清空日志',
            onPressed: _clearing ? null : _clearLogs,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _LogSettingsPanel(
            loggingEnabled: _loggingEnabled,
            minimumLevel: _minimumLevel,
            onLoggingEnabledChanged: _setLoggingEnabled,
            onMinimumLevelChanged: _setMinimumLevel,
          ),
          _LevelFilterBar(
            filter: _levelFilter,
            onChanged: (level) => setState(() => _levelFilter = level),
          ),
          Expanded(
            child: FutureBuilder<List<AppLogEntry>>(
              future: _entriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final entries = snapshot.data ?? const <AppLogEntry>[];
                final filtered = _levelFilter == null
                    ? entries
                    : entries
                          .where((entry) => entry.level == _levelFilter)
                          .toList();
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
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            '暂无错误日志',
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
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
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

class _LogSettingsPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.fact_check_outlined),
              title: const Text('日志记录'),
              value: loggingEnabled,
              onChanged: onLoggingEnabledChanged,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: const Text('记录级别'),
              subtitle: Text(minimumLevel.thresholdLabel),
              trailing: DropdownButton<AppLogLevel>(
                value: minimumLevel,
                underline: const SizedBox.shrink(),
                onChanged: onMinimumLevelChanged,
                items: [
                  for (final level in AppLogLevel.values)
                    DropdownMenuItem(
                      value: level,
                      child: Text(level.thresholdLabel),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelFilterBar extends StatelessWidget {
  const _LevelFilterBar({required this.filter, required this.onChanged});

  final AppLogLevel? filter;
  final ValueChanged<AppLogLevel?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            _filterChip(context, '全部', null),
            const SizedBox(width: 8),
            for (final level in AppLogLevel.values) ...[
              _filterChip(context, level.displayName, level),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterChip(BuildContext context, String label, AppLogLevel? level) {
    final cs = Theme.of(context).colorScheme;
    final selected = filter == level;

    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onChanged(selected ? null : level),
      selectedColor: cs.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
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

  AppLogEntry get entry => widget.entry;

  Future<void> _copyEntry() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: entry.toPlainText()));
      if (mounted) {
        showToast(context, '日志已复制到剪贴板');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '复制失败：$e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _copying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final stackTrace = entry.stackTrace;

    return Card(
      color: cs.surfaceContainerLow,
      child: ExpansionTile(
        leading: Icon(
          _levelIcon(entry.level),
          color: _levelColor(cs, entry.level),
        ),
        title: Text(
          entry.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatLogTime(entry.timestamp)} · ${entry.level.displayName} · ${entry.source}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: '复制此日志',
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text('上下文', style: tt.labelLarge),
            ),
            const SizedBox(height: 8),
            for (final item in entry.context.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _LogTextBlock(text: '${item.key}: ${item.value}'),
              ),
            const SizedBox(height: 8),
          ],
          if (stackTrace != null && stackTrace.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('堆栈', style: tt.labelLarge),
            ),
            const SizedBox(height: 8),
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
        borderRadius: BorderRadius.circular(8),
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
    AppLogLevel.warning => cs.tertiary,
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
