import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/update_check_frequency.dart';

void main() {
  final now = DateTime.utc(2026, 11, 6, 12);

  test('legacy values and unknown frequencies use compatible defaults', () {
    expect(
      UpdateCheckFrequency.fromPreference(null),
      UpdateCheckFrequency.startup,
    );
    expect(
      UpdateCheckFrequency.fromPreference(null, legacyEnabled: false),
      UpdateCheckFrequency.never,
    );
    expect(
      UpdateCheckFrequency.fromPreference('invalid'),
      UpdateCheckFrequency.startup,
    );
    expect(
      UpdateCheckFrequency.fromPreference(42, legacyEnabled: false),
      UpdateCheckFrequency.never,
    );
    for (final frequency in UpdateCheckFrequency.values) {
      expect(UpdateCheckFrequency.fromPreference(frequency.name), frequency);
    }
  });

  test('never and startup ignore the last successful check', () {
    for (final last in [null, now.millisecondsSinceEpoch]) {
      expect(
        UpdateCheckFrequency.never.isDue(
          now: now,
          lastSuccessMilliseconds: last,
        ),
        isFalse,
      );
      expect(
        UpdateCheckFrequency.startup.isDue(
          now: now,
          lastSuccessMilliseconds: last,
        ),
        isTrue,
      );
    }
  });

  for (final (frequency, days) in [
    (UpdateCheckFrequency.daily, 1),
    (UpdateCheckFrequency.weekly, 7),
    (UpdateCheckFrequency.monthly, 30),
  ]) {
    test('${frequency.name} uses exactly $days elapsed days', () {
      final boundary = now
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch;
      expect(
        frequency.isDue(now: now, lastSuccessMilliseconds: boundary + 1),
        isFalse,
      );
      expect(
        frequency.isDue(now: now, lastSuccessMilliseconds: boundary),
        isTrue,
      );
      expect(
        frequency.isDue(now: now, lastSuccessMilliseconds: boundary - 1),
        isTrue,
      );
    });

    test('${frequency.name} tolerates missing records and clock rollback', () {
      for (final last in [
        null,
        0,
        -1,
        now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      ]) {
        expect(
          frequency.isDue(now: now, lastSuccessMilliseconds: last),
          isTrue,
        );
      }
    });
  }
}
