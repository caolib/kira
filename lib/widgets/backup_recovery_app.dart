import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// Startup remains here if the journal cannot be restored. No preference
/// singleton or background writer starts against a half-restored database.
class BackupRecoveryApp extends StatefulWidget {
  final Future<void> Function() onRetry;

  const BackupRecoveryApp({super.key, required this.onRetry});

  @override
  State<BackupRecoveryApp> createState() => _BackupRecoveryAppState();
}

class _BackupRecoveryAppState extends State<BackupRecoveryApp> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } catch (_) {
      // Keep the recovery screen and encrypted journal intact; retrying after
      // unlocking secure storage/freeing space is safe and idempotent.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.backupRecoveryTitle)),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.backupRecoveryRequired),
                  const SizedBox(height: AppSpacing.lg),
                  if (_busy)
                    const CircularProgressIndicator()
                  else
                    FilledButton(
                      onPressed: _retry,
                      child: Text(l10n.retryButton),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
