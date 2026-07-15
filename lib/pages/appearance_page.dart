import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:system_fonts/system_fonts.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show isDesktop;
import '../models/app_theme_option.dart';
import '../models/user_manager.dart';
import '../utils/display_mode_preference.dart';
import '../utils/font_manager.dart';
import '../utils/toast.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  final _user = UserManager();

  static const _navMeta = {
    'comic': (Icons.menu_book_outlined, Icons.menu_book),
    'anime': (Icons.movie_outlined, Icons.movie),
    'search': (Icons.search_outlined, Icons.search),
    'bookshelf': (Icons.bookmark_border, Icons.bookmark),
    'profile': (Icons.person_outline, Icons.person),
  };

  String _navLabel(String key, AppLocalizations l10n) => switch (key) {
    'comic' => l10n.comicTabLabel,
    'anime' => l10n.animeTabLabel,
    'search' => l10n.searchTabLabel,
    'bookshelf' => l10n.bookshelfTabLabel,
    'profile' => l10n.profileTabLabel,
    _ => key,
  };

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _switchLogo(int index) async {
    if (_user.logoIndex == index) return;
    await _user.setLogoIndex(index);
    if (!mounted) return;
    if (Platform.isAndroid || Platform.isIOS) {
      showToast(context, AppLocalizations.of(context)!.appearanceLogoChanged);
    }
  }

  Future<void> _showDisplayModeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DisplayModeSheet(user: _user),
    );
  }

  Future<void> _showBottomNavLabelModeSheet(AppLocalizations l10n) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: RadioGroup<BottomNavLabelMode>(
            groupValue: _user.bottomNavLabelMode,
            onChanged: (value) {
              if (value == null) return;
              _user.setBottomNavLabelMode(value);
              Navigator.of(sheetContext).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in BottomNavLabelMode.values)
                  RadioListTile<BottomNavLabelMode>(
                    value: mode,
                    title: Text(_bottomNavLabelModeLabel(mode, l10n)),
                    subtitle: Text(_bottomNavLabelModeDesc(mode, l10n)),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  String _bottomNavLabelModeLabel(
    BottomNavLabelMode mode,
    AppLocalizations l10n,
  ) => switch (mode) {
    BottomNavLabelMode.selectedOnly =>
      l10n.appearanceBottomNavLabelModeSelectedOnly,
    BottomNavLabelMode.hidden => l10n.appearanceBottomNavLabelModeHidden,
    BottomNavLabelMode.always => l10n.appearanceBottomNavLabelModeAlways,
  };

  String _bottomNavLabelModeDesc(
    BottomNavLabelMode mode,
    AppLocalizations l10n,
  ) => switch (mode) {
    BottomNavLabelMode.selectedOnly =>
      l10n.appearanceBottomNavLabelModeSelectedOnlyDesc,
    BottomNavLabelMode.hidden => l10n.appearanceBottomNavLabelModeHiddenDesc,
    BottomNavLabelMode.always => l10n.appearanceBottomNavLabelModeAlwaysDesc,
  };

  /// Give the selected capsule a bit more room so icon+label doesn't overflow
  /// the equally-split preview slots.
  List<double> _navPreviewItemWidths({
    required double availableWidth,
    required int itemCount,
    required int selectedIndex,
    required BottomNavLabelMode labelMode,
  }) {
    if (itemCount <= 0) return const [];
    final equal = availableWidth / itemCount;
    if (labelMode != BottomNavLabelMode.selectedOnly ||
        selectedIndex < 0 ||
        selectedIndex >= itemCount ||
        equal >= 72) {
      return List<double>.filled(itemCount, equal);
    }

    final selectedWidth = (equal + 28).clamp(equal, availableWidth * 0.34);
    final remaining = availableWidth - selectedWidth;
    final otherWidth = remaining / (itemCount - 1);
    return [
      for (var i = 0; i < itemCount; i++)
        i == selectedIndex ? selectedWidth.toDouble() : otherWidth,
    ];
  }

  Future<void> _pickCustomThemeColor() async {
    var selectedColor = _user.customThemeColor;
    final l10n = AppLocalizations.of(context)!;
    final didSelectColor =
        await ColorPicker(
          color: selectedColor,
          onColorChanged: (color) => selectedColor = color,
          pickersEnabled: const <ColorPickerType, bool>{
            ColorPickerType.both: false,
            ColorPickerType.primary: false,
            ColorPickerType.accent: false,
            ColorPickerType.bw: false,
            ColorPickerType.custom: false,
            ColorPickerType.wheel: true,
          },
          enableShadesSelection: false,
          showColorCode: true,
          colorCodeHasColor: true,
          showEditIconButton: true,
          wheelDiameter: 220,
          wheelWidth: 20,
          wheelSquareBorderRadius: 12,
          wheelHasBorder: true,
          heading: Text(l10n.appearanceColorPickerHeading),
          wheelSubheading: Text(l10n.appearanceColorPickerSubheading),
          borderRadius: 12,
        ).showPickerDialog(
          context,
          constraints: const BoxConstraints(maxWidth: 460),
        );

    if (!didSelectColor) return;

    await _user.setCustomThemeColor(selectedColor);
    if (mounted) {
      showToast(
        context,
        l10n.appearanceThemeColorUpdated(_colorToHex(selectedColor)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectedVariant = _user.themeVariantOption;
    final coverBrightnessPercent = (_user.darkModeCoverBrightness * 100)
        .round();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appearanceTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Card(
            color: cs.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.text_fields_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  title: Text(l10n.appearanceBottomNavLabelMode),
                  subtitle: Text(
                    _bottomNavLabelModeLabel(_user.bottomNavLabelMode, l10n),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showBottomNavLabelModeSheet(l10n),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.swap_vert,
                          color: cs.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.appearanceNavOrder,
                              style: tt.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.appearanceNavOrderDragHint,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height:
                      _user.bottomNavLabelMode == BottomNavLabelMode.always
                      ? 80
                      : 56,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemCount = _user.navOrder.length;
                      final widths = _navPreviewItemWidths(
                        availableWidth: constraints.maxWidth,
                        itemCount: itemCount,
                        selectedIndex: _user.navOrder.indexOf(
                          _user.lastNavKey,
                        ),
                        labelMode: _user.bottomNavLabelMode,
                      );

                      return ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        padding: EdgeInsets.zero,
                        itemCount: itemCount,
                        onReorderItem: (oldIndex, newIndex) {
                          final order = List<String>.of(_user.navOrder);
                          final item = order.removeAt(oldIndex);
                          order.insert(newIndex, item);
                          _user.setNavOrder(order);
                        },
                        itemBuilder: (context, index) {
                          final key = _user.navOrder[index];
                          final meta = _navMeta[key]!;
                          return SizedBox(
                            key: ValueKey(key),
                            width: widths[index],
                            child: ReorderableDragStartListener(
                              index: index,
                              child: _NavOrderDestination(
                                icon: meta.$1,
                                selectedIcon: meta.$2,
                                label: _navLabel(key, l10n),
                                selected: key == _user.lastNavKey,
                                labelMode: _user.bottomNavLabelMode,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          if (isDesktop) ...[
            const SizedBox(height: 8),
            _DesktopFontCard(user: _user),
          ],
          const SizedBox(height: 8),
          _AppFontCard(user: _user),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.switch_account_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 16),
                      Text(l10n.appearanceAppIcon),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.appearanceAppIconRestartHint,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < UserManager.appLogoPaths.length; i++)
                        _LogoOptionTile(
                          assetPath: UserManager.appLogoPaths[i],
                          selected: _user.logoIndex == i,
                          onTap: () => _switchLogo(i),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (DisplayModePreference.isSupportedPlatform) ...[
            const SizedBox(height: 8),
            Card(
              color: cs.surfaceContainerLow,
              child: ListTile(
                leading: Icon(
                  Icons.monitor_heart_outlined,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(l10n.appearanceRefreshRateTitle),
                trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                onTap: _showDisplayModeSheet,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.brightness_6, color: cs.onSurfaceVariant),
                      const SizedBox(width: 16),
                      Text(l10n.appearanceThemeMode),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.settings_brightness),
                          label: Text(l10n.appearanceSystemMode),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: const Icon(Icons.light_mode),
                          label: Text(l10n.appearanceLightMode),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: const Icon(Icons.dark_mode),
                          label: Text(l10n.appearanceDarkMode),
                        ),
                      ],
                      selected: {_user.themeMode},
                      onSelectionChanged: (v) => _user.setThemeMode(v.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.brightness_low_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 16),
                      Text(l10n.appearanceDarkCoverBrightness),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.appearanceDarkCoverBrightnessDesc,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _user.darkModeCoverBrightness,
                          min: UserManager.minDarkModeCoverBrightness,
                          divisions:
                              ((UserManager.maxDarkModeCoverBrightness -
                                          UserManager
                                              .minDarkModeCoverBrightness) /
                                      0.05)
                                  .round(),
                          label: '$coverBrightnessPercent%',
                          onChanged: (value) {
                            _user.setDarkModeCoverBrightness(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '$coverBrightnessPercent%',
                          textAlign: TextAlign.end,
                          style: tt.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: cs.onSurfaceVariant),
                      const SizedBox(width: 16),
                      Text(l10n.appearanceThemeStyle),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.appearanceCurrentStyle(
                      selectedVariant.localizedLabel(l10n),
                      selectedVariant.localizedDescription(l10n),
                    ),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in appThemeVariantOptions)
                        Tooltip(
                          message: option.localizedDescription(l10n),
                          child: ChoiceChip(
                            label: Text(option.localizedLabel(l10n)),
                            selected: _user.themeVariant == option.variant,
                            onSelected: (_) =>
                                _user.setThemeVariant(option.variant),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.appearanceThemeColor,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.appearanceThemeColorDesc,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in appThemeOptions)
                        _ThemeColorTile(
                          color: option.seedColor,
                          selected: _user.themeColor == option.id,
                          onTap: () => _user.setThemeColor(option.id),
                        ),
                      _ThemeColorTile(
                        color: _user.customThemeColor,
                        selected: _user.themeColor == customThemeOptionId,
                        onTap: _pickCustomThemeColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
                    borderRadius: BorderRadius.circular(16),
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
                              Icon(
                                selectedIcon,
                                color: foreground,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
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
              const SizedBox(height: 4),
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

class _DisplayModeSheet extends StatefulWidget {
  final UserManager user;

  const _DisplayModeSheet({required this.user});

  @override
  State<_DisplayModeSheet> createState() => _DisplayModeSheetState();
}

class _DisplayModeSheetState extends State<_DisplayModeSheet> {
  late Future<DisplayModeData> _future;
  int? _applyingRate;

  @override
  void initState() {
    super.initState();
    _future = DisplayModePreference.load();
  }

  Future<void> _selectRefreshRate(int refreshRate, DisplayModeData data) async {
    if (_applyingRate != null) return;

    setState(() => _applyingRate = refreshRate);
    await widget.user.setDisplayModeRefreshRate(refreshRate);
    final applied = await DisplayModePreference.applyRefreshRate(
      refreshRate,
      modes: data.modes,
      active: data.active,
    );

    if (!mounted) return;
    setState(() => _applyingRate = null);
    final l10n = AppLocalizations.of(context)!;
    showToast(
      context,
      applied
          ? l10n.appearanceRefreshRateRequested(
              _formatRefreshRate(refreshRate, l10n),
            )
          : l10n.appearanceRefreshRateSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: FutureBuilder<DisplayModeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 220,
              child: Center(child: ExpressiveLoadingIndicator()),
            );
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.appearanceRefreshRateTitle,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.appearanceRefreshRateLoadFailed(
                      (snapshot.error ?? l10n.appearanceUnknownError)
                          .toString(),
                    ),
                    style: tt.bodyMedium?.copyWith(color: cs.error),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final currentRate = widget.user.displayModeRefreshRate;
          final activeRate = data.active.refreshRate.round();
          final rates = DisplayModePreference.refreshRates(data.modes);
          final isApplying = _applyingRate != null;

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.appearanceRefreshRateTitle,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: RadioGroup<int>(
                      groupValue: currentRate,
                      onChanged: (value) {
                        if (isApplying || value == null) return;
                        _selectRefreshRate(value, data);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            value: UserManager.defaultDisplayModeRefreshRate,
                            title: Text(l10n.appearanceAutoSystem),
                          ),
                          for (final rate in rates)
                            RadioListTile<int>(
                              contentPadding: EdgeInsets.zero,
                              value: rate,
                              title: Text(
                                rate == activeRate
                                    ? l10n.appearanceRefreshRateCurrent(rate)
                                    : '${rate}Hz',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isApplying) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.appearanceApplyingRefreshRate(
                          _formatRefreshRate(_applyingRate!, l10n),
                        ),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  l10n.appearanceRefreshRateDesc,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
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

    return Material(
      color: selected ? color.withValues(alpha: 0.14) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? color.withValues(alpha: 0.65) : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 1,
                    right: 1,
                    child: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: cs.onPrimary,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black26),
                      ],
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

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String _formatRefreshRate(int refreshRate, AppLocalizations l10n) {
  return refreshRate == UserManager.defaultDisplayModeRefreshRate
      ? l10n.appearanceAutoSystem
      : '${refreshRate}Hz';
}

class _DesktopFontCard extends StatefulWidget {
  final UserManager user;

  const _DesktopFontCard({required this.user});

  @override
  State<_DesktopFontCard> createState() => _DesktopFontCardState();
}

class _DesktopFontCardState extends State<_DesktopFontCard> {
  Future<List<String>>? _fontsFuture;
  bool _applying = false;

  Future<List<String>> _loadFonts() async {
    final list = SystemFonts().getFontList();
    final unique = <String>{...list}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return unique;
  }

  Future<void> _pickFont() async {
    _fontsFuture ??= _loadFonts();
    final selected = await showDialog<_FontPickResult>(
      context: context,
      builder: (ctx) => _FontPickerDialog(
        currentFont: widget.user.desktopFontFamily,
        fontsFuture: _fontsFuture!,
      ),
    );
    if (!mounted || selected == null) return;

    if (selected.useDefault) {
      await widget.user.setDesktopFontFamily('');
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceDefaultFontRestored,
        );
      }
      return;
    }

    final name = selected.fontName;
    if (name == null || name.isEmpty) return;
    setState(() => _applying = true);
    try {
      final family = await SystemFonts().loadFont(name);
      final resolved = (family?.toString().isNotEmpty ?? false)
          ? family.toString()
          : name;
      await widget.user.setDesktopFontFamily(resolved);
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceFontChanged(resolved),
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceFontLoadFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final current = widget.user.desktopFontFamily;
    final hasCustom = current.isNotEmpty;

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.font_download_outlined, color: cs.onSurfaceVariant),
                const SizedBox(width: 16),
                Text(l10n.appearanceAppFont),
              ],
            ),
            const SizedBox(height: 12),
            Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _applying ? null : _pickFont,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasCustom ? current : l10n.appearanceSystemDefault,
                          style: tt.bodyMedium?.copyWith(
                            fontFamily: hasCustom ? current : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_applying)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontPickResult {
  final bool useDefault;
  final String? fontName;

  const _FontPickResult.defaultFont() : useDefault = true, fontName = null;
  const _FontPickResult.named(String name)
    : useDefault = false,
      fontName = name;
}

class _FontPickerDialog extends StatefulWidget {
  final String currentFont;
  final Future<List<String>> fontsFuture;

  const _FontPickerDialog({
    required this.currentFont,
    required this.fontsFuture,
  });

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.appearanceChooseFont,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.appearanceSearchFont,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<String>>(
                  future: widget.fontsFuture,
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: ExpressiveLoadingIndicator(),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          l10n.appearanceFontLoadFailed(snap.error.toString()),
                          style: TextStyle(color: cs.error),
                        ),
                      );
                    }
                    final fonts = snap.data ?? const <String>[];
                    final lowerQuery = _query.toLowerCase();
                    final filtered = lowerQuery.isEmpty
                        ? fonts
                        : fonts
                              .where(
                                (f) => f.toLowerCase().contains(lowerQuery),
                              )
                              .toList();

                    return ListView.builder(
                      itemCount: filtered.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                          final selected = widget.currentFont.isEmpty;
                          return ListTile(
                            leading: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: selected ? cs.primary : null,
                            ),
                            title: Text(l10n.appearanceSystemDefault),
                            onTap: () => Navigator.of(
                              context,
                            ).pop(const _FontPickResult.defaultFont()),
                          );
                        }
                        final name = filtered[i - 1];
                        final selected = name == widget.currentFont;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected ? cs.primary : null,
                          ),
                          title: Text(name),
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_FontPickResult.named(name)),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
                  child: Icon(Icons.check_circle, size: 14, color: cs.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppFontCard extends StatefulWidget {
  final UserManager user;

  const _AppFontCard({required this.user});

  @override
  State<_AppFontCard> createState() => _AppFontCardState();
}

class _AppFontCardState extends State<_AppFontCard> {
  final _fontManager = FontManager();
  List<RemoteFontInfo> _fonts = const [];
  Map<String, bool> _downloadedCache = {};
  final _downloadStates = <String, bool>{};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refreshDownloadStates();
  }

  Future<void> _refreshDownloadStates() async {
    final downloaded = await _fontManager.listDownloadedFonts();
    final results = <String, bool>{};
    for (final name in downloaded) {
      results[name] = true;
    }
    if (mounted) setState(() => _downloadedCache = results);
  }

  Future<void> _loadFonts({bool force = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final fonts = await _fontManager.fetchAvailableFonts(force: force);
    await _refreshDownloadStates();
    if (mounted) {
      setState(() {
        _fonts = fonts;
        _loading = false;
      });
    }
  }

  Future<void> _selectFont(String fontName) async {
    if (_downloadStates[fontName] == true) return;

    final currentFont = widget.user.theme.appFontFamily;

    if (fontName == FontManager.defaultFontId) {
      if (currentFont.isEmpty) return;
      await widget.user.theme.setAppFontFamily(FontManager.defaultFontId);
      return;
    }

    if (currentFont == fontName) return;

    final isDownloaded = _downloadedCache[fontName] ?? false;
    if (!isDownloaded) {
      final font = _fontManager.infoForName(fontName);
      if (font == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final l10n = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text(l10n.appearanceFontDownloadTitle),
            content: Text(l10n.appearanceFontDownloadPrompt(font.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.appearanceFontDownloadTooltip),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      await _downloadFont(fontName);
      if (!(_downloadedCache[fontName] ?? false)) return;
    }

    final loaded = await _fontManager.loadFont(fontName);
    if (loaded != null) {
      await widget.user.theme.setAppFontFamily(fontName);
    }
  }

  Future<void> _downloadFont(String fontName) async {
    if (_downloadStates[fontName] == true) return;

    final font = _fontManager.infoForName(fontName);
    if (font == null) return;

    setState(() => _downloadStates[fontName] = true);
    try {
      final ok = await _fontManager.downloadFont(font);
      if (ok) {
        await _fontManager.loadFont(fontName);
      } else if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceFontDownloadFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloadStates[fontName] = false);
        await _refreshDownloadStates();
      }
    }
  }

  Future<void> _deleteFont(RemoteFontInfo font) async {
    final l10n = AppLocalizations.of(context)!;
    final isCustom = font.isCustom;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isCustom
              ? l10n.appearanceCustomFontRemoveTitle
              : l10n.appearanceFontDeleteTitle,
        ),
        content: Text(
          isCustom
              ? l10n.appearanceCustomFontRemoveContent(font.name)
              : l10n.appearanceFontDeleteContent(font.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (widget.user.theme.appFontFamily == font.name) {
      await widget.user.theme.setAppFontFamily(FontManager.defaultFontId);
    }
    if (isCustom) {
      await _fontManager.removeCustomFont(font.name);
    } else {
      await _fontManager.deleteFont(font.name);
    }
    await _refreshDownloadStates();
    if (mounted) {
      setState(() {
        _fonts = List<RemoteFontInfo>.from(_fontManager.cachedList);
      });
    }
  }

  Future<void> _showAddCustomFontDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.appearanceAddCustomFont),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n.appearanceCustomFontNameLabel,
                  hintText: l10n.appearanceCustomFontNameHint,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: l10n.appearanceCustomFontUrlLabel,
                  hintText: l10n.appearanceCustomFontUrlHint,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );

    final fontName = nameController.text.trim();
    final fontUrl = urlController.text.trim();
    // Dispose after the dialog route finishes unmounting its TextFields.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      urlController.dispose();
    });

    if (submitted != true || !mounted) return;

    final added = await _fontManager.addCustomFont(
      name: fontName,
      url: fontUrl,
    );
    if (!mounted) return;

    if (!added) {
      showToast(context, l10n.appearanceCustomFontInvalid, isError: true);
      return;
    }

    await _refreshDownloadStates();
    if (!mounted) return;
    setState(() {
      _fonts = List<RemoteFontInfo>.from(_fontManager.cachedList);
    });
    showToast(context, l10n.appearanceCustomFontAdded(fontName));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final currentFont = widget.user.theme.appFontFamily;
    final currentLabel = currentFont.isEmpty
        ? l10n.appearanceSystemDefault
        : currentFont;

    return Card(
      color: cs.surfaceContainerLow,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.text_fields, color: cs.onSurfaceVariant),
        title: Text(l10n.appearanceAppFont),
        subtitle: Text(
          currentLabel,
          style: tt.bodySmall?.copyWith(
            fontFamily: currentFont.isEmpty ? null : currentFont,
          ),
        ),
        trailing: SizedBox(
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l10n.appearanceAddCustomFont,
                onPressed: _showAddCustomFontDialog,
                icon: Icon(Icons.add_rounded, color: cs.primary),
                iconSize: 22,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 4),
              if (_loading)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: l10n.refreshButton,
                  onPressed: () => _loadFonts(force: true),
                  icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              const SizedBox(width: 4),
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(
                    Icons.expand_more,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        onExpansionChanged: (expanded) {
          if (expanded && _fonts.isEmpty && !_loading) {
            _loadFonts();
          }
        },
        children: [
          const Divider(height: 1),
          if (_loading && _fonts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else ...[
            RadioGroup<String>(
              groupValue: currentFont.isEmpty
                  ? FontManager.defaultFontId
                  : currentFont,
              onChanged: (value) {
                if (value != null) _selectFont(value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: FontManager.defaultFontId,
                    title: Text(l10n.appearanceSystemDefault),
                  ),
                  for (final font in _fonts)
                    RadioListTile<String>(
                      value: font.name,
                      title: Text(font.name),
                      subtitle: _buildFontSubtitle(font, l10n, cs),
                      secondary: _buildFontActions(font, l10n, cs),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildFontSubtitle(
    RemoteFontInfo font,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final isDownloaded = _downloadedCache[font.name] == true;
    if (!font.isCustom && isDownloaded) return null;

    final parts = <Widget>[];
    if (font.isCustom) {
      parts.add(
        Text(
          l10n.appearanceCustomFontBadge,
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (!isDownloaded) {
      if (parts.isNotEmpty) {
        parts.add(
          Text(' · ', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        );
      }
      parts.add(Text(l10n.appearanceFontNotDownloaded));
    }

    if (parts.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }

  Widget _buildFontActions(
    RemoteFontInfo font,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    if (_downloadStates[font.name] == true) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final isDownloaded = _downloadedCache[font.name] == true;
    final actions = <Widget>[];

    if (!isDownloaded) {
      actions.add(
        IconButton(
          icon: Icon(
            Icons.download_outlined,
            size: 20,
            color: colorScheme.primary,
          ),
          tooltip: l10n.appearanceFontDownloadTooltip,
          onPressed: () => _downloadFont(font.name),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    // Custom fonts can always be removed (even before download).
    // Built-in remote fonts only expose delete after they are downloaded.
    if (font.isCustom || isDownloaded) {
      actions.add(
        IconButton(
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          tooltip: font.isCustom
              ? l10n.appearanceCustomFontRemoveTitle
              : l10n.appearanceFontDeleteTitle,
          onPressed: () => _deleteFont(font),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (actions.length == 1) return actions.single;
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }
}
