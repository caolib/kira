/// 定时备份的间隔单位，默认以「天」为单位。
enum BackupIntervalUnit { minutes, hours, days }

/// 用户配置的定时备份节奏。仅在本进程运行时生效，不做后台驻留。
class BackupSchedule {
  static const minValue = 1;
  static const maxValue = 9999;
  static const defaultValue = 1;

  final bool enabled;
  final int value;
  final BackupIntervalUnit unit;

  const BackupSchedule({
    this.enabled = false,
    this.value = defaultValue,
    this.unit = BackupIntervalUnit.days,
  });

  Duration get interval => switch (unit) {
    BackupIntervalUnit.minutes => Duration(minutes: value),
    BackupIntervalUnit.hours => Duration(hours: value),
    BackupIntervalUnit.days => Duration(days: value),
  };

  BackupSchedule copyWith({
    bool? enabled,
    int? value,
    BackupIntervalUnit? unit,
  }) => BackupSchedule(
    enabled: enabled ?? this.enabled,
    value: value ?? this.value,
    unit: unit ?? this.unit,
  );

  static int clampValue(int value) => value.clamp(minValue, maxValue);

  /// 单位名不认识（例如新版本删掉了某个单位）时返回 null，由调用方回退默认。
  static BackupIntervalUnit? tryFromName(Object? name) =>
      BackupIntervalUnit.values.where((unit) => unit.name == name).firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is BackupSchedule &&
      other.enabled == enabled &&
      other.value == value &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(enabled, value, unit);
}
