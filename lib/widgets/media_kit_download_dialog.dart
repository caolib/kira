import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../utils/media_kit_native_loader.dart';
import '../utils/toast.dart';

/// Ensures media_kit is ready before opening the anime player.
///
/// On Android, prompts to download native libs on first use (GitHub or mirror).
/// Returns `false` if the user cancels or download fails.
Future<bool> ensureAnimePlayerReady(BuildContext context) async {
  final loader = MediaKitNativeLoader.instance;

  if (!loader.needsOnDemandDownload) {
    try {
      await loader.ensureInitialized();
      return true;
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.mediaKitInitFailed(e.toString()),
          isError: true,
        );
      }
      return false;
    }
  }

  if (await loader.isInstalled) {
    if (!context.mounted) return false;
    final ok = await _ensureInstalledWithProgress(context, loader);
    if (ok) return true;
    // Broken install — fall through to re-download.
  }

  if (!context.mounted) return false;

  final source = await showDialog<MediaKitDownloadSource>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _MediaKitDownloadConfirmDialog(),
  );
  if (source == null || !context.mounted) return false;

  final downloaded = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MediaKitDownloadProgressDialog(source: source),
  );
  return downloaded == true;
}

/// Shows a short non-dismissible dialog while System.load + JavaVM bind runs.
Future<bool> _ensureInstalledWithProgress(
  BuildContext context,
  MediaKitNativeLoader loader,
) async {
  if (loader.isInitialized) {
    return true;
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  var dialogShown = false;

  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      dialogShown = true;
      final l10n = AppLocalizations.of(ctx)!;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.mediaKitDownloadStageLoad)),
            ],
          ),
        ),
      );
    },
  );

  // Let the first dialog frame schedule before blocking on System.load.
  await Future<void>.delayed(Duration.zero);

  try {
    await loader.ensureInitialized();
    return true;
  } catch (e) {
    debugPrint('media_kit ensureInitialized failed: $e');
    return false;
  } finally {
    if (dialogShown && navigator.canPop()) {
      navigator.pop();
    }
    unawaited(dialogFuture.then((_) {}, onError: (_, _) {}));
  }
}

class _MediaKitDownloadConfirmDialog extends StatefulWidget {
  const _MediaKitDownloadConfirmDialog();

  @override
  State<_MediaKitDownloadConfirmDialog> createState() =>
      _MediaKitDownloadConfirmDialogState();
}

