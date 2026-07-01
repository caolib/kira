import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/comic.dart';
import 'package:kira/repositories/bookshelf_repository.dart';
import 'package:kira/repositories/manga_home_repository.dart';
import 'package:kira/repositories/search_init_repository.dart';

void main() {
  group('MangaHomeData', () {
    test('toJson and fromJson round-trip correctly', () {
      final home = MangaHome(
        banners: [
          const MangaBanner(
            cover: 'https://example.com/banner.jpg',
            brief: 'Test banner',
            outUuid: 'uuid1',
          ),
        ],
        recommendations: [
          Comic(name: 'Comic1', pathWord: 'pw1', cover: 'c1.jpg'),
        ],
      );
      final data = MangaHomeData(
        home: home,
        ranking: [
          Comic(name: 'Ranked', pathWord: 'rpw', cover: 'rc.jpg', popular: 99),
        ],
      );

      final json = data.toJson();
      final restored = MangaHomeData.fromJson(json);

      expect(restored.home.banners.length, 1);
      expect(restored.home.banners.first.outUuid, 'uuid1');
      expect(restored.home.recommendations.length, 1);
      expect(restored.home.recommendations.first.name, 'Comic1');
      expect(restored.ranking.length, 1);
      expect(restored.ranking.first.name, 'Ranked');
      expect(restored.ranking.first.popular, 99);
    });

    test('fromJson handles empty home gracefully', () {
      final data = MangaHomeData.fromJson({
        'home': {'banners': <dynamic>[], 'recs': <String, dynamic>{}},
        'ranking': <dynamic>[],
      });

      expect(data.home.banners, isEmpty);
      expect(data.home.recommendations, isEmpty);
      expect(data.ranking, isEmpty);
    });
  });

  group('CopyMangaHomeData', () {
    test('toJson and fromJson round-trip', () {
      final home = CopyMangaHome(
        recComics: [Comic(name: 'Rec', pathWord: 'pw', cover: 'c.jpg')],
      );
      final data = CopyMangaHomeData(home: home);

      final json = data.toJson();
      final restored = CopyMangaHomeData.fromJson(json);

      expect(restored.home.recComics.length, 1);
      expect(restored.home.recComics.first.name, 'Rec');
    });
  });

  group('ComicBookshelfData', () {
    test('toJson and fromJson round-trip with cacheTime', () {
      final now = DateTime.now();
      final data = ComicBookshelfData(
        items: [
          BookshelfItem(
            comic: Comic(name: 'Test', pathWord: 'pw', cover: 'c.jpg'),
            lastBrowseId: 'ch1',
            lastBrowseName: 'Chapter 1',
          ),
        ],
        total: 1,
        cacheTime: now,
      );

      final json = data.toJson();
      final restored = ComicBookshelfData.fromJson(json);

      expect(restored.items.length, 1);
      expect(restored.items.first.comic.name, 'Test');
      expect(restored.items.first.lastBrowseId, 'ch1');
      expect(restored.total, 1);
      expect(restored.cacheTime, isNotNull);
    });

    test('fromJson handles null cacheTime', () {
      final data = ComicBookshelfData.fromJson({
        'items': <dynamic>[],
        'total': 0,
      });

      expect(data.items, isEmpty);
      expect(data.total, 0);
      expect(data.cacheTime, isNull);
    });
  });

  group('AnimeBookshelfData', () {
    test('fromJson handles empty data', () {
      final data = AnimeBookshelfData.fromJson({
        'items': <dynamic>[],
        'total': 0,
      });

      expect(data.items, isEmpty);
      expect(data.total, 0);
      expect(data.cacheTime, isNull);
    });
  });

  group('SearchInitData', () {
    test('toJson and fromJson round-trip', () {
      // Use a minimal JSON round-trip that doesn't require Theme directly
      final json = {
        'keywords': ['keyword1', 'keyword2'],
        'tags': [
          {'name': 'action', 'path_word': 'pw1', 'count': 5},
        ],
      };

      final restored = SearchInitData.fromJson(json);

      expect(restored.keywords.length, 2);
      expect(restored.keywords[0], 'keyword1');
      expect(restored.tags.length, 1);
      expect(restored.tags.first.name, 'action');

      // Round-trip back to JSON
      final exported = restored.toJson();
      final restored2 = SearchInitData.fromJson(exported);
      expect(restored2.keywords.length, 2);
      expect(restored2.tags.first.name, 'action');
    });
  });
}
