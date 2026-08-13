import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/kira_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('comicDetail link uses kira scheme and open host', () {
    final uri = Uri.parse(KiraLinks.comicDetail('some_comic'));

    expect(uri.scheme, KiraLinks.scheme);
    expect(uri.host, 'open');
    expect(uri.path, '/comic/some_comic');
    expect(KiraLinks.comicDetail('some_comic'), 'kira://open/comic/some_comic');
  });

  test('comicShareUrl is an https link on the landing-page host', () {
    final uri = Uri.parse(KiraLinks.comicShareUrl('some_comic'));

    expect(uri.scheme, 'https');
    expect(uri.host, KiraLinks.webHost);
    expect(uri.path, '/c/');
    expect(uri.queryParameters['w'], 'some_comic');
  });

  test('comic link paths match the app comicDetail route', () {
    // 深链/https 链接交付给 GoRouter 后必须最终命中 /comic/:pathWord 路由，
    // 否则接收方点击链接会看到路由错误页。
    final router = createAppRouter();
    addTearDown(router.dispose);

    void expectComicRoute(String location) {
      final matchList = router.configuration.findMatch(Uri.parse(location));
      expect(matchList.isError, isFalse, reason: location);
      expect(
        matchList.matches.whereType<RouteMatch>().first.route.name,
        AppRoutes.comicDetail,
        reason: location,
      );
      expect(
        matchList.pathParameters['pathWord'],
        'some_comic',
        reason: location,
      );
    }

    // kira:// 深链:path 直接就是 /comic/:pathWord。
    expectComicRoute(KiraLinks.comicDetail('some_comic'));
    // https 分享链接:经 /c 路由 redirect 后命中漫画详情(与线上导航一致)。
    final shareUrl = KiraLinks.comicShareUrl('some_comic');
    final redirected = KiraLinks.comicPathFromShareUrl(Uri.parse(shareUrl));
    expect(redirected, '/comic/some_comic');
    expectComicRoute(redirected!);
  });

  group('comicPathFromShareUrl', () {
    test('maps the landing-page URL to the in-app comic path', () {
      final uri = Uri.parse('https://${KiraLinks.webHost}/c/?w=abc_123');
      expect(KiraLinks.comicPathFromShareUrl(uri), '/comic/abc_123');
    });

    test('returns null for non-share URLs', () {
      // 缺少 w 参数
      expect(
        KiraLinks.comicPathFromShareUrl(
          Uri.parse('https://${KiraLinks.webHost}/c/'),
        ),
        isNull,
      );
      // 非法 pathWord 字符
      expect(
        KiraLinks.comicPathFromShareUrl(
          Uri.parse('https://${KiraLinks.webHost}/c/?w=a.b'),
        ),
        isNull,
      );
      // 非本站域名
      expect(
        KiraLinks.comicPathFromShareUrl(Uri.parse('https://evil.com/c/?w=abc')),
        isNull,
      );
      // 非 /c 路径
      expect(
        KiraLinks.comicPathFromShareUrl(
          Uri.parse('https://${KiraLinks.webHost}/other?w=abc'),
        ),
        isNull,
      );
    });
  });

  group('extractComicPathWord', () {
    test('extracts pathWord from a kira:// share text', () {
      const text = '《咒术回战》 kira://open/comic/zhoushuhuizhan';
      expect(KiraLinks.extractComicPathWord(text), 'zhoushuhuizhan');
    });

    test('extracts pathWord from an https share text', () {
      final text = '《咒术回战》 ${KiraLinks.comicShareUrl('zhoushuhuizhan')}';
      expect(KiraLinks.extractComicPathWord(text), 'zhoushuhuizhan');
    });

    test('stops at Chinese punctuation right after the link', () {
      const text = '《咒术回战》 kira://open/comic/zhoushuhuizhan。快来看！';
      expect(KiraLinks.extractComicPathWord(text), 'zhoushuhuizhan');
    });

    test('returns null when there is no kira comic link', () {
      expect(KiraLinks.extractComicPathWord('随便一段文本'), isNull);
      expect(
        KiraLinks.extractComicPathWord('https://example.com/comic/abc'),
        isNull,
      );
      // 其他 kira:// 路径不算漫画分享链接
      expect(KiraLinks.extractComicPathWord('kira://open/reader/abc'), isNull);
    });
  });

  group('extractComicName', () {
    test('extracts the bracketed comic name', () {
      const text = '《咒术回战》 kira://open/comic/zhoushuhuizhan';
      expect(KiraLinks.extractComicName(text), '咒术回战');
    });

    test('returns null when there is no bracketed name', () {
      expect(KiraLinks.extractComicName('kira://open/comic/abc'), isNull);
    });
  });

  group('SharedLinkRecord', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('read returns null when nothing was recorded', () async {
      expect(await SharedLinkRecord.read(), isNull);
    });

    test('markHandled stores the link and a newer one replaces it', () async {
      await SharedLinkRecord.markHandled('comic_a');
      expect(await SharedLinkRecord.read(), 'comic_a');

      // 只保存一条记录：记录 B 后 A 不再被拦截（A→B→A 场景 A 会再次提示）。
      await SharedLinkRecord.markHandled('comic_b');
      expect(await SharedLinkRecord.read(), 'comic_b');
    });
  });
}