class _MediaKitDownloadConfirmDialogState
    extends State<_MediaKitDownloadConfirmDialog> {
  MediaKitDownloadSource _source = MediaKitDownloadSource.github;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mirrorPrefix = UserManager().updateMirrorPrefix;

    return AlertDialog(
      title: Text(l10n.mediaKitDownloadTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mediaKitDownloadMessage(
                MediaKitNativeLoader.approximateSizeLabel,
              ),
              style: tt.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.mediaKitDownloadSourceLabel,
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<MediaKitDownloadSource>(
              groupValue: _source,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _source = value);
              },
              child: Column(
                children: [
                  RadioListTile<MediaKitDownloadSource>(
                    value: MediaKitDownloadSource.github,
                    title: Text(l10n.mediaKitDownloadSourceGithub),
                    subtitle: Text(
                      l10n.mediaKitDownloadSourceGithubHint,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    secondary: SvgPicture.asset(
                      'assets/github.svg',
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(
                        cs.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<MediaKitDownloadSource>(
                    value: MediaKitDownloadSource.mirror,
                    title: Text(l10n.mediaKitDownloadSourceMirror),
                    subtitle: Text(
                      l10n.mediaKitDownloadSourceMirrorHint(mirrorPrefix),
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    secondary: Icon(Icons.public, color: cs.primary),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _source),
          child: Text(l10n.mediaKitDownloadConfirm),
        ),
      ],
    );
  }
}

class _MediaKitDownloadProgressDialog extends StatefulWidget {
  final MediaKitDownloadSource source;

  const _MediaKitDownloadProgressDialog({required this.source});

  @override
  State<_MediaKitDownloadProgressDialog> createState() =>
      _MediaKitDownloadProgressDialogState();
}

class _MediaKitDownloadProgressDialogState
    extends State<_MediaKitDownloadProgressDialog> {
  MediaKitDownloadCancelToken _cancelToken = MediaKitDownloadCancelToken();
  double? _fraction;
  String _stage = 'prepare';
  int _receivedBytes = 0;
  int? _totalBytes;
  String? _detail;
  String? _error;
  bool _finished = false;
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished || _error != null) return;
      setState(() => _elapsedSeconds += 1);
    });
    // Defer so the first frame paints before download work starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    if (!_cancelToken.isCancelled && !_finished) {
      _cancelToken.cancel('disposed');
    }
    super.dispose();
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context)!;
    _cancelToken = MediaKitDownloadCancelToken();
    setState(() {
      _error = null;
      _fraction = null;
      _stage = 'prepare';
      _receivedBytes = 0;
      _totalBytes = null;
      _detail = null;
      _elapsedSeconds = 0;
      _finished = false;
    });

    try {
      await MediaKitNativeLoader.instance.downloadAndInstall(
        source: widget.source,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _fraction = progress.fraction;
            _stage = progress.stage;
            _receivedBytes = progress.receivedBytes;
            _totalBytes = progress.totalBytes;
            _detail = progress.detail;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _finished = true;
        _fraction = 1;
        _stage = 'done';
        _detail = '完成';
      });
      Navigator.pop(context, true);
    } on MediaKitDownloadCancelled {
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      if (_cancelToken.isCancelled) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(l10n, e);
      });
    }
  }

  String _friendlyError(AppLocalizations l10n, Object e) {
    final text = e.toString();
    if (e is TimeoutException ||
        text.contains('Timeout') ||
        text.contains('超时')) {
      return l10n.mediaKitDownloadFailed(l10n.mediaKitDownloadTimeout);
    }
    if (e is SocketException ||
        text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Network is unreachable')) {
      return l10n.mediaKitDownloadFailed(l10n.mediaKitDownloadNetworkError);
    }
    if (e is HttpException || text.contains('HttpException')) {
      return l10n.mediaKitDownloadFailed(text);
    }
    return l10n.mediaKitDownloadFailed(text);
  }

  String _stageLabel(AppLocalizations l10n) {
    return switch (_stage) {
      'prepare' => l10n.mediaKitDownloadStagePrepare,
      'connect' => l10n.mediaKitDownloadStageConnect,
      'download' => l10n.mediaKitDownloadStageDownload,
      'verify' => l10n.mediaKitDownloadStageVerify,
      'extract' => l10n.mediaKitDownloadStageExtract,
      'load' => l10n.mediaKitDownloadStageLoad,
      'done' => l10n.mediaKitDownloadStageDone,
      _ => l10n.mediaKitDownloadStageDownload,
    };
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '$m分${s.toString().padLeft(2, '0')}秒';
    return '$s秒';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasError = _error != null;
    final total = _totalBytes;
    final bytesLine = total != null && total > 0
        ? l10n.mediaKitDownloadBytesProgress(
            _formatBytes(_receivedBytes),
            _formatBytes(total),
          )
        : (_receivedBytes > 0
              ? l10n.mediaKitDownloadBytesOnly(_formatBytes(_receivedBytes))
              : null);

    return AlertDialog(
      title: Text(
        hasError
            ? l10n.mediaKitDownloadFailedTitle
            : l10n.mediaKitDownloadingTitle,
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasError)
              Text(
                _error!,
                style: tt.bodyMedium?.copyWith(color: cs.error, height: 1.4),
              )
            else ...[
              Text(_stageLabel(l10n), style: tt.titleSmall),
              if (_detail != null && _detail!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _detail!,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              if (bytesLine != null) ...[
                const SizedBox(height: 6),
                Text(
                  bytesLine,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '已用时 ${_formatElapsed(_elapsedSeconds)}',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _fraction),
              if (_fraction != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${(_fraction! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (hasError) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(onPressed: _start, child: Text(l10n.retryButton)),
        ] else
          TextButton(
            onPressed: () {
              _cancelToken.cancel('user');
              Navigator.pop(context, false);
            },
            child: Text(l10n.cancelButton),
          ),
      ],
    );
  }
}
