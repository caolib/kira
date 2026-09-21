import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/comic.dart';

void main() {
  test('CopyFilterOptions survives a toJson/fromJson round-trip', () {
    final original = CopyFilterOptions(
      themes: [
        Theme(name: '愛情', pathWord: 'aiqing', count: 11376),
        Theme(name: '歡樂向', pathWord: 'huanlexiang', count: 6495),
      ],
      tops: [
        Theme(name: '日漫', pathWord: 'japan'),
        Theme(name: '已完結', pathWord: 'finish'),
      ],
    );

    final restored = CopyFilterOptions.fromJson(original.toJson());

    expect(restored.themes.length, 2);
    expect(restored.themes[0].name, '愛情');
    expect(restored.themes[0].pathWord, 'aiqing');
    expect(restored.themes[0].count, 11376);
    expect(restored.tops.length, 2);
    expect(restored.tops[1].name, '已完結');
    expect(restored.tops[1].pathWord, 'finish');
  });

  test('CopyFilterOptions handles the server payload shape', () {
    // /api/v3/h5/filter/comic/tags 的 results 形状
    final restored = CopyFilterOptions.fromJson({
      'theme': [
        {'initials': 0, 'name': '愛情', 'logo': null, 'path_word': 'aiqing', 'count': 11376},
      ],
      'ordering': [
        {'name': '更新時間', 'path_word': 'datetime_updated'},
      ],
      'top': [
        {'name': '日漫', 'path_word': 'japan'},
      ],
    });
    expect(restored.themes.single.pathWord, 'aiqing');
    expect(restored.tops.single.pathWord, 'japan');
  });

  test('CopyFilterOptions tolerates missing keys', () {
    final restored = CopyFilterOptions.fromJson(const {});
    expect(restored.themes, isEmpty);
    expect(restored.tops, isEmpty);
  });
}
