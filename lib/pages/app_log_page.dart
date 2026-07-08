import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../l10n/app_localizations.dart';
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

  Future<void> _copyLogs() async {
    final l10n = AppLocalizations.of(context)!;
    if (_copying) return;
    setState(() {
      _copying = true;
    });

    try {
      final text = await _logger.exportText();
      if (!mounted) return;
      if (text.trim().isEmpty) {
        showToast(context, l10n.appLogEmpty, isError: true);
        return;
      }

      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        showToast(context, l10n.appLogCopied);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.appLogCopyFailed('$e'), isError: true);
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
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _LogSettingsPanel(
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
      appBar: AppBar(
        title: Text(l10n.errorLogTitle),
        actions: [
          IconButton(
            tooltip: l10n.settingsTooltip,
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _LogFilterPanel(
            controller: _searchController,
            levelFilter: _levelFilter,
            searchQuery: _searchQuery,
            copying: _copying,
            clearing: _clearing,
            onLevelChanged: (level) => setState(() => _levelFilter = level),
            onSearchChanged: (query) => setState(() => _searchQuery = query),
            onRefresh: _refresh,
            onCopy: _copyLogs,
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

                final entries = snapshot.data ?? const <AppLogEntry>[];
                final query = _searchQuery.trim().toLowerCase();
                final filtered = entries.where((entry) {
                  if (_levelFilter != null && entry.level != _levelFilter) {
                    return false;
                  }
                  if (query.isEmpty) return true;
                  return _entryMatches(entry, query, l10n);
                }).toList();
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

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(l10n.appLogSettingsTitle, style: tt.titleMedium),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            secondary: const Icon(Icons.fact_check_outlined),
            title: Text(l10n.appLogRecordLogs),
            value: _loggingEnabled,
            onChanged: (value) {
              setState(() => _loggingEnabled = value);
              widget.onLoggingEnabledChanged(value);
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.tune_rounded),
            title: Text(l10n.appLogLevel),
            trailing: DropdownButton<AppLogLevel>(
              value: _minimumLevel,
              underline: const SizedBox.shrink(),
              onChanged: (level) {
                if (level == null || level == _minimumLevel) return;
                setState(() => _minimumLevel = level);
                widget.onMinimumLevelChanged(level);
              },
              items: [
                for (final level in AppLogLevel.values)
                  DropdownMenuItem(
                    value: level,
                    child: _FilterItem(
                      icon: _levelIcon(level),
                      color: _levelColor(Theme.of(context).colorScheme, level),
                      label: level.displayName(l10n),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
    required this.onRefresh,
    required this.onCopy,
    required this.onClear,
    this.copying = false,
    this.clearing = false,
  });

  final TextEditingController controller;
  final AppLogLevel? levelFilter;
  final String searchQuery;
  final ValueChanged<AppLogLevel?> onLevelChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final VoidCallback onCopy;
  final VoidCallback onClear;
  final bool copying;
  final bool clearing;

  static const _allValue = #all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final currentValue = levelFilter ?? _allValue;

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
                hintText: l10n.appLogSearchHint,
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: l10n.refreshButton,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: l10n.chapterCommentsCopyLog,
                  onPressed: copying ? null : onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
                IconButton(
                  tooltip: l10n.appLogClearLogsTooltip,
                  onPressed: clearing ? null : onClear,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const Spacer(),
                DropdownButton<Object>(
                  value: currentValue,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) {
                    if (value == _allValue) {
                      onLevelChanged(null);
                    } else if (value is AppLogLevel) {
                      onLevelChanged(value);
                    }
                  },
                  items: [
                    DropdownMenuItem<Object>(
                      value: _allValue,
                      child: _FilterItem(
                        icon: Icons.layers_rounded,
                        color: cs.onSurfaceVariant,
                        label: l10n.appLogAllLevels,
                      ),
                    ),
                    for (final level in AppLogLevel.values)
                      DropdownMenuItem<Object>(
                        value: level,
                        child: _FilterItem(
                          icon: _levelIcon(level),
                          color: _levelColor(cs, level),
                          label: level.displayName(l10n),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterItem extends StatelessWidget {
  const _FilterItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color)),
      ],
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l10n.appLogContextTitle, style: tt.labelLarge),
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
              child: Text(l10n.appLogStackTitle, style: tt.labelLarge),
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
