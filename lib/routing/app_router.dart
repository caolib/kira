import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/comic.dart' hide Theme;
import '../pages/about_page.dart' show AboutPage;
import '../pages/ai_config_page.dart';
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
  static const search = 'search';
  static const bookshelf = 'bookshelf';
  static const profile = 'profile';

  // Top-level pages
  static const comicDetail = 'comic_detail';
  static const reader = 'reader';
  static const recommend = 'recommend';
  static const ranking = 'ranking';
  static const copyMangaList = 'copy_manga_list';
  static const localComics = 'local_comics';
  static const localComicDetail = 'local_comic_detail';
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
          // preload 让各分支页面在启动时就挂载（隐藏但活着），首次滑动切入
          // 不必现场 build + 拉数据；首次绘制由 MainShell 的预热负责。
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/',
                name: AppRoutes.home,
                builder: (_, _) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/search',
                name: AppRoutes.search,
                builder: (_, _) => const SearchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/bookshelf',
                name: AppRoutes.bookshelf,
                builder: (_, _) => const BookshelfPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
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
