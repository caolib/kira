import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/comic.dart' hide Theme;
import '../models/novel.dart';
import '../pages/about_page.dart' show AboutPage;
import '../pages/account_center_page.dart';
import '../pages/ai_config_page.dart';
import '../pages/app_log_page.dart';
import '../pages/appearance_page.dart';
import '../pages/backup_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/bookshelf_page.dart';
import '../pages/browse_history_page.dart';
import '../pages/cache_management_page.dart';
import '../pages/comic_detail_page.dart';
import '../pages/copy_manga_list_page.dart';
import '../pages/copy_topic_detail_page.dart';
import '../pages/copy_topic_list_page.dart';
import '../pages/disclaimer_page.dart' show DisclaimerPage;
import '../pages/download_center_page.dart';
import '../pages/general_page.dart';
import '../pages/home_page.dart';
import '../pages/license_page.dart';
import '../pages/local_comics_page.dart';
import '../pages/local_novels_page.dart';
import '../pages/login_page.dart' show LoginPage;
import '../pages/network_page.dart';
import '../pages/notice_center_page.dart';
import '../pages/novel_detail_page.dart';
import '../pages/novel_filter_page.dart';
import '../pages/novel_history_page.dart';
import '../pages/novel_home_page.dart';
import '../pages/novel_reader_page.dart';
import '../pages/profile_page.dart';
import '../pages/ranking_page.dart';
import '../pages/reader_page.dart';
import '../pages/recommend_page.dart';
import '../pages/search_page.dart';
import '../pages/stats_page.dart';
import '../pages/webview_login_page.dart';
import '../utils/kira_links.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/novel_hero_tags.dart';
import 'dismiss_keyboard_observer.dart';
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
  static const novelHome = 'novel_home';
  static const novelDetail = 'novel_detail';
  static const novelFilter = 'novel_filter';
  static const novelReader = 'novel_reader';
  static const novelBookshelf = 'novel_bookshelf';
  static const novelHistory = 'novel_history';
  static const recommend = 'recommend';
  static const ranking = 'ranking';
  static const copyMangaList = 'copy_manga_list';
  static const copyTopics = 'copy_topics';
  static const copyTopicDetail = 'copy_topic_detail';
  static const localComics = 'local_comics';
  static const localComicDetail = 'local_comic_detail';
  static const localNovels = 'local_novels';
  static const localNovelDetail = 'local_novel_detail';
  static const login = 'login';
  static const webviewLogin = 'webview_login';
  static const accountCenter = 'account_center';
  static const general = 'general';
  static const backup = 'backup';
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
  static const packageLicense = 'package_license';
  static const fontLicense = 'font_license';
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

  /// 阅读器栈底没有本漫画目录页（章节列表）时为 true，「我的」继续阅读、
  /// 书签等直入入口使用。pop 落回的是来源列表页而非目录，
  /// 阅读器统一出口 `_exitToCatalog` 据此改为原地替换成漫画详情页。
  final bool noCatalogBelow;

  const ReaderExtra({
    this.comicName,
    this.group,
    required this.chapterName,
    this.chapterListPage,
    this.initialPage = 1,
    this.noCatalogBelow = false,
  });
}

/// Extra data for [NovelDetailPage] route.
class NovelDetailExtra {
  final NovelBook? initialBook;
  final String? heroTagBase;

  const NovelDetailExtra({this.initialBook, this.heroTagBase});
}

/// 卷内章节没有远端 UUID，使用目录原始索引定位。
class NovelReaderExtra {
  final String name;
  final String cover;
  final int entryIndex;
  final int initialParagraphIndex;
  final double initialParagraphAlignment;
  final bool resume;

  /// 本地入口先初始化下载目录，不限制后续卷的在线加载。
  final bool preferDownloads;

  /// 从书签进入：目标段落短暂高亮，提示书签指向的具体位置。
  final bool highlightParagraph;

  /// 栈底没有小说详情页（书架/历史/书签/继续阅读等直达入口）时置 true，
  /// 阅读页「总目录」退出会原地替换成详情页。
  final bool noDetailBelow;

