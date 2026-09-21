import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backup/backup_schedule.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_status_colors.dart';
import '../../widgets/setting_tile_group.dart';
import 'backup_labels.dart';

/// 定时备份开关与间隔设置。前置条件不满足时不允许开启（已开启的仍可关闭），
/// [hint] 用于说明不可开启的原因。
class BackupScheduleControls extends StatefulWidget {
  final BackupSchedule schedule;
  final bool canEnable;
  final bool enabled;
  final String? hint;
  final ValueChanged<BackupSchedule> onChanged;

  const BackupScheduleControls({
    super.key,
    required this.schedule,
    required this.canEnable,
    required this.enabled,
    required this.onChanged,
    this.hint,
  });

  @override
  State<BackupScheduleControls> createState() => _BackupScheduleControlsState();
}

class _BackupScheduleControlsState extends State<BackupScheduleControls> {
  late final _value = TextEditingController(text: '${widget.schedule.value}');

  @override
  void didUpdateWidget(covariant BackupScheduleControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = '${widget.schedule.value}';
    // 只在外部值确实与输入框内容不一致时回写，避免打断正在输入的内容。
    if (_value.text != text &&
        int.tryParse(_value.text) != widget.schedule.value) {
      _value.text = text;
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _commitValue(String raw) {
    final value = int.tryParse(raw);
    if (value == null || value < BackupSchedule.minValue) return;
    widget.onChanged(widget.schedule.copyWith(value: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final schedule = widget.schedule;
    return SettingTileGroup(
      children: [
        SwitchListTile(
          title: Text(l10n.backupSchedule),
          // 已开启或没有原因时不显示，避免常驻说明文案。
          subtitle: widget.hint == null || widget.schedule.enabled
              ? null
              : Text(
                  widget.hint!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppStatusColors.warning(
                      Theme.of(context).colorScheme,
                    ),
                  ),
                ),
          value: schedule.enabled,
          onChanged: widget.enabled && (widget.canEnable || schedule.enabled)
              ? (value) => widget.onChanged(schedule.copyWith(enabled: value))
              : null,
        ),
        if (schedule.enabled)
          ListTile(
            title: Text(l10n.backupScheduleInterval),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _value,
                    enabled: widget.enabled,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    onChanged: _commitValue,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DropdownButtonHideUnderline(
                  child: DropdownButton<BackupIntervalUnit>(
                    value: schedule.unit,
                    onChanged: widget.enabled
                        ? (unit) => unit == null
                              ? null
                              : widget.onChanged(schedule.copyWith(unit: unit))
                        : null,
                    items: [
                      for (final unit in BackupIntervalUnit.values)
                        DropdownMenuItem(
                          value: unit,
                          child: Text(backupIntervalUnitLabel(unit, l10n)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
