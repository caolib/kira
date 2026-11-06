enum UpdateCheckFrequency {
  never,
  startup,
  daily,
  weekly,
  monthly;

  static UpdateCheckFrequency fromPreference(
    Object? value, {
    bool legacyEnabled = true,
  }) {
    for (final frequency in values) {
      if (frequency.name == value) return frequency;
    }
    return legacyEnabled ? startup : never;
  }

  Duration? get interval => switch (this) {
    never || startup => null,
    daily => const Duration(days: 1),
    weekly => const Duration(days: 7),
    monthly => const Duration(days: 30),
  };

  bool isDue({required DateTime now, int? lastSuccessMilliseconds}) {
    if (this == never) return false;
    if (this == startup) return true;
    final nowMilliseconds = now.millisecondsSinceEpoch;
    // Missing/invalid records and a clock moved backwards must not block checks.
    if (lastSuccessMilliseconds == null ||
        lastSuccessMilliseconds <= 0 ||
        lastSuccessMilliseconds > nowMilliseconds) {
      return true;
    }
    return nowMilliseconds - lastSuccessMilliseconds >=
        interval!.inMilliseconds;
  }
}
