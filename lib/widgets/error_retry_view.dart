import 'package:flutter/material.dart';

/// A centered error state with icon, message, and retry button.
///
/// Used across list/grid pages that fail to load data from the API.
/// Customizable icon, message, and retry action.
class ErrorRetryView extends StatelessWidget {
  final IconData icon;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const ErrorRetryView({
    super.key,
    this.icon = Icons.cloud_off,
    this.message = '加载失败',
    this.retryLabel = '重试',
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(message, style: tt.titleMedium),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}

/// A sliver version of [ErrorRetryView] for use inside [CustomScrollView].
class SliverErrorRetryView extends StatelessWidget {
  final IconData icon;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const SliverErrorRetryView({
    super.key,
    this.icon = Icons.cloud_off,
    this.message = '加载失败',
    this.retryLabel = '重试',
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
