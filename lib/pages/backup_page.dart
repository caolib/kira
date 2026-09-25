import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup/backup_category.dart';
import '../backup/backup_codec.dart';
import '../backup/backup_controller.dart';
import '../backup/backup_document.dart';
import '../backup/backup_error.dart';
import '../backup/backup_schedule.dart';
import '../backup/backup_scheduler.dart';
import '../backup/backup_settings.dart';
import '../backup/webdav_config.dart';
import '../l10n/app_localizations.dart';
import '../providers/backup_providers.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/toast.dart';
import '../widgets/error_retry_view.dart';
import 'backup/backup_content_controls.dart';
import 'backup/backup_labels.dart';
import 'backup/backup_password_dialog.dart';
import 'backup/backup_preview_dialog.dart';
import 'backup/backup_restore_dialog.dart';
import 'backup/webdav_connection_dialog.dart';
import 'backup/webdav_panel.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  late final BackupController _controller;
  late final BackupScheduler _scheduler;
  late final BackupSettings _settings;

  /// Every category is selected by default, for export and for the restore
  /// dialog: the「全选」row is what most users want, and both lists are still
  /// fully editable before anything is written.
  final _selected = BackupCategory.values.toSet();
  Map<BackupCategory, int>? _sizes;
  BackupSchedule _schedule = const BackupSchedule();
  WebDavConfig? _config;
  WebDavCredentials _credentials = const WebDavCredentials(
    username: '',
    password: '',
  );
  List<WebDavBackupEntry> _entries = [];
  String _password = '';
  bool _remember = false;
  bool _encrypted = true;
  bool _webDav = false;
  bool _webDavEnabled = false;
  bool _working = true;
  bool _listed = false;
  Object? _loadError;
  String? _listError;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(backupControllerProvider)..addListener(_onChanged);
    _scheduler = ref.read(backupSchedulerProvider);
    _settings = ref.read(backupSettingsProvider);
    unawaited(_loadSettings());
    unawaited(_loadSizes());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 定时备份也在跑同一个控制器，此时页面上的按钮一并禁用、显示其进度。
  bool get _busy => _working || _controller.busy;

  /// 加密开启时，定时备份必须有可用密码（记住的或本次运行内输入的），否则
  /// 每轮都只能跳过——这种情况不允许开启开关。
  bool get _scheduleReady =>
      !_encrypted || _password.isNotEmpty || _settings.sessionPassword != null;

  Future<void> _loadSettings() async {
    setState(() {
      _working = true;
      _loadError = null;
    });
    try {
      final data = await _settings.load();
      if (!mounted) return;
      _config = data.connection;
      _credentials = data.credentials;
      _webDavEnabled = data.webDavEnabled;
      _encrypted = data.encrypted;
      _password = data.rememberedPassword ?? '';
      _remember = data.rememberedPassword != null;
      _schedule = data.schedule;
    } catch (error) {
      _loadError = error;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Sizes are a preview: a failure only leaves the list without them, the
  /// export path reports the real error.
  Future<void> _loadSizes() async {
    try {
      final summaries = await _controller.measureCategories();
      if (!mounted) return;
      setState(() {
        _sizes = {
          for (final entry in summaries.entries)
            entry.key: entry.value.rawBytes,
        };
      });
    } catch (error) {
      // Leave [_sizes] unset; the list simply shows no sizes.
      _recordFailure(error);
    }
  }

  /// The toast is transient, so record the failing code as well — otherwise an
  /// unreproducible failure leaves nothing to look at. Only backup exceptions
  /// are recorded: they carry a code and never any payload.
  void _recordFailure(Object error, [StackTrace? stack]) {
    if (error is! SettingsBackupException && error is! WebDavException) return;
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: error is WebDavException ? 'backup.webdav' : 'backup.page',
      ),
    );
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error, stack) {
      if (mounted) {
        showToast(
          context,
          backupErrorMessage(error, AppLocalizations.of(context)!),
          isError:
              error is! SettingsBackupException ||
              error.code != SettingsBackupErrorCode.cancelled,
        );
      }
      _recordFailure(error, stack);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _toast(String message) {
    if (mounted) showToast(context, message);
  }

  Future<bool> _editPassword() async {
    final choice = await showDialog<BackupPasswordChoice>(
      context: context,
      builder: (_) =>
          BackupPasswordDialog(initialPassword: _password, remember: _remember),
    );
    if (choice == null) return false;
    await _settings.saveEncryption(
      encrypted: _encrypted,
      remember: choice.remember,
      password: choice.password,
    );
    if (!mounted) return false;
    setState(() {
      _password = choice.password;
      _remember = choice.remember;
    });
    // 密码刚变得可用，之前因缺密码跳过的定时备份可以重新评估了。
    _scheduler.poke();
    return true;
  }

  /// 不走 [_perform]：开关与间隔是逐键提交的，短暂置忙会让输入框失焦。
  Future<void> _updateSchedule(BackupSchedule schedule) async {
    setState(() => _schedule = schedule);
    try {
      await _settings.saveSchedule(schedule);
    } catch (error, stack) {
      if (mounted) {
        showToast(
          context,
          backupErrorMessage(error, AppLocalizations.of(context)!),
          isError: true,
        );
      }
      _recordFailure(error, stack);
      return;
    }
    // 开关或间隔刚变过，立刻按新节奏复查一次到期情况。
    _scheduler.poke();
  }

  Future<void> _configure() async {
    final choice = await showDialog<(WebDavConfig?, WebDavCredentials)>(
      context: context,
      builder: (_) =>
          WebDavConnectionDialog(config: _config, credentials: _credentials),
    );
    if (choice == null) return;
    final config = choice.$1;
    // 连接设置留空保存 = 清除：地址与账号密码一起删掉。
    if (config == null) {
      await _settings.clearConnection();
      if (!mounted) return;
      setState(() {
        _config = null;
        _credentials = const WebDavCredentials(username: '', password: '');
        _entries = [];
        _listed = false;
        _listError = null;
      });
      _toast(AppLocalizations.of(context)!.backupWebDavCleared);
      _scheduler.poke();
      return;
    }
    await _settings.saveConnection(config, choice.$2);
    if (!mounted) return;
    setState(() {
      _config = config;
      _credentials = choice.$2;
      _entries = [];
      _listed = false;
      _listError = null;
    });
  }

  Future<void> _toggleWebDav(bool value) async {
    setState(() => _webDavEnabled = value);
    try {
      await _settings.saveEnabled(value);
    } catch (error, stack) {
      if (!mounted) return;
      setState(() => _webDavEnabled = !value);
      showToast(
        context,
        backupErrorMessage(error, AppLocalizations.of(context)!),
        isError: true,
      );
      _recordFailure(error, stack);
      return;
    }
    // 关掉开关会取消已排期的定时器——没有这一步，关闭前武装的那一次仍会上传。
    if (value) {
      _scheduler.poke();
      if (_config != null) unawaited(_perform(_refreshRemote));
    } else {
      _scheduler.suspend();
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)!.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _export({required bool remote}) async {
    if (_encrypted && _password.isEmpty && !await _editPassword()) return;
    final prepared = await _controller.prepare(Set.of(_selected));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => BackupPreviewDialog(
        prepared: prepared,
        encrypted: _encrypted,
        actionLabel: remote ? l10n.backupUpload : l10n.backupSaveLocal,
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!_encrypted &&
        _selected.any((category) => category.isSensitive) &&
        !await _confirm(
          l10n.backupSensitiveWarningTitle,
          l10n.backupSensitiveWarning,
          l10n.backupAcceptRisk,
        )) {
      return;
    }
    final encoded = await _controller.encode(
      prepared,
      password: _encrypted ? _password : null,
    );
    if (!mounted) return;
    if (remote) {
      final entry = await _controller.upload(_config!, _credentials, encoded);
      if (!mounted) return;
      setState(() => _entries = [entry, ..._entries]);
      _toast(l10n.backupUploaded);
      await _refreshRemote();
    } else {
      final saved = await FilePicker.saveFile(
        fileName: BackupCodec.uniqueFileName(encoded.extension),
        bytes: encoded.bytes,
      );
      if (saved != null) _toast(l10n.backupSaved);
    }
  }

  Future<void> _importLocal() async {
    final file = await FilePicker.pickFile(
      dialogTitle: AppLocalizations.of(context)!.backupImportLocal,
    );
    if (file == null || !mounted) return;
    await _decodeAndRestore(await _controller.readLocal(file));
  }

  Future<void> _decodeAndRestore(Uint8List bytes) async {
    var password = _password;
    BackupDocument? document;
    while (document == null) {
      if (!mounted) return;
      if (BackupCodec.isEncrypted(bytes) && password.isEmpty) {
        final choice = await showDialog<BackupPasswordChoice>(
          context: context,
          builder: (_) => const BackupPasswordDialog(decrypting: true),
        );
        if (choice == null) return;
        password = choice.password;
      }
      try {
        document = await _controller.decode(bytes, password: password);
      } on SettingsBackupException catch (error) {
        if (error.code != SettingsBackupErrorCode.authenticationFailed) rethrow;
        if (!mounted) return;
        showToast(
          context,
          error.localizedMessage(AppLocalizations.of(context)!),
          isError: true,
        );
        password = '';
      }
    }
    if (!mounted) return;
    if (document.categories.isEmpty) {
      throw const SettingsBackupException(SettingsBackupErrorCode.noCategories);
    }
    // Nothing is displayed or written before decryption, decompression and
    // full format validation have all completed.
    final categories = await showDialog<Set<BackupCategory>>(
      context: context,
      builder: (_) => BackupRestoreDialog(document: document!),
    );
    if (categories == null || !mounted) return;
    await _controller.restore(document, categories);
    // The restored data replaces the local one, so the sizes changed too.
    await _loadSizes();
    if (mounted) _toast(AppLocalizations.of(context)!.backupRestored);
  }

  Future<void> _refreshRemote() async {
    try {
      final entries = await _controller.list(_config!, _credentials);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _listed = true;
        _listError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _listError = backupErrorMessage(
            error,
            AppLocalizations.of(context)!,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _deleteRemote(WebDavBackupEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirm(
      l10n.backupDeleteTitle,
      l10n.backupDeleteWarning(entry.name),
      l10n.deleteButton,
    )) {
      return;
    }
    await _controller.delete(_config!, _credentials, entry);
    if (!mounted) return;
    setState(() => _entries.removeWhere((item) => item.name == entry.name));
    _toast(l10n.backupDeleted);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(backupControllerProvider);
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.backupTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48 + AppSpacing.md),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(l10n.backupLocal),
                          icon: const Icon(Icons.folder_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(l10n.backupWebDav),
                          icon: const Icon(Icons.cloud_outlined),
                        ),
                      ],
                      selected: {_webDav},
                      onSelectionChanged: _busy
                          ? null
                          : (value) {
                              setState(() => _webDav = value.single);
                              // 切到 WebDAV 页签时自动拉取一次远端列表。
                              if (_webDav &&
                                  _webDavEnabled &&
                                  _config != null) {
                                unawaited(_perform(_refreshRemote));
                              }
                            },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _controller.busy
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: _controller.progress),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _controller.cancelling
                                  ? l10n.backupCancelling
                                  : backupOperationLabel(
                                      _controller.operation,
                                      l10n,
                                    ),
                            ),
                          ),
                          if (_controller.canCancel)
                            TextButton(
                              onPressed: _controller.cancelling
                                  ? null
                                  : _controller.cancel,
                              child: Text(l10n.cancelButton),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: _loadError != null
            ? ErrorRetryView(
                message: backupErrorMessage(_loadError!, l10n),
                onRetry: _loadSettings,
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      BackupContentControls(
                        selected: _selected,
                        sizes: _sizes,
                        enabled: !_busy,
                        encrypted: _encrypted,
                        passwordSet: _password.isNotEmpty,
                        passwordRemembered: _remember,
                        onSelect: (category, selected) => setState(() {
                          if (selected) {
                            _selected.add(category);
                          } else {
                            _selected.remove(category);
                          }
                        }),
                        onSelectAll: (value) => setState(() {
                          _selected.clear();
                          if (value) _selected.addAll(BackupCategory.values);
                        }),
                        onEncryptionChanged: (value) => _perform(() async {
                          await _settings.saveEncryption(
                            encrypted: value,
                            remember: _remember,
                            password: _password,
                          );
                          if (mounted) setState(() => _encrypted = value);
                        }),
                        onPassword: () => _perform(() async {
                          await _editPassword();
                        }),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      if (_webDav)
                        WebDavPanel(
                          config: _config,
                          entries: _entries,
                          enabled: _webDavEnabled,
                          interactive: !_busy,
                          canUpload: _selected.isNotEmpty,
                          listed: _listed,
                          schedule: _schedule,
                          scheduleReady: _scheduleReady,
                          scheduleHint: _encrypted && !_scheduleReady
                              ? l10n.backupSchedulePasswordRequired
                              : null,
                          error: _listError,
                          onToggle: _toggleWebDav,
                          onConfigure: () => _perform(_configure),
                          onTest: () => _perform(() async {
                            await _controller.test(_config!, _credentials);
                            _toast(l10n.backupTestSucceeded);
                          }),
                          onUpload: () => _perform(() => _export(remote: true)),
                          onRefresh: () => _perform(_refreshRemote),
                          onRestore: (entry) => _perform(() async {
                            final bytes = await _controller.download(
                              _config!,
                              _credentials,
                              entry,
                            );
                            await _decodeAndRestore(bytes);
                          }),
                          onDelete: (entry) =>
                              _perform(() => _deleteRemote(entry)),
                          onScheduleChanged: _updateSchedule,
                        )
                      else
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.md,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy || _selected.isEmpty
                                  ? null
                                  : () =>
                                        _perform(() => _export(remote: false)),
                              icon: const Icon(Icons.save_alt_rounded),
                              label: Text(l10n.backupSaveLocal),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _perform(_importLocal),
                              icon: const Icon(Icons.file_open_outlined),
                              label: Text(l10n.backupImportLocal),
                            ),
                          ],
                        ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
