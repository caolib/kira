import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../models/app_theme_option.dart';
import '../models/user_manager.dart';
import '../utils/toast.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  final _user = UserManager();

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

  Future<void> _pickCustomThemeColor() async {
    final initialColor = _user.customThemeColor;
    final color = await showColorPickerDialog(
      context,
      initialColor,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: false,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: false,
        ColorPickerType.wheel: true,
      },
      enableShadesSelection: false,
      enableTonalPalette: false,
      enableOpacity: false,
      showColorCode: true,
      colorCodeHasColor: true,
      showEditIconButton: true,
      wheelDiameter: 220,
      wheelWidth: 20,
      wheelSquareBorderRadius: 12,
      wheelHasBorder: true,
      dialogTitle: const Text('选择主题色'),
      heading: const Text('点击色盘选择一个自定义主题色'),
      wheelSubheading: const Text('拖动取色点，实时预览主题色'),
      borderRadius: 12,
      constraints: const BoxConstraints(maxWidth: 460),
    );

    if (_user.themeColor != customThemeOptionId &&
        color.toARGB32() == initialColor.toARGB32()) {
      return;
    }

    await _user.setCustomThemeColor(color);
    if (mounted) {
      showToast(context, '主题配色已更新为 ${_colorToHex(color)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
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
                  Text(
                    '主题配色',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前配色：${_user.themeOption.label}${_user.themeColor == customThemeOptionId ? ' ${_colorToHex(_user.customThemeColor)}' : ''}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in appThemeOptions)
                        ChoiceChip(
                          avatar: CircleAvatar(
                            radius: 9,
                            backgroundColor: option.seedColor,
                          ),
                          label: Text(option.label),
                          selected: _user.themeColor == option.id,
                          selectedColor: option.seedColor.withValues(alpha: 0.18),
                          side: BorderSide(
                            color: _user.themeColor == option.id
                                ? option.seedColor.withValues(alpha: 0.65)
                                : cs.outlineVariant,
                          ),
                          labelStyle: tt.bodyMedium?.copyWith(
                            color: _user.themeColor == option.id
                                ? option.seedColor
                                : null,
                            fontWeight: _user.themeColor == option.id
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          onSelected: (_) => _user.setThemeColor(option.id),
                        ),
                      ChoiceChip(
                        avatar: CircleAvatar(
                          radius: 9,
                          backgroundColor: _user.customThemeColor,
                        ),
                        label: const Text('自定'),
                        selected: _user.themeColor == customThemeOptionId,
                        selectedColor:
                            _user.customThemeColor.withValues(alpha: 0.18),
                        side: BorderSide(
                          color: _user.themeColor == customThemeOptionId
                              ? _user.customThemeColor.withValues(alpha: 0.65)
                              : cs.outlineVariant,
                        ),
                        labelStyle: tt.bodyMedium?.copyWith(
                          color: _user.themeColor == customThemeOptionId
                              ? _user.customThemeColor
                              : null,
                          fontWeight: _user.themeColor == customThemeOptionId
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        onSelected: (_) => _pickCustomThemeColor(),
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

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
