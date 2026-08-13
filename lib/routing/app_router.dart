import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/anime.dart';
import '../models/comic.dart' hide Theme;
import '../pages/about_page.dart' show AboutPage;
import '../pages/acknowledgement_page.dart';
import '../pages/ai_config_page.dart';
import '../pages/anime_detail_page.dart';
import '../pages/anime_home_page.dart';
import '../pages/anime_list_page.dart';
import '../pages/anime_player_page.dart';
import '../pages/app_log_page.dart';
import '../pages/appearance_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/bookshelf_page.dart';
import '../pages/browse_history_page.dart';
import '../pages/cache_management_page.dart';
import '../pages/comic_detail_page.dart';
import '../pages/copy_manga_list_page.dart';
import '../pages/disclaimer_page.dart' show DisclaimerPage;
import '../pages/download_center_page.dart';
import '../pages/general_page.dart';
import '../pages/home_page.dart';
import '../pages/license_page.dart';
import '../pages/local_anime_page.dart';
import '../pages/local_comics_page.dart';
import '../pages/login_page.dart' show LoginPage;
import '../pages/network_page.dart';
import '../pages/notice_center_page.dart';
import '../pages/profile_page.dart'
    hide LoginPage, RegisterPage, DisclaimerPage, AboutPage;
import '../pages/ranking_page.dart';
import '../pages/reader_page.dart';
import '../pages/recommend_page.dart';
import '../pages/register_page.dart' show RegisterPage;
import '../pages/search_page.dart';
import '../pages/stats_page.dart';
import '../pages/webview_login_page.dart';
import '../utils/kira_links.dart';
import '../widgets/comic_hero_tags.dart';
import 'main_shell.dart';

/// Named route constants for type-safe navigation.
final class AppRoutes {
  AppRoutes._();

  // Shell tabs
  static const home = 'home';
  static const anime = 'anime';
  static const search = 'search';
  static const bookshelf = 'bookshelf';
  static const profile = 'profile';

  // Top-level pages
  static const comicDetail = 'comic_detail';
  static const reader = 'reader';
  static const animeDetail = 'anime_detail';
  static const animePlayer = 'anime_player';
  static const recommend = 'recommend';
  static const ranking = 'ranking';
  static const copyMangaList = 'copy_manga_list';
  static const animeList = 'anime_list';
  static const localComics = 'local_comics';
  static const localAnime = 'local_anime';
  static const localComicDetail = 'local_comic_detail';
  static const localAnimeDetail = 'local_anime_detail';
  static const login = 'login';
  static const register = 'register';
  static const webviewLogin = 'webview_login';
  static const general = 'general';
  static const appearance = 'appearance';
  static const network = 'network';
  static const aiConfig = 'ai_config';
  static const downloadCenter = 'download_center';
  static const browseHistory = 'browse_history';
  static const bookmarks = 'bookmarks';
  static const noticeCenter = 'notice_center';
  static const about = 'about';
  static const disclaimer = 'disclaimer';
  static const appLog = 'app_log';
  static const acknowledgement = 'acknowledgement';
  static const license = 'license';
  static const cacheManagement = 'cache_management';
  static const stats = 'stats';
}

/// Extra data for [ComicDetailPage] route.
class ComicDetailExtra {
  final Comic? initialComic;
  final String? heroTagBase;
  final String? lastBrowseId;
  final String? lastBrowseName;

  const ComicDetailExtra({
    this.initialComic,
    this.heroTagBase,
    this.lastBrowseId,
    this.lastBrowseName,
  });
}

/// Extra data for [ReaderPage] route.
class ReaderExtra {
  final String? comicName;
  final String? group;
  final String chapterName;
  final int? chapterListPage;
  final int initialPage;

  const ReaderExtra({
    this.comicName,
    this.group,
    required this.chapterName,
    this.chapterListPage,
    this.initialPage = 1,
  });
}

/// Extra data for [AnimeDetailPage] route.
class AnimeDetailExtra {
  final Anime? initialAnime;

  const AnimeDetailExtra({this.initialAnime});
}

/// Extra data for [AnimePlayerPage] route.
class AnimePlayerExtra {
  final String animeName;
  final String chapterName;
  final String line;
  final List<AnimeChapter> chapters;
  final String? localVideoPath;

