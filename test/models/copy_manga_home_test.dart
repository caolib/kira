import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/comic.dart' hide Theme;

void main() {
  test('CopyMangaHome.fromJson 解析全部板块', () {
    final home = CopyMangaHome.fromJson(_sampleResults);

    // banners：仅保留 type==1，type=6 外链被过滤
    expect(home.banners.length, 1);
    expect(home.banners.first.type, 1);
    expect(home.banners.first.cover, startsWith('https://'));
    expect(home.banners.first.outUuid, '92c42eba-b3a4-11ed-a57e-024352452ce0');
    expect(home.banners.first.comic, isNotNull);
    expect(home.banners.first.comic!.name, '四畳半的睡美人');

    // recComics / rank* / hot / new：解析 list[].comic
    expect(home.recComics.length, 3);
    expect(home.recComics.first.name, '尾巴與逆鱗');
    expect(home.rankDayComics.length, 1);
    expect(home.rankDayComics.first.name, '在超市後門吸煙的二人');
    expect(home.rankWeekComics.length, 1);
    expect(home.rankMonthComics.length, 1);
    expect(home.hotComics.length, 1);
    expect(home.hotComics.first.name, '死宅男女大亂燉'); // 来自 comic.name，外层 name 是章节名
    expect(home.newComics.length, 1);

    // finishComics：list[] 本身即漫画对象
    expect(home.finishComics.length, 1);
    expect(home.finishComics.first.name, '假面騎士 Super Hero Ride Xtreme');
    expect(home.finishComics.first.authors.first.name, '若林まこと');

    // topics / topicsList
    expect(home.topics.length, 4);
    expect(home.topics.first.title, contains('這本漫畫真厲害'));
    expect(home.topics.first.period, '第39期');
    expect(home.topics.first.pathWord, 'zhebenmanhuazhenlihai2026');
    expect(home.topics.first.datetimeCreated, '2026-03-27');
    expect(home.topicsList.length, 4);
    expect(home.topicsList.last.type, 4); // 写真 type=4
  });

  test('CopyMangaHome.fromJson 缺失字段时回退为空列表', () {
    final home = CopyMangaHome.fromJson({});
    expect(home.banners, isEmpty);
    expect(home.recComics, isEmpty);
    expect(home.rankDayComics, isEmpty);
    expect(home.finishComics, isEmpty);
    expect(home.topics, isEmpty);
  });

  test('CopyMangaHome.toJson 可往返', () {
    final home = CopyMangaHome.fromJson(_sampleResults);
    final encoded = home.toJson();
    final decoded = CopyMangaHome.fromJson(encoded);
    expect(decoded.banners.length, home.banners.length);
    expect(decoded.recComics.length, home.recComics.length);
    expect(decoded.rankWeekComics.length, home.rankWeekComics.length);
    expect(decoded.hotComics.length, home.hotComics.length);
    expect(decoded.finishComics.length, home.finishComics.length);
    expect(decoded.topicsList.length, home.topicsList.length);
  });
}

