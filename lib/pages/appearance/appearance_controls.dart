part of '../appearance_page.dart';

class _AppearanceSliderControl extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _AppearanceSliderControl({
    required this.icon,
    required this.title,
    required this.description,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colorScheme.onSurfaceVariant, size: 20),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 52,
                child: Text(
                  valueText,
                  textAlign: TextAlign.end,
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueText,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class _NavOrderDestination extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final BottomNavLabelMode labelMode;

  const _NavOrderDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.labelMode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final showUnderLabel = labelMode == BottomNavLabelMode.always;
    final showCapsuleLabel =
        labelMode == BottomNavLabelMode.selectedOnly && selected;

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 32),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.secondaryContainer
                        : Colors.transparent,
                    borderRadius: AppRadius.lgR,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: showCapsuleLabel ? 8 : 10,
                      vertical: 6,
                    ),
                    child: showCapsuleLabel
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(selectedIcon, color: foreground, size: 18),
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.labelSmall?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w600,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Icon(
                            selected ? selectedIcon : icon,
                            color: foreground,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ),
            if (showUnderLabel) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeColorTile extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeColorTile({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hex = _colorToHex(color);

    return Semantics(
      button: true,
      selected: selected,
      label: hex,
      child: Material(
        color: selected ? color.withValues(alpha: 0.14) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgR,
          side: BorderSide(
            color: selected ? color.withValues(alpha: 0.65) : cs.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: AppRadius.lgR,
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: AppRadius.smR,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String _formatRefreshRate(int refreshRate, AppLocalizations l10n) {
  return refreshRate == UserManager.defaultDisplayModeRefreshRate
      ? l10n.appearanceAutoSystem
      : '${refreshRate}Hz';
}

class _LogoOptionTile extends StatelessWidget {
  final String assetPath;
  final bool selected;
  final VoidCallback onTap;

  const _LogoOptionTile({
    required this.assetPath,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fileName = assetPath.split('/').last;

    return Semantics(
      button: true,
      selected: selected,
      label: fileName,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgR,
          side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: AppRadius.lgR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Image.asset(assetPath, width: 48, height: 48),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.check_circle,
                      size: 14,
                      color: cs.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