  const NovelReaderExtra({
    this.name = '',
    this.cover = '',
    this.entryIndex = 0,
    this.initialParagraphIndex = 0,
    this.initialParagraphAlignment = 0,
    this.resume = false,
    this.preferDownloads = false,
    this.highlightParagraph = false,
    this.noDetailBelow = false,
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
    observers: [DismissKeyboardObserver()],
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildMainShellNavigatorContainer,
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          // preload 让各分支页面在启动时就挂载（隐藏但活着），首次滑动切入
          // 不必现场 build + 拉数据；首次绘制由 MainShell 的预热负责，首次
          // 数据加载由各页面的 BranchDeferredInit 推迟到「切到该分支且停稳」
          // 之后——启动只请求当前页，隐藏分支停留在骨架态。
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
                builder: (_, state) => BookshelfPage(
                  initialTab: state.uri.queryParameters['type'] == 'novel'
                      ? BookshelfTab.novel
                      : BookshelfTab.comic,
                ),
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
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/novels',
                name: AppRoutes.novelHome,
                builder: (_, _) => const NovelHomePage(),
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
            noCatalogBelow: extra?.noCatalogBelow ?? false,
          );
        },
      ),
      // Compatibility link: the novel shelf now belongs to the shared tab.
      GoRoute(
        path: '/novel-bookshelf',
        name: AppRoutes.novelBookshelf,
        redirect: (_, _) => '/bookshelf?type=novel',
      ),
      GoRoute(
        path: '/novel-history',
        name: AppRoutes.novelHistory,
        builder: (_, _) => const NovelHistoryPage(),
      ),
      GoRoute(
        path: '/novel/:pathWord',
        name: AppRoutes.novelDetail,
        pageBuilder: (context, state) {
          final extra = state.extra as NovelDetailExtra?;
          return CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: NovelHeroTags.transitionDuration,
            reverseTransitionDuration: NovelHeroTags.reverseTransitionDuration,
            child: NovelDetailPage(
              pathWord: state.pathParameters['pathWord']!,
              initialBook: extra?.initialBook,
              heroTagBase: extra?.heroTagBase,
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
        path: '/novel-filter/:kind/:pathWord',
        name: AppRoutes.novelFilter,
        redirect: (_, state) {
          final kind = state.pathParameters['kind'];
          if (!NovelFilterKind.values.any((value) => value.name == kind) ||
              state.pathParameters['pathWord']!.trim().isEmpty) {
            return '/novels';
          }
          return null;
        },
        builder: (_, state) => NovelFilterPage(
          kind: NovelFilterKind.values.byName(state.pathParameters['kind']!),
          pathWord: state.pathParameters['pathWord']!,
          name: state.uri.queryParameters['name'] ?? '',
        ),
      ),
      GoRoute(
        path: '/novel-reader/:pathWord/:volumeId',
        name: AppRoutes.novelReader,
        builder: (_, state) {
          final extra = state.extra;
          final options = extra is NovelReaderExtra
              ? extra
              : const NovelReaderExtra();
          return NovelReaderPage(
            pathWord: state.pathParameters['pathWord']!,
            volumeId: state.pathParameters['volumeId']!,
            name: options.name,
            cover: options.cover,
            initialEntryIndex: options.entryIndex,
            initialParagraphIndex: options.initialParagraphIndex,
            initialParagraphAlignment: options.initialParagraphAlignment,
            resume: options.resume,
            preferDownloads: options.preferDownloads,
            noDetailBelow: options.noDetailBelow,
            highlightOnEntry: options.highlightParagraph,
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
        path: '/copy-topics',
        name: AppRoutes.copyTopics,
        builder: (_, _) => const CopyTopicListPage(),
      ),
      GoRoute(
        path: '/copy-topic/:pathWord',
        name: AppRoutes.copyTopicDetail,
        builder: (_, state) =>
            CopyTopicDetailPage(pathWord: state.pathParameters['pathWord']!),
      ),
      GoRoute(
        path: '/local-comics',
        name: AppRoutes.localComics,
        builder: (_, _) => const LocalComicsPage(),
      ),
      GoRoute(
        path: '/local-comic-detail/:pathWord',
        name: AppRoutes.localComicDetail,
        builder: (_, state) =>
            LocalComicDetailPage(pathWord: state.pathParameters['pathWord']!),
      ),
      GoRoute(
        path: '/local-novels',
        name: AppRoutes.localNovels,
        builder: (_, _) => const LocalNovelsPage(),
      ),
      GoRoute(
        path: '/local-novel-detail/:pathWord',
        name: AppRoutes.localNovelDetail,
        builder: (_, state) =>
            LocalNovelDetailPage(pathWord: state.pathParameters['pathWord']!),
      ),
      GoRoute(
        path: '/login',
        name: AppRoutes.login,
        builder: (_, state) => LoginPage(
          copyOnly: state.uri.queryParameters['copyOnly'] == 'true',
        ),
      ),
      GoRoute(
        path: '/login/webview',
        name: AppRoutes.webviewLogin,
        builder: (_, state) => WebViewLoginPage(
          autoFill: state.extra as ({String username, String password}),
        ),
      ),
      GoRoute(
        path: '/accounts',
        name: AppRoutes.accountCenter,
        builder: (_, _) => const AccountCenterPage(),
      ),
      GoRoute(
        path: '/general',
        name: AppRoutes.general,
        builder: (_, _) => const GeneralPage(),
      ),
      GoRoute(
        path: '/general/backup',
        name: AppRoutes.backup,
        builder: (_, _) => const BackupPage(),
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
        routes: [
          GoRoute(
            path: ':packageName',
            name: AppRoutes.packageLicense,
            builder: (_, state) => PackageLicensePage(
              packageName: state.pathParameters['packageName']!,
            ),
          ),
          GoRoute(
            path: 'font/:fontId',
            name: AppRoutes.fontLicense,
            builder: (_, state) =>
                FontLicensePage(fontId: state.pathParameters['fontId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/cache-management',
        name: AppRoutes.cacheManagement,
        builder: (_, _) => const CacheManagementPage(),
      ),
    ],
  );
}
