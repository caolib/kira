import 'package:flutter/material.dart';

import '../theme/app_icon_sizes.dart';

/// Shared cover-image placeholder / error tile.
///
/// Four call sites used to hand-build the same
/// `surfaceContainerHighest + centered icon` box; keep it here so every cover
/// that fails to load looks identical.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key, this.isError = false});

  const CoverPlaceholder.error({super.key}) : isError = true;

  final bool isError;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          isError ? Icons.broken_image_outlined : Icons.image_outlined,
          color: cs.onSurfaceVariant,
          size: AppIconSize.placeholder,
        ),
      ),
    );
  }
}
