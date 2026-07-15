import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/theme_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeSettings settings;

  setUp(() async {
    settings = ThemeSettings();
    settings.resetPrefsCache();
  });

  test('defaults to selectedOnly when no bottom-nav preference exists', () async {
    SharedPreferences.setMockInitialValues({});
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
    expect(settings.bottomNavShowLabels, isTrue);
  });

  test('migrates legacy true bool to selectedOnly mode', () async {
    SharedPreferences.setMockInitialValues({
      'bottom_nav_show_labels': true,
    });
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
    expect(settings.bottomNavShowLabels, isTrue);
  });

  test('migrates legacy false bool to hidden mode', () async {
    SharedPreferences.setMockInitialValues({
      'bottom_nav_show_labels': false,
    });
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.hidden);
    expect(settings.bottomNavShowLabels, isFalse);
  });

  test('prefers explicit label mode over legacy bool', () async {
    SharedPreferences.setMockInitialValues({
      'bottom_nav_show_labels': false,
      'bottom_nav_label_mode': BottomNavLabelMode.selectedOnly.name,
    });
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
  });

  test('setBottomNavLabelMode writes mode and legacy bool', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);

    await settings.setBottomNavLabelMode(BottomNavLabelMode.hidden);
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.hidden);
    expect(prefs.getString('bottom_nav_label_mode'), 'hidden');
    expect(prefs.getBool('bottom_nav_show_labels'), isFalse);

    await settings.setBottomNavLabelMode(BottomNavLabelMode.always);
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.always);
    expect(prefs.getString('bottom_nav_label_mode'), 'always');
    expect(prefs.getBool('bottom_nav_show_labels'), isTrue);
  });
}
