import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/display_mode_preference.dart';

void main() {
  test('refreshRates keeps conventional manual rates only', () {
    final rates = DisplayModePreference.refreshRates(const [
      DisplayMode.auto,
      DisplayMode(id: 1, width: 1080, height: 2400, refreshRate: 15),
      DisplayMode(id: 2, width: 1080, height: 2400, refreshRate: 60),
      DisplayMode(id: 3, width: 1080, height: 2400, refreshRate: 90),
      DisplayMode(id: 4, width: 1080, height: 2400, refreshRate: 120),
      DisplayMode(id: 5, width: 1440, height: 3200, refreshRate: 120),
    ]);

    expect(rates, [120, 90, 60]);
  });

  test('refreshRates adds common manual rates below device maximum', () {
    final rates = DisplayModePreference.refreshRates(const [
      DisplayMode.auto,
      DisplayMode(id: 1, width: 1080, height: 2400, refreshRate: 15),
      DisplayMode(id: 2, width: 1080, height: 2400, refreshRate: 120),
    ]);

    expect(rates, [120, 90, 60]);
  });
}