  const AnimePlayerExtra({
    required this.animeName,
    required this.chapterName,
    required this.line,
    this.chapters = const [],
    this.localVideoPath,
  });
}

/// Extra data for [RankingPage] route.
class RankingExtra {
  final String? authorPathWord;
  final String? authorName;
  final String? themePathWord;
  final String? themeName;

  const RankingExtra({
    this.authorPathWord,
    this.authorName,
    this.themePathWord,
    this.themeName,
  });
}

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildMainShellNavigatorContainer,
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: AppRoutes.home,
                builder: (_, _) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/anime',
                name: AppRoutes.anime,
                builder: (_, _) => const AnimeHomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                name: AppRoutes.search,
                builder: (_, _) => const SearchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/bookshelf',
                name: AppRoutes.bookshelf,
                builder: (_, _) => const BookshelfPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: AppRoutes.profile,
                builder: (_, _) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      // https 分享落地页链接(App Link):https://{KiraLinks.webHost}/c/?w={pathWord}
      // 系统把它交给 GoRouter 时 path 为 /c,这里重定向到真实的漫画详情路由。
      GoRoute(
        path: '/c',
        redirect: (context, state) =>
            KiraLinks.comicPathFromShareUrl(state.uri) ?? '/',
      ),
      GoRoute(
        path: '/comic/:pathWord',
        name: AppRoutes.comicDetail,
        pageBuilder: (context, state) {
          final pathWord = state.pathParameters['pathWord']!;
          final extra = state.extra as ComicDetailExtra?;
          return CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: ComicHeroTags.transitionDuration,
            reverseTransitionDuration: ComicHeroTags.reverseTransitionDuration,
            child: ComicDetailPage(
              pathWord: pathWord,
              initialComic: extra?.initialComic,
              heroTagBase: extra?.heroTagBase,
              lastBrowseId: extra?.lastBrowseId,
              lastBrowseName: extra?.lastBrowseName,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  if (animation.status == AnimationStatus.reverse) {
                    return Opacity(opacity: 0, child: child);
                  }
                  return child;
                },
          );
        },
      ),
      GoRoute(
        path: '/reader/:pathWord/:chapterUuid',
        name: AppRoutes.reader,
        builder: (context, state) {
          final pathWord = state.pathParameters['pathWord']!;
          final chapterUuid = state.pathParameters['chapterUuid']!;
          final extra = state.extra as ReaderExtra?;
          return ReaderPage(
            pathWord: pathWord,
            chapterUuid: chapterUuid,
            comicName: extra?.comicName,
            group: extra?.group,
            chapterName: extra?.chapterName ?? '',
            chapterListPage: extra?.chapterListPage,
            initialPage: extra?.initialPage ?? 1,
          );
        },
      ),
      GoRoute(
        path: '/anime-detail/:pathWord',
        name: AppRoutes.animeDetail,
        builder: (context, state) {
          final pathWord = state.pathParameters['pathWord']!;
          final extra = state.extra as AnimeDetailExtra?;
          return AnimeDetailPage(
            pathWord: pathWord,
            initialAnime: extra?.initialAnime,
          );
        },
      ),
      GoRoute(
        path: '/anime-player/:pathWord/:chapterUuid',
        name: AppRoutes.animePlayer,
        builder: (context, state) {
          final pathWord = state.pathParameters['pathWord']!;
          final chapterUuid = state.pathParameters['chapterUuid']!;
          final extra = state.extra as AnimePlayerExtra?;
          return AnimePlayerPage(
            pathWord: pathWord,
            chapterUuid: chapterUuid,
            animeName: extra?.animeName ?? '',
            chapterName: extra?.chapterName ?? '',
            line: extra?.line ?? '',
            chapters: extra?.chapters ?? const [],
            localVideoPath: extra?.localVideoPath,
          );
        },
      ),
      GoRoute(
        path: '/recommend',
        name: AppRoutes.recommend,
        builder: (_, _) => const RecommendPage(),
      ),
      GoRoute(
        path: '/ranking',
        name: AppRoutes.ranking,
        builder: (context, state) {
          final extra = state.extra as RankingExtra?;
          return RankingPage(
            authorPathWord: extra?.authorPathWord,
            authorName: extra?.authorName,
            themePathWord: extra?.themePathWord,
            themeName: extra?.themeName,
          );
        },
      ),
      GoRoute(
        path: '/copy-manga-list/:kind',
        name: AppRoutes.copyMangaList,
        builder: (context, state) {
          final kindName = state.pathParameters['kind'] ?? 'recommendations';
          final kind = CopyMangaListKind.values.firstWhere(
            (e) => e.name == kindName,
            orElse: () => CopyMangaListKind.recommendations,
          );
          return CopyMangaListPage(kind: kind);
        },
      ),
      GoRoute(
        path: '/anime-list/:type',
        name: AppRoutes.animeList,
        builder: (context, state) {
          final typeName = state.pathParameters['type'] ?? 'editor';
          final type = AnimeListType.values.firstWhere(
            (e) => e.name == typeName,
            orElse: () => AnimeListType.editor,
          );
          return AnimeListPage(type: type);
        },
      ),
      GoRoute(
        path: '/local-comics',
        name: AppRoutes.localComics,
        builder: (_, _) => const LocalComicsPage(),
      ),
      GoRoute(
        path: '/local-comic-detail/:pathWord',
        name: AppRoutes.localComicDetail,
        builder: (context, state) {
          final pathWord = state.pathParameters['pathWord']!;
          return LocalComicDetailPage(pathWord: pathWord);
        },
      ),
      GoRoute(
        path: '/local-anime',
        name: AppRoutes.localAnime,
        builder: (_, _) => const LocalAnimePage(),
      ),
      GoRoute(
        path: '/local-anime-detail/:pathWord',
        name: AppRoutes.localAnimeDetail,
        builder: (context, state) {
          final pathWord = state.pathParameters['pathWord']!;
          return LocalAnimeDetailPage(pathWord: pathWord);
        },
      ),
      GoRoute(
        path: '/login',
        name: AppRoutes.login,
        builder: (_, _) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: AppRoutes.register,
        builder: (_, _) => const RegisterPage(),
      ),
      GoRoute(
        path: '/login/webview',
        name: AppRoutes.webviewLogin,
        builder: (_, _) => const WebViewLoginPage(),
      ),
      GoRoute(
        path: '/general',
        name: AppRoutes.general,
        builder: (_, _) => const GeneralPage(),
      ),
      GoRoute(
        path: '/appearance',
        name: AppRoutes.appearance,
        builder: (_, _) => const AppearancePage(),
      ),
      GoRoute(
        path: '/network',
        name: AppRoutes.network,
        builder: (_, _) => const NetworkPage(),
      ),
      GoRoute(
        path: '/ai-config',
        name: AppRoutes.aiConfig,
        builder: (_, _) => const AiConfigPage(),
      ),
      GoRoute(
        path: '/download-center',
        name: AppRoutes.downloadCenter,
        builder: (context, state) {
          final initialTab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          return DownloadCenterPage(initialTab: initialTab);
        },
      ),
      GoRoute(
        path: '/browse-history',
        name: AppRoutes.browseHistory,
        builder: (_, _) =>
            BrowseHistoryPage(loginPageBuilder: (_) => const LoginPage()),
      ),
      GoRoute(
        path: '/bookmarks',
        name: AppRoutes.bookmarks,
        builder: (_, _) => const BookmarksPage(),
      ),
      GoRoute(
        path: '/stats',
        name: AppRoutes.stats,
        builder: (_, _) => const StatsPage(),
      ),
      GoRoute(
        path: '/notices',
        name: AppRoutes.noticeCenter,
        builder: (_, _) => const NoticeCenterPage(),
      ),
      GoRoute(
        path: '/about',
        name: AppRoutes.about,
        builder: (_, _) => const AboutPage(),
      ),
      GoRoute(
        path: '/disclaimer',
        name: AppRoutes.disclaimer,
        builder: (_, _) => const DisclaimerPage(),
      ),
      GoRoute(
        path: '/app-log',
        name: AppRoutes.appLog,
        builder: (_, _) => const AppLogPage(),
      ),
      GoRoute(
        path: '/acknowledgement',
        name: AppRoutes.acknowledgement,
        builder: (_, _) => const AcknowledgementPage(),
      ),
      GoRoute(
        path: '/license',
        name: AppRoutes.license,
        builder: (_, _) => const ProjectLicensePage(),
      ),
      GoRoute(
        path: '/cache-management',
        name: AppRoutes.cacheManagement,
        builder: (_, _) => const CacheManagementPage(),
      ),
    ],
  );
}
