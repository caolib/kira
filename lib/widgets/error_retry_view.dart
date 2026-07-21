import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// A centered error state with icon, message, and retry button.
///
/// Used across list/grid pages that fail to load data from the API.
/// Customizable icon, message, and retry action.
class ErrorRetryView extends StatelessWidget {
  final IconData icon;
  final String? message;
  final String? retryLabel;
  final VoidCallback onRetry;

  const ErrorRetryView({
    super.key,
    this.icon = Icons.cloud_off,
    this.message,
    this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final resolvedMessage = message ?? l10n.loadingFailed;
    final resolvedRetryLabel = retryLabel ?? l10n.retryButton;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: AppSpacing.lg),
          Text(resolvedMessage, style: tt.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(resolvedRetryLabel),
          ),
        ],
      ),
    );
  }
}

/// A sliver version of [ErrorRetryView] for use inside [CustomScrollView].
class SliverErrorRetryView extends StatelessWidget {
  final IconData icon;
  final String? message;
  final String? retryLabel;
  final VoidCallback onRetry;

  const SliverErrorRetryView({
    super.key,
    this.icon = Icons.cloud_off,
    this.message,
    this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: ErrorRetryView(
        icon: icon,
        message: message,
        retryLabel: retryLabel,
        onRetry: onRetry,
      ),
    );
  }
}