/// 取自 homeIndex2 真实响应的精简样本（结构完整、字段代表性覆盖）。
const _sampleResults = {
  'topics': {
    'list': [
      {
        'title': '這本漫畫真厲害2026獲獎作品 必看熱門漫畫推薦第39期',
        'series': null,
        'journal': '2026',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/zhebenmanhuazhenlihai2026/17746252607598.jpg.200x80.jpg',
        'period': '第39期',
        'type': 1,
        'brief': '',
        'path_word': 'zhebenmanhuazhenlihai2026',
        'datetime_created': '2026-03-27',
      },
      {
        'title': '最期待2026動畫化的漫畫 必看熱門漫畫推薦第38期',
        'series': null,
        'journal': '2026',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/remenmanhua202509/17746250508583.jpg.200x80.jpg',
        'period': '第38期',
        'type': 1,
        'brief': '',
        'path_word': 'remenmanhua202509',
        'datetime_created': '2026-03-27',
      },
      {
        'title': '冬番漫畫2026 必看熱門漫畫推薦第37期',
        'series': null,
        'journal': '2026',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/remenmanhua202601/17746248574099.jpg.200x80.jpg',
        'period': '第37期',
        'type': 1,
        'brief': '',
        'path_word': 'remenmanhua202601',
        'datetime_created': '2026-03-18',
      },
      {
        'title': '秋番漫畫2025 必看熱門漫畫推薦第36期',
        'series': null,
        'journal': '2025',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/remenmanhua202508/17642407475414.jpg.200x80.jpg',
        'period': '第36期',
        'type': 1,
        'brief': '',
        'path_word': 'remenmanhua202508',
        'datetime_created': '2025-11-21',
      },
    ],
    'total': 39,
    'limit': 4,
    'offset': 0,
  },
  'topicsList': {
    'list': [
      {
        'title': '這本漫畫真厲害2026獲獎作品 必看熱門漫畫推薦第39期',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/zhebenmanhuazhenlihai2026/17746252607598.jpg.200x80.jpg',
        'period': '第39期',
        'type': 1,
        'brief': '',
        'path_word': 'zhebenmanhuazhenlihai2026',
        'datetime_created': '2026-03-27',
      },
      {
        'title': '最期待2026動畫化的漫畫 必看熱門漫畫推薦第38期',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/remenmanhua202509/17746250508583.jpg.200x80.jpg',
        'period': '第38期',
        'type': 1,
        'brief': '',
        'path_word': 'remenmanhua202509',
        'datetime_created': '2026-03-27',
      },
      {
        'title': '冬番漫畫2026 必看熱門漫畫推薦第37期',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/remenmanhua202601/17746248574099.jpg.200x80.jpg',
        'period': '第37期',
        'type': 1,
        'brief': '',
        'path_word': 'remenmanhua202601',
        'datetime_created': '2026-03-18',
      },
      {
        'title': '11月獨家授權寫真推薦 美女寫真集第24期',
        'cover':
            'https://s3.mangafunb.fun/topic/cover/xiezhen24/17674970647601.jpg.200x80.jpg',
        'period': '第24期',
        'type': 4,
        'brief': '',
        'path_word': 'xiezhen24',
        'datetime_created': '2025-12-26',
      },
    ],
    'total': 63,
    'limit': 4,
    'offset': 0,
  },
  'recComics': {
    'list': [
      {
        'type': 1,
        'comic': {
          'name': '尾巴與逆鱗',
          'path_word': 'weibayunilin',
          'author': [
            {'name': '由田果', 'path_word': 'youtianguo'},
          ],
          'cover':
              'https://sw.mangafunb.fun/w/weibayunilin/cover/1775900220.jpg.328x422.jpg',
          'popular': 7078,
          'author_alias': '由田果',
        },
      },
      {
        'type': 1,
        'comic': {
          'name': '小手指君別碰我',
          'path_word': 'xiaoshouzhijunbietengwo',
          'author': [
            {'name': 'シンジョウタクヤ', 'path_word': 'sinzyoutakuya'},
          ],
          'cover':
              'https://sx.mangafunb.fun/x/xiaoshouzhijunbietengwo/cover/1659555457.jpg.328x422.jpg',
          'popular': 5964099,
          'author_alias': 'シンジョウタクヤ',
        },
      },
      {
        'type': 1,
        'comic': {
          'name': '和組織宿敵的婚後生活超甜',
          'path_word': 'hzzsddhhshct',
          'author': [
            {'name': 'しーめ', 'path_word': 'siyia'},
          ],
          'cover':
              'https://sh.mangafunb.fun/h/hzzsddhhshct/cover/1770489314.png.328x422.jpg',
          'popular': 107428,
          'author_alias': 'しーめ',
        },
      },
    ],
    'total': 1758,
    'limit': 3,
    'offset': 0,
  },
  'rankDayComics': {
    'list': [
      {
        'sort': 1,
        'comic': {
          'name': '在超市後門吸煙的二人',
          'path_word': 'zaichaoshihoumenxiyandeerren',
          'author': [
            {'name': '地主', 'path_word': 'dizhu'},
          ],
          'cover':
              'https://sz.mangafunb.fun/z/zaichaoshihoumenxiyandeerren/cover/1769605539.jpg.328x422.jpg',
          'popular': 8472765,
          'author_alias': '地主',
        },
      },
    ],
    'total': 198,
    'limit': 6,
    'offset': 0,
  },
  'rankWeekComics': {
    'list': [
      {
        'sort': 1,
        'comic': {
          'name': '在超市後門吸煙的二人',
          'path_word': 'zaichaoshihoumenxiyandeerren',
          'author': [
            {'name': '地主', 'path_word': 'dizhu'},
          ],
          'cover': 'https://example.com/w1.jpg',
          'popular': 7613432,
        },
      },
    ],
  },
  'rankMonthComics': {
    'list': [
      {
        'sort': 1,
        'comic': {
          'name': '喜歡來者不拒的你',
          'path_word': 'xihuanlaizhebujudeni',
          'cover': 'https://example.com/m1.jpg',
          'popular': 6781185,
        },
      },
    ],
  },
  'hotComics': [
    {
      'name': '第22話',
      'comic': {
        'name': '死宅男女大亂燉',
        'path_word': 'sizainannvdaluandun',
        'cover': 'https://example.com/h1.jpg',
        'popular': 238530,
      },
    },
  ],
  'newComics': [
    {
      'name': '全一卷',
      'comic': {
        'name': '假面騎士 Super Hero Ride Xtreme',
        'path_word': 'jiamianqishisuperheroridextreme',
        'cover': 'https://example.com/n1.jpg',
        'popular': 108,
      },
    },
  ],
  'finishComics': {
    'list': [
      {
        'name': '假面騎士 Super Hero Ride Xtreme',
        'path_word': 'jiamianqishisuperheroridextreme',
        'author': [
          {'name': '若林まこと', 'path_word': ''},
          {'name': 'ギコガコ堂', 'path_word': ''},
        ],
        'author_alias': '若林まこと,ギコガコ堂',
        'cover':
            'https://sj.mangafunb.fun/j/jiamianqishisuperheroridextreme/cover/1781422716.jpg.328x422.jpg',
        'popular': 108,
        'datetime_updated': '2026-06-14',
      },
    ],
    'total': 15813,
    'limit': 6,
    'offset': 0,
  },
  'banners': [
    {
      'type': 6,
      'cover': 'https://s3.mangafunb.fun/recommend/2026/06/17810812467285.jpg',
      'brief': '看新番、看里番、看本子的点这里(下载不了请更新至最新版)',
      'out_uuid': 'https://www.manga2026.xyz/download',
      'comic': null,
    },
    {
      'type': 1,
      'cover': 'https://s3.mangafunb.fun/recommend/2026/06/17812613730666.jpg',
      'brief': '報社獵奇少女漫、慎入',
      'out_uuid': '92c42eba-b3a4-11ed-a57e-024352452ce0',
      'comic': {'name': '四畳半的睡美人', 'path_word': 'sidiebandeshuimeiren'},
    },
  ],
};
