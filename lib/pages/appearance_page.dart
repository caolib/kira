import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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
import '../utils/app_platform.dart';
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

class _AppearancePageState extends State<AppearancePage>
    with WidgetsBindingObserver {
  final _user = UserManager();
  double? _previewCoverBrightness;
  double? _previewCardShadowElevation;
  List<int> _refreshRates = DisplayModePreference.refreshRates(const []);
  int? _activeRefreshRate;
  Timer? _refreshRateTimer;
  int _refreshRateGeneration = 0;
  bool _refreshRateVisible = false;
  bool _applyingRate = false;

  static const _navMeta = {
    'comic': (Icons.menu_book_outlined, Icons.menu_book),
    'novel': (Icons.auto_stories_outlined, Icons.auto_stories),
    'search': (Icons.search_outlined, Icons.search),
    'bookshelf': (Icons.favorite_border, Icons.favorite),
    'profile': (Icons.person_outline, Icons.person),
  };

  String _navLabel(String key, AppLocalizations l10n) => switch (key) {
    'comic' => l10n.comicTabLabel,
    'novel' => l10n.novelTitle,
    'search' => l10n.searchTabLabel,
    'bookshelf' => l10n.bookshelfTabLabel,
    'profile' => l10n.profileTabLabel,
    _ => key,
  };

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    if (DisplayModePreference.isSupportedPlatform) {
      unawaited(_loadRefreshRates());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshRateVisible = TickerMode.valuesOf(context).enabled;
    _syncRefreshRatePolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncRefreshRatePolling();
  }

  void _syncRefreshRatePolling() {
    _refreshRateTimer?.cancel();
    final generation = ++_refreshRateGeneration;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        !DisplayModePreference.isSupportedPlatform ||
        !_refreshRateVisible ||
        _applyingRate ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    unawaited(_readActiveRefreshRate(generation));
  }

  Future<void> _readActiveRefreshRate(int generation) async {
    var interval = const Duration(seconds: 1);
    int? rate;
    try {
      rate = await DisplayModePreference.activeRefreshRate();
    } catch (e, stack) {
      interval = const Duration(seconds: 5);
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'appearance.active_refresh_rate',
        ),
      );
    }
    // Ignore responses from before a preference/lifecycle change or disposal.
    if (!mounted || generation != _refreshRateGeneration) return;
    if (rate != _activeRefreshRate) {
      setState(() => _activeRefreshRate = rate);
    }
    // A single cancellable timer also observes delayed native mode switches.
    _refreshRateTimer = Timer(
      interval,
      () => unawaited(_readActiveRefreshRate(generation)),
    );
  }

  Future<void> _loadRefreshRates() async {
    try {
      final rates = await DisplayModePreference.loadRefreshRates();
      if (!mounted) return;
      setState(() => _refreshRates = rates);
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
    _syncRefreshRatePolling();
    await _user.setDisplayModeRefreshRate(rate);
    final applied = await DisplayModePreference.applyRefreshRate(rate);
    if (!mounted) return;
    setState(() => _applyingRate = false);
    _syncRefreshRatePolling();
    final l10n = AppLocalizations.of(context)!;
    showToast(
      context,
      applied
          ? l10n.appearanceRefreshRateRequested(_formatRefreshRate(rate, l10n))
          : l10n.appearanceRefreshRateSaved,
    );
  }

  @override
  void dispose() {
    _refreshRateTimer?.cancel();
    ++_refreshRateGeneration;
    WidgetsBinding.instance.removeObserver(this);
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

  String _bottomNavLabelModeLabel(
    BottomNavLabelMode mode,
    AppLocalizations l10n,
  ) => switch (mode) {
    BottomNavLabelMode.selectedOnly =>
      l10n.appearanceBottomNavLabelModeSelectedOnly,
    BottomNavLabelMode.hidden => l10n.appearanceBottomNavLabelModeHidden,
    BottomNavLabelMode.always => l10n.appearanceBottomNavLabelModeAlways,
  };

  Future<void> _selectBottomNavLabelMode(BottomNavLabelMode mode) async {
    await _user.setBottomNavLabelMode(mode);
    if (!mounted ||
        mode != BottomNavLabelMode.always ||
        !_user.theme.floatingNavEnabled ||
        _user.bottomNavLabelMode != BottomNavLabelMode.selectedOnly) {
      return;
    }
    showToast(
      context,
      AppLocalizations.of(context)!.appearanceFloatingNavLabelModeHint,
      duration: const Duration(seconds: 3),
    );
  }

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
        ScreenLayout.contentWidth(screenWidth) >= ScreenLayout.wideBreakpoint &&
        MediaQuery.textScalerOf(context).scale(14) <= 21;

    final navCard = SettingTileGroup(
      children: [
        ListTile(
          leading: Icon(Icons.text_fields_rounded, color: cs.onSurfaceVariant),
          title: Text(l10n.appearanceBottomNavLabelMode),
          trailing: SelectTile<BottomNavLabelMode>(
            value: _user.bottomNavLabelMode,
            items: [
              for (final mode in BottomNavLabelMode.values)
                SelectItem(mode, _bottomNavLabelModeLabel(mode, l10n)),
            ],
            onChanged: _selectBottomNavLabelMode,
          ),
        ),
        SwitchListTile(
          secondary: Icon(Icons.swipe_outlined, color: cs.onSurfaceVariant),
          title: Text(l10n.appearanceNavSwipeTitle),
          value: _user.theme.navSwipeEnabled,
          onChanged: (value) =>
              unawaited(_user.theme.setNavSwipeEnabled(value)),
        ),
        SwitchListTile(
          secondary: Icon(Icons.layers_outlined, color: cs.onSurfaceVariant),
          title: Text(l10n.appearanceFloatingNavTitle),
          value: _user.theme.floatingNavEnabled,
          onChanged: (value) =>
              unawaited(_user.theme.setFloatingNavEnabled(value)),
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
                    // 与底部导航一致：轻小说关闭时不参与排序预览。
                    final navOrder = _user.navOrder
                        .where((key) => key != 'novel' || _user.showNovel)
                        .toList();
                    final itemCount = navOrder.length;
                    final widths = _navPreviewItemWidths(
                      availableWidth: constraints.maxWidth,
                      itemCount: itemCount,
                      selectedIndex: navOrder.indexOf(_user.lastNavKey),
                      labelMode: _user.bottomNavLabelMode,
                    );

                    return ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.zero,
                      itemCount: itemCount,
                      onReorderItem: (oldIndex, newIndex) {
                        final order = List<String>.of(navOrder);
                        final item = order.removeAt(oldIndex);
                        order.insert(newIndex, item);
                        _user.setNavOrder(order);
                      },
                      itemBuilder: (context, index) {
                        final key = navOrder[index];
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

    // 阴影卡片不再要标题：滑块自己写着「统一阴影大小」。
    final shadowSection = SettingsSection(
      child: Column(
        children: [
          _AppearanceSliderControl(
            icon: Icons.view_agenda_outlined,
            title: l10n.appearanceCardShadowSize,
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
                trailing: SelectTile<int>(
                  value: _user.displayModeRefreshRate,
                  items: [
                    SelectItem(
                      0,
                      l10n.appearanceAutoSystem,
                      compactLabel: _activeRefreshRate == null
                          ? l10n.appearanceAutoShort
                          : l10n.appearanceAutoRefreshRate(_activeRefreshRate!),
                    ),
                    for (final rate in _refreshRates)
                      SelectItem(
                        rate,
                        rate == _activeRefreshRate
                            ? l10n.appearanceRefreshRateCurrent(rate)
                            : '$rate Hz',
                      ),
                  ],
                  onChanged: _applyingRate ? (_) {} : _selectRefreshRate,
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
              SelectItem(ThemeMode.system, l10n.appearanceSystemMode),
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
                  Expanded(child: Text(l10n.appearanceDarkCoverBrightness)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
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

    final useDynamicColor =
        AppPlatform.supportsDynamicColor && _user.theme.useDynamicColor;
    final themeStyleSection = SettingsSection(
      icon: Icons.palette_outlined,
      title: l10n.appearanceThemeStyle,
      child: useDynamicColor
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
                          onSelected: (_) =>
                              _user.setThemeVariant(option.variant),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
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
        if (AppPlatform.supportsDynamicColor)
          SwitchListTile(
            secondary: Icon(Icons.colorize_rounded, color: cs.onSurfaceVariant),
            title: Text(l10n.appearanceDynamicColor),
            value: _user.theme.useDynamicColor,
            onChanged: (value) =>
                unawaited(_user.theme.setUseDynamicColor(value)),
          ),
        SwitchListTile(
          secondary: Icon(Icons.contrast_rounded, color: cs.onSurfaceVariant),
          title: Text(l10n.appearanceAmoledDark),
          value: _user.theme.amoledDark,
          onChanged: (value) => unawaited(_user.theme.setAmoledDark(value)),
        ),
      ],
    );

    // 动效开关：与系统无障碍设置取并集，影响页面切换、封面交叉淡化与骨架。
    final motionSection = SettingTileGroup(
      children: [
        SwitchListTile(
          secondary: Icon(
            Icons.motion_photos_off_outlined,
            color: cs.onSurfaceVariant,
          ),
          title: Text(l10n.appearanceReduceMotionTitle),
          value: _user.theme.reduceMotion,
          onChanged: (value) => unawaited(_user.theme.setReduceMotion(value)),
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
      // 常用外观在左、导航和设备选项在右；大字号回到单列。
      body = ListView(
        padding: EdgeInsets.fromLTRB(hp, AppSpacing.sm, hp, AppSpacing.sm),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: spaced([
                    themeModeSection,
                    colorOptionsSection,
                    if (!useDynamicColor) themeStyleSection,
                    appFontCard,
                    ?desktopFontCard,
                    motionSection,
                  ]),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: spaced([
                    navCard,
                    shadowSection,
                    iconSection,
                    ?refreshRateCard,
                  ]),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      body = ListView(
        padding: EdgeInsets.fromLTRB(hp, AppSpacing.sm, hp, AppSpacing.sm),
        children: spaced([
          themeModeSection,
          colorOptionsSection,
          if (!useDynamicColor) themeStyleSection,
          appFontCard,
          ?desktopFontCard,
          motionSection,
          navCard,
          shadowSection,
          iconSection,
          ?refreshRateCard,
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appearanceTitle)),
      body: body,
    );
  }
}
