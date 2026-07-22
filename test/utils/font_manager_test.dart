import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:kira/utils/font_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FontManager().resetForTest();
  });

  tearDown(() {
    FontManager().resetForTest();
  });

  group('FontManager remote catalog cache', () {
    test('keeps the remote font list for three days', () {
      expect(FontManager.fontListCacheTtl, const Duration(days: 3));
    });

    test('loads a valid persistent catalog without a remote request', () async {
      await AppStorage.cache.put('font_list_v1', {
        'fonts': [
          {'name': 'CachedFont', 'url': 'https://example.com/cached-font.ttf'},
        ],
      }, ttl: FontManager.fontListCacheTtl);

      final fonts = await FontManager().fetchAvailableFonts();

      expect(fonts, hasLength(1));
      expect(fonts.single.name, 'CachedFont');
    });
  });

  group('FontManager custom fonts', () {
    test('addCustomFont persists name and url', () async {
      final manager = FontManager();
      final added = await manager.addCustomFont(
        name: ' MyFont ',
        url: 'https://example.com/fonts/myfont.ttf',
      );
      expect(added, isTrue);

      final fonts = await manager.fetchAvailableFonts();
      final custom = fonts.where((font) => font.name == 'MyFont').toList();
      expect(custom, hasLength(1));
      expect(custom.single.url, 'https://example.com/fonts/myfont.ttf');
      expect(custom.single.isCustom, isTrue);

      manager.resetForTest();
      final reloaded = await FontManager().fetchAvailableFonts();
      expect(
        reloaded.any((font) => font.name == 'MyFont' && font.isCustom),
        isTrue,
      );
    });

    test('addCustomFont rejects invalid input', () async {
      final manager = FontManager();
      expect(
        await manager.addCustomFont(name: '', url: 'https://a.com/a.ttf'),
        isFalse,
      );
      expect(await manager.addCustomFont(name: 'A', url: ''), isFalse);
      expect(
        await manager.addCustomFont(name: 'A', url: 'ftp://a.com/a.ttf'),
        isFalse,
      );
      expect(await manager.addCustomFont(name: 'A', url: 'not-a-url'), isFalse);
      expect(
        await manager.addCustomFont(
          name: FontManager.defaultFontId,
          url: 'https://a.com/a.ttf',
        ),
        isFalse,
      );
    });

    test('removeCustomFont drops catalog entry', () async {
      final manager = FontManager();
      await manager.addCustomFont(
        name: 'TempFont',
        url: 'https://example.com/temp.ttf',
      );
      await manager.removeCustomFont('TempFont');
      final fonts = await manager.fetchAvailableFonts();
      expect(fonts.any((font) => font.name == 'TempFont'), isFalse);
    });
  });
}
