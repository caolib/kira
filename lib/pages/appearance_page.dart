import 'dart:async';
import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:system_fonts/system_fonts.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show isDesktop;
import '../models/app_theme_option.dart';
import '../models/theme_settings.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/display_mode_preference.dart';
import '../utils/font_manager.dart';
import '../utils/screen_layout.dart';
import '../utils/toast.dart';
import '../widgets/select_tile.dart';
import '../widgets/setting_tile_group.dart';
import '../widgets/settings_section.dart';
import '../widgets/text_controller_scope.dart';

part 'appearance/appearance_app_font_card.dart';
part 'appearance/appearance_controls.dart';
part 'appearance/appearance_desktop_font_card.dart';
part 'appearance/appearance_font_picker_dialog.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  final _user = UserManager();
  double? _previewCoverBrightness;
  double? _previewCardShadowElevation;
  List<int> _refreshRates = const [];
  int? _activeRefreshRate;
  bool _applyingRate = false;

  static const _navMeta = {
    'comic': (Icons.menu_book_outlined, Icons.menu_book),
    'search': (Icons.search_outlined, Icons.search),
    'bookshelf': (Icons.bookmark_border, Icons.bookmark),
    'profile': (Icons.person_outline, Icons.person),
  };

  String _navLabel(String key, AppLocalizations l10n) => switch (key) {
    'comic' => l10n.comicTabLabel,
    'search' => l10n.searchTabLabel,
    'bookshelf' => l10n.bookshelfTabLabel,
    'profile' => l10n.profileTabLabel,
    _ => key,
  };

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
    if (DisplayModePreference.isSupportedPlatform) {
      unawaited(_loadRefreshRates());
    }
  }

  Future<void> _loadRefreshRates() async {
    try {
      final data = await DisplayModePreference.load();
      if (!mounted) return;
      setState(() {
        _refreshRates = DisplayModePreference.refreshRates(data.modes);
        _activeRefreshRate = data.active.refreshRate.round();
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'appearance.refresh_rates',
        ),
      );
    }
  }

  Future<void> _selectRefreshRate(int rate) async {
    if (_applyingRate || rate == _user.displayModeRefreshRate) return;
    setState(() => _applyingRate = true);
    await _user.setDisplayModeRefreshRate(rate);
    final applied = await DisplayModePreference.applyRefreshRate(rate);
    if (!mounted) return;
    setState(() => _applyingRate = false);
    final l10n = AppLocalizations.of(context)!;
    showToast(
      context,
      applied
          ? l10n.appearanceRefreshRateRequested(
              _formatRefreshRate(rate, l10n),
            )
          : l10n.appearanceRefreshRateSaved,
    );
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
                const SizedBox(height: AppSpacing.sm),
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
  /// the equally-split preview slots. On narrow screens, fall back to a
  /// scrollable min-width so labels can ellipsize instead of overflowing.
  List<double> _navPreviewItemWidths({
    required double availableWidth,
    required int itemCount,
    required int selectedIndex,
    required BottomNavLabelMode labelMode,
  }) {
    if (itemCount <= 0) return const [];
    final minWidth = switch (labelMode) {
      BottomNavLabelMode.always => 56.0,
      BottomNavLabelMode.selectedOnly => 48.0,
      BottomNavLabelMode.hidden => 44.0,
    };
    final equal = availableWidth / itemCount;
    if (equal < minWidth) {
      return List<double>.filled(itemCount, minWidth);
    }
    if (labelMode != BottomNavLabelMode.selectedOnly ||
        selectedIndex < 0 ||
        selectedIndex >= itemCount ||
        equal >= 72) {
      return List<double>.filled(itemCount, equal);
    }

    final selectedWidth = (equal + 28).clamp(equal, availableWidth * 0.34);
    final remaining = availableWidth - selectedWidth;
    final otherWidth = (remaining / (itemCount - 1)).clamp(minWidth, equal);
    return [
      for (var i = 0; i < itemCount; i++)
        i == selectedIndex ? selectedWidth.toDouble() : otherWidth.toDouble(),
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
    final coverBrightness =
        _previewCoverBrightness ?? _user.darkModeCoverBrightness;
    final coverBrightnessPercent = (coverBrightness * 100).round();
    final cardShadowElevation =
        _previewCardShadowElevation ?? _user.theme.cardShadowElevation;

    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final isWide =
        ScreenLayout.contentWidth(screenWidth) >= ScreenLayout.wideBreakpoint;

    // 第一块卡片：底部导航标签模式 / 滑动切换 / 导航排序预览。
    final navCard = SettingTileGroup(
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
        SwitchListTile(
          secondary: Icon(Icons.swipe_outlined, color: cs.onSurfaceVariant),
          title: Text(l10n.appearanceNavSwipeTitle),
          subtitle: Text(
            l10n.appearanceNavSwipeDesc,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          value: _user.theme.navSwipeEnabled,
          onChanged: (value) =>
              unawaited(_user.theme.setNavSwipeEnabled(value)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.appearanceNavOrder, style: tt.titleSmall),
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
              SizedBox(
                height: _user.bottomNavLabelMode == BottomNavLabelMode.always
                    ? 80
                    : 56,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemCount = _user.navOrder.length;
                    final widths = _navPreviewItemWidths(
                      availableWidth: constraints.maxWidth,
                      itemCount: itemCount,
                      selectedIndex: _user.navOrder.indexOf(_user.lastNavKey),
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
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ],
    );

    final desktopFontCard = isDesktop ? _DesktopFontCard(user: _user) : null;

    final appFontCard = _AppFontCard(user: _user);

    final shadowSection = SettingsSection(
      icon: Icons.layers_outlined,
      title: l10n.appearanceShadowTitle,
      child: Column(
        children: [
          _AppearanceSliderControl(
            icon: Icons.view_agenda_outlined,
            title: l10n.appearanceCardShadowSize,
            description: l10n.appearanceCardShadowSizeDesc,
            valueText: cardShadowElevation.toStringAsFixed(1),
            value: cardShadowElevation,
            min: ThemeSettings.minCardShadowElevation,
            max: ThemeSettings.maxCardShadowElevation,
            divisions: 8,
            onChanged: (value) {
              setState(() => _previewCardShadowElevation = value);
            },
            onChangeEnd: (value) {
              setState(() => _previewCardShadowElevation = null);
              unawaited(_user.theme.setCardShadowElevation(value));
            },
          ),
        ],
      ),
    );

    final iconSection = SettingsSection(
      icon: Icons.switch_account_outlined,
      title: l10n.appearanceAppIcon,
      description: l10n.appearanceAppIconRestartHint,
      child: Wrap(
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
    );

    final refreshRateCard = DisplayModePreference.isSupportedPlatform
        ? SettingTileGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(l10n.appearanceRefreshRateTitle),
                trailing: _refreshRates.isEmpty
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : SelectTile<int>(
                        value: _user.displayModeRefreshRate,
                        items: [
                          SelectItem(
                            0,
                            l10n.appearanceAutoSystem,
                            compactLabel: l10n.appearanceAutoShort,
                          ),
                          for (final rate in _refreshRates)
                            SelectItem(
                              rate,
                              rate == _activeRefreshRate
                                  ? l10n.appearanceRefreshRateCurrent(rate)
                                  : '$rate Hz',
                            ),
                        ],
                        onChanged:
                            _applyingRate ? (_) {} : _selectRefreshRate,
                      ),
              ),
            ],
          )
        : null;

    final themeModeSection = SettingTileGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.settings_brightness),
          title: Text(l10n.appearanceThemeMode),
          trailing: SelectTile<ThemeMode>(
            value: _user.themeMode,
            items: [
              SelectItem(
                ThemeMode.system,
                l10n.appearanceSystemMode,
              ),
              SelectItem(ThemeMode.light, l10n.appearanceLightMode),
              SelectItem(ThemeMode.dark, l10n.appearanceDarkMode),
            ],
            onChanged: (v) => _user.setThemeMode(v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.brightness_low_outlined,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Text(l10n.appearanceDarkCoverBrightness),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.appearanceDarkCoverBrightnessDesc,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: coverBrightness,
                      min: UserManager.minDarkModeCoverBrightness,
                      divisions:
                          ((UserManager.maxDarkModeCoverBrightness -
                                      UserManager.minDarkModeCoverBrightness) /
                                  0.05)
                              .round(),
                      label: '$coverBrightnessPercent%',
                      onChanged: (value) {
                        setState(() => _previewCoverBrightness = value);
                      },
                      onChangeEnd: (value) {
                        setState(() => _previewCoverBrightness = null);
                        unawaited(_user.setDarkModeCoverBrightness(value));
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
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
      ],
    );

    final themeStyleSection = SettingsSection(
      icon: Icons.palette_outlined,
      title: l10n.appearanceThemeStyle,
      child: _user.theme.useDynamicColor
          ? const SizedBox.shrink()
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    showCheckmark: false,
                    onSelected: (_) => _user.setThemeVariant(option.variant),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
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
    );

    final colorOptionsSection = SettingTileGroup(
      children: [
        SwitchListTile(
          secondary: Icon(
            Icons.colorize_rounded,
            color: cs.onSurfaceVariant,
          ),
          title: Text(l10n.appearanceDynamicColor),
          subtitle: Text(
            l10n.appearanceDynamicColorDesc,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          value: _user.theme.useDynamicColor,
          onChanged: (value) => unawaited(_user.theme.setUseDynamicColor(value)),
        ),
        SwitchListTile(
          secondary: Icon(
            Icons.contrast_rounded,
            color: cs.onSurfaceVariant,
          ),
          title: Text(l10n.appearanceAmoledDark),
          subtitle: Text(
            l10n.appearanceAmoledDarkDesc,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          value: _user.theme.amoledDark,
          onChanged: (value) => unawaited(_user.theme.setAmoledDark(value)),
        ),
      ],
    );

    List<Widget> spaced(Iterable<Widget> cards) => [
      for (final (i, card) in cards.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpacing.sm),
        card,
      ],
    ];

    final Widget body;
    if (isWide) {
      // 宽屏双列：左列导航与字体卡片，右列阴影/图标/刷新率/主题卡片，
      // 两列顶部对齐、各自纵向堆叠。
      body = ListView(
        padding: EdgeInsets.fromLTRB(hp, 8, hp, 8),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: spaced([
                    navCard,
                    ?desktopFontCard,
                    appFontCard,
                    shadowSection,
                  ]),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: spaced([
                    iconSection,
                    ?refreshRateCard,
                    themeModeSection,
                    themeStyleSection,
                    colorOptionsSection,
                  ]),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      body = ListView(
        padding: EdgeInsets.fromLTRB(hp, 8, hp, 8),
        children: spaced([
          navCard,
          ?desktopFontCard,
          appFontCard,
          shadowSection,
          iconSection,
          ?refreshRateCard,
          themeModeSection,
          themeStyleSection,
          colorOptionsSection,
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appearanceTitle)),
      body: body,
    );
  }
}
