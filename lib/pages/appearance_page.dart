import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:system_fonts/system_fonts.dart';

import '../main.dart' show isDesktop;
import '../models/app_theme_option.dart';
import '../models/user_manager.dart';
import '../utils/display_mode_preference.dart';
import '../utils/toast.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  final _user = UserManager();

  static const _navMeta = {
    'comic': (Icons.menu_book_outlined, Icons.menu_book, '漫画'),
    'anime': (Icons.movie_outlined, Icons.movie, '动漫'),
    'search': (Icons.search_outlined, Icons.search, '搜索'),
    'bookshelf': (Icons.bookmark_border, Icons.bookmark, '书架'),
    'profile': (Icons.person_outline, Icons.person, '我的'),
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
      showToast(context, '桌面图标已更换，可能需要重启应用后生效');
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

  Future<void> _pickCustomThemeColor() async {
    var selectedColor = _user.customThemeColor;
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
          heading: const Text('点击色盘选择一个自定义主题色'),
          wheelSubheading: const Text('拖动取色点，实时预览主题色'),
          borderRadius: 12,
        ).showPickerDialog(
          context,
          constraints: const BoxConstraints(maxWidth: 460),
        );

    if (!didSelectColor) return;

    await _user.setCustomThemeColor(selectedColor);
    if (mounted) {
      showToast(context, '主题配色已更新为 ${_colorToHex(selectedColor)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectedVariant = _user.themeVariantOption;
    final coverBrightnessPercent = (_user.darkModeCoverBrightness * 100)
        .round();

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Card(
            color: cs.surfaceContainerLow,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.text_fields_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  title: const Text('底部导航栏显示文字'),
                  value: _user.bottomNavShowLabels,
                  onChanged: _user.setBottomNavShowLabels,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_vert,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(width: 16),
                      Text('导航栏顺序', style: tt.titleSmall),
                    ],
                  ),
                ),
                SizedBox(
                  height: _user.bottomNavShowLabels ? 80 : 64,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemCount = _user.navOrder.length;
                      final itemWidth = constraints.maxWidth / itemCount;
                      final constrainedItemWidth = itemWidth < 56
                          ? 56.0
                          : itemWidth;

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
                            width: constrainedItemWidth,
                            child: ReorderableDragStartListener(
                              index: index,
                              child: _NavOrderDestination(
                                icon: meta.$1,
                                selectedIcon: meta.$2,
                                label: meta.$3,
                                selected: key == _user.lastNavKey,
                                showLabel: _user.bottomNavShowLabels,
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
                      const Text('应用图标'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '更换后重启应用生效',
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
                title: const Text('屏幕刷新率'),
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
                      const Text('主题模式'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.settings_brightness),
                          label: Text('系统'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('深色'),
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
                      const Text('暗色模式封面亮度'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '暗色模式下降低各个界面的卡片封面亮度',
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
                      const Text('主题风格'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前风格：${selectedVariant.label} · ${selectedVariant.description}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in appThemeVariantOptions)
                        Tooltip(
                          message: option.description,
                          child: ChoiceChip(
                            label: Text(option.label),
                            selected: _user.themeVariant == option.variant,
                            onSelected: (_) =>
                                _user.setThemeVariant(option.variant),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '主题配色',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击颜色块切换主题色，带勾选的为当前配色。',
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
  final bool showLabel;

  const _NavOrderDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 64,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? cs.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? selectedIcon : icon,
                color: foreground,
                size: 24,
              ),
            ),
            if (showLabel) ...[
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
    showToast(
      context,
      applied ? '已请求刷新率 ${_formatRefreshRate(refreshRate)}' : '刷新率偏好已保存',
    );
  }

  @override
  Widget build(BuildContext context) {
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
              child: Center(child: CircularProgressIndicator()),
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
                    '屏幕刷新率',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '获取设备刷新率失败：${snapshot.error ?? '未知错误'}',
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
                  '屏幕刷新率',
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
                          const RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            value: UserManager.defaultDisplayModeRefreshRate,
                            title: Text('自动（跟随系统）'),
                          ),
                          for (final rate in rates)
                            RadioListTile<int>(
                              contentPadding: EdgeInsets.zero,
                              value: rate,
                              title: Text(
                                rate == activeRate
                                    ? '${rate}Hz（当前）'
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
                        '正在应用 ${_formatRefreshRate(_applyingRate!)}',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '实际生效取决于系统和屏幕，部分设备可能需要重启应用后完全生效。',
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

String _formatRefreshRate(int refreshRate) {
  return refreshRate == UserManager.defaultDisplayModeRefreshRate
      ? '自动（跟随系统）'
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
      if (mounted) showToast(context, '已恢复系统默认字体，重启应用后完全生效');
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
      if (mounted) showToast(context, '字体已切换为 $resolved');
    } catch (e) {
      if (mounted) showToast(context, '加载字体失败：$e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const Text('应用字体'),
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
                          hasCustom ? current : '系统默认',
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
                  const Expanded(
                    child: Text(
                      '选择字体',
                      style: TextStyle(
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
                  hintText: '搜索字体',
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
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          '获取字体失败：${snap.error}',
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
                            title: const Text('系统默认'),
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
