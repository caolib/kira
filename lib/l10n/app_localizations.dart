import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Kira'**
  String get appTitle;

  /// No description provided for @comicTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get comicTabLabel;

  /// No description provided for @animeTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'动漫'**
  String get animeTabLabel;

  /// No description provided for @searchTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get searchTabLabel;

  /// No description provided for @bookshelfTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'书架'**
  String get bookshelfTabLabel;

  /// No description provided for @profileTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get profileTabLabel;

  /// No description provided for @disclaimerTitle.
  ///
  /// In zh, this message translates to:
  /// **'免责声明'**
  String get disclaimerTitle;

  /// No description provided for @disclaimerAgreeNote.
  ///
  /// In zh, this message translates to:
  /// **'继续使用本应用，即表示您已阅读、理解并同意上述说明；如您不同意，请立即停止使用并退出本应用。'**
  String get disclaimerAgreeNote;

  /// No description provided for @disclaimerConfirmAgeAndTerms.
  ///
  /// In zh, this message translates to:
  /// **'我已年满 18 周岁，并已仔细阅读、充分理解且同意上述全部条款'**
  String get disclaimerConfirmAgeAndTerms;

  /// No description provided for @disagreeAndExit.
  ///
  /// In zh, this message translates to:
  /// **'不同意并退出'**
  String get disagreeAndExit;

  /// No description provided for @confirmButton.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirmButton;

  /// No description provided for @cancelButton.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancelButton;

  /// No description provided for @deleteButton.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get deleteButton;

  /// No description provided for @loadingFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get loadingFailed;

  /// No description provided for @retryButton.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retryButton;

  /// No description provided for @noContent.
  ///
  /// In zh, this message translates to:
  /// **'暂无内容'**
  String get noContent;

  /// No description provided for @hotRecommend.
  ///
  /// In zh, this message translates to:
  /// **'热门推荐'**
  String get hotRecommend;

  /// No description provided for @comicRanking.
  ///
  /// In zh, this message translates to:
  /// **'漫画排行'**
  String get comicRanking;

  /// No description provided for @rankingAuthorWorks.
  ///
  /// In zh, this message translates to:
  /// **'作者作品'**
  String get rankingAuthorWorks;

  /// No description provided for @rankingThemeWorks.
  ///
  /// In zh, this message translates to:
  /// **'主题作品'**
  String get rankingThemeWorks;

  /// No description provided for @rankingNoAuthorWorks.
  ///
  /// In zh, this message translates to:
  /// **'暂无作者作品'**
  String get rankingNoAuthorWorks;

  /// No description provided for @rankingNoThemeWorks.
  ///
  /// In zh, this message translates to:
  /// **'暂无主题作品'**
  String get rankingNoThemeWorks;

  /// No description provided for @rankingNoComics.
  ///
  /// In zh, this message translates to:
  /// **'暂无漫画'**
  String get rankingNoComics;

  /// No description provided for @moreButton.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get moreButton;

  /// No description provided for @dayRank.
  ///
  /// In zh, this message translates to:
  /// **'日榜'**
  String get dayRank;

  /// No description provided for @weekRank.
  ///
  /// In zh, this message translates to:
  /// **'周榜'**
  String get weekRank;

  /// No description provided for @monthRank.
  ///
  /// In zh, this message translates to:
  /// **'月榜'**
  String get monthRank;

  /// No description provided for @copyRecommend.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get copyRecommend;

  /// No description provided for @copyRanking.
  ///
  /// In zh, this message translates to:
  /// **'排行榜'**
  String get copyRanking;

  /// No description provided for @copyHotUpdate.
  ///
  /// In zh, this message translates to:
  /// **'热门更新'**
  String get copyHotUpdate;

  /// No description provided for @copyNewArrival.
  ///
  /// In zh, this message translates to:
  /// **'全新上架'**
  String get copyNewArrival;

  /// No description provided for @copyFinished.
  ///
  /// In zh, this message translates to:
  /// **'已完结'**
  String get copyFinished;

  /// No description provided for @switchToHotHome.
  ///
  /// In zh, this message translates to:
  /// **'切换到 HOT 首页'**
  String get switchToHotHome;

  /// No description provided for @switchToCopyHome.
  ///
  /// In zh, this message translates to:
  /// **'切换到 COPY 首页'**
  String get switchToCopyHome;

  /// No description provided for @homeSourceHot.
  ///
  /// In zh, this message translates to:
  /// **'热辣'**
  String get homeSourceHot;

  /// No description provided for @homeSourceCopy.
  ///
  /// In zh, this message translates to:
  /// **'拷贝'**
  String get homeSourceCopy;

  /// No description provided for @localComicsTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地漫画'**
  String get localComicsTitle;

  /// No description provided for @noLocalComicsTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有本地漫画'**
  String get noLocalComicsTitle;

  /// No description provided for @noLocalComicsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'去漫画详情页下载章节后，这里会显示离线内容'**
  String get noLocalComicsSubtitle;

  /// No description provided for @deleteLocalComicsTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除本地漫画'**
  String get deleteLocalComicsTitle;

  /// No description provided for @deleteLocalComicsContent.
  ///
  /// In zh, this message translates to:
  /// **'确定删除选中的 {count} 部本地漫画吗？已下载章节和封面都会被删除。'**
  String deleteLocalComicsContent(int count);

  /// No description provided for @deletedLocalComicsCount.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 部本地漫画'**
  String deletedLocalComicsCount(int count);

  /// No description provided for @localAnimeTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地动漫'**
  String get localAnimeTitle;

  /// No description provided for @noLocalAnimeTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有本地动漫'**
  String get noLocalAnimeTitle;

  /// No description provided for @noLocalAnimeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'去动漫详情页下载剧集后，这里会显示离线内容'**
  String get noLocalAnimeSubtitle;

  /// No description provided for @deleteLocalAnimeTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除本地动漫'**
  String get deleteLocalAnimeTitle;

  /// No description provided for @deleteLocalAnimeContent.
  ///
  /// In zh, this message translates to:
  /// **'确定删除选中的 {count} 部本地动漫吗？已下载视频和封面都会被删除。'**
  String deleteLocalAnimeContent(int count);

  /// No description provided for @deletedLocalAnimeCount.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 部本地动漫'**
  String deletedLocalAnimeCount(int count);

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} {unit}'**
  String selectedCount(int count, String unit);

  /// No description provided for @selectedItems.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 部'**
  String selectedItems(int count);

  /// No description provided for @downloadedChapterCount.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {count} 章'**
  String downloadedChapterCount(int count);

  /// No description provided for @downloadedEpisodeCount.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {count} 集'**
  String downloadedEpisodeCount(int count);

  /// No description provided for @downloadedCountUnit.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {count} {unit}'**
  String downloadedCountUnit(int count, String unit);

  /// No description provided for @localChaptersTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地章节 ({count})'**
  String localChaptersTitle(int count);

  /// No description provided for @localEpisodesTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地剧集 ({count})'**
  String localEpisodesTitle(int count);

  /// No description provided for @deleteLocalChaptersTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除本地章节'**
  String get deleteLocalChaptersTitle;

  /// No description provided for @deleteChaptersConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除选中的 {count} 个章节吗？'**
  String deleteChaptersConfirm(int count);

  /// No description provided for @deletedChaptersCount.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 个章节'**
  String deletedChaptersCount(int count);

  /// No description provided for @deleteLocalEpisodesTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除本地剧集'**
  String get deleteLocalEpisodesTitle;

  /// No description provided for @deleteEpisodesConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除选中的 {count} 个剧集吗？'**
  String deleteEpisodesConfirm(int count);

  /// No description provided for @deletedEpisodesCount.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 个剧集'**
  String deletedEpisodesCount(int count);

  /// No description provided for @viewOnlineDetail.
  ///
  /// In zh, this message translates to:
  /// **'查看在线详情'**
  String get viewOnlineDetail;

  /// No description provided for @manageChapters.
  ///
  /// In zh, this message translates to:
  /// **'管理章节'**
  String get manageChapters;

  /// No description provided for @manageEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'管理剧集'**
  String get manageEpisodes;

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @sortReverse.
  ///
  /// In zh, this message translates to:
  /// **'逆序（新→旧）'**
  String get sortReverse;

  /// No description provided for @sortNormal.
  ///
  /// In zh, this message translates to:
  /// **'正序（旧→新）'**
  String get sortNormal;

  /// No description provided for @readMark.
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get readMark;

  /// No description provided for @videoFileNotFound.
  ///
  /// In zh, this message translates to:
  /// **'视频文件不存在'**
  String get videoFileNotFound;

  /// No description provided for @openDownloadFolder.
  ///
  /// In zh, this message translates to:
  /// **'打开下载位置'**
  String get openDownloadFolder;

  /// No description provided for @batchManage.
  ///
  /// In zh, this message translates to:
  /// **'批量管理'**
  String get batchManage;

  /// No description provided for @comicLabel.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get comicLabel;

  /// No description provided for @animeLabel.
  ///
  /// In zh, this message translates to:
  /// **'动漫'**
  String get animeLabel;

  /// No description provided for @comicWithCount.
  ///
  /// In zh, this message translates to:
  /// **'漫画（{count}）'**
  String comicWithCount(int count);

  /// No description provided for @animeWithCount.
  ///
  /// In zh, this message translates to:
  /// **'动漫（{count}）'**
  String animeWithCount(int count);

  /// No description provided for @hasUpdate.
  ///
  /// In zh, this message translates to:
  /// **'有更新'**
  String get hasUpdate;

  /// No description provided for @updateBadge.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get updateBadge;

  /// No description provided for @refreshedAt.
  ///
  /// In zh, this message translates to:
  /// **'刷新于 {time}'**
  String refreshedAt(String time);

  /// No description provided for @sortByUpdate.
  ///
  /// In zh, this message translates to:
  /// **'按更新'**
  String get sortByUpdate;

  /// No description provided for @sortByFavorite.
  ///
  /// In zh, this message translates to:
  /// **'按收藏'**
  String get sortByFavorite;

  /// No description provided for @sortByRead.
  ///
  /// In zh, this message translates to:
  /// **'按阅读'**
  String get sortByRead;

  /// No description provided for @sortLabel.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sortLabel;

  /// No description provided for @sortMethod.
  ///
  /// In zh, this message translates to:
  /// **'排序方式'**
  String get sortMethod;

  /// No description provided for @sortByUpdateTime.
  ///
  /// In zh, this message translates to:
  /// **'作品更新时间'**
  String get sortByUpdateTime;

  /// No description provided for @sortByUpdateTimeDesc.
  ///
  /// In zh, this message translates to:
  /// **'按{type}最新章节的更新时间排序'**
  String sortByUpdateTimeDesc(String type);

  /// No description provided for @sortByFavoriteTime.
  ///
  /// In zh, this message translates to:
  /// **'收藏时间'**
  String get sortByFavoriteTime;

  /// No description provided for @sortByFavoriteTimeDesc.
  ///
  /// In zh, this message translates to:
  /// **'按加入书架的时间排序'**
  String get sortByFavoriteTimeDesc;

  /// No description provided for @sortByBrowseTime.
  ///
  /// In zh, this message translates to:
  /// **'浏览时间'**
  String get sortByBrowseTime;

  /// No description provided for @sortByBrowseTimeDesc.
  ///
  /// In zh, this message translates to:
  /// **'按最近浏览的时间排序'**
  String get sortByBrowseTimeDesc;

  /// No description provided for @bookshelfEmpty.
  ///
  /// In zh, this message translates to:
  /// **'书架空空如也'**
  String get bookshelfEmpty;

  /// No description provided for @goFindSomething.
  ///
  /// In zh, this message translates to:
  /// **'去找点好看的{type}吧'**
  String goFindSomething(String type);

  /// No description provided for @refreshButton.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refreshButton;

  /// No description provided for @noComicUpdates.
  ///
  /// In zh, this message translates to:
  /// **'没有漫画更新'**
  String get noComicUpdates;

  /// No description provided for @backToTop.
  ///
  /// In zh, this message translates to:
  /// **'回到顶部'**
  String get backToTop;

  /// No description provided for @refreshSuccess.
  ///
  /// In zh, this message translates to:
  /// **'刷新成功'**
  String get refreshSuccess;

  /// No description provided for @refreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败'**
  String get refreshFailed;

  /// No description provided for @loginExpiredTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录已过期'**
  String get loginExpiredTitle;

  /// No description provided for @loginExpiredBookshelfContent.
  ///
  /// In zh, this message translates to:
  /// **'书架需要登录后才能继续使用，是否现在重新登录？'**
  String get loginExpiredBookshelfContent;

  /// No description provided for @loginExpiredFeatureContent.
  ///
  /// In zh, this message translates to:
  /// **'{featureName}需要登录后才能继续使用，是否现在重新登录？'**
  String loginExpiredFeatureContent(String featureName);

  /// No description provided for @laterButton.
  ///
  /// In zh, this message translates to:
  /// **'稍后再说'**
  String get laterButton;

  /// No description provided for @goLoginButton.
  ///
  /// In zh, this message translates to:
  /// **'去登录'**
  String get goLoginButton;

  /// No description provided for @autoLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动登录失败，请手动重新登录'**
  String get autoLoginFailed;

  /// No description provided for @loginToViewBookshelf.
  ///
  /// In zh, this message translates to:
  /// **'登录后可继续查看书架'**
  String get loginToViewBookshelf;

  /// No description provided for @totalEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 集'**
  String totalEpisodes(int count);

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索{mode}...'**
  String searchHint(String mode);

  /// No description provided for @hotSearchTitle.
  ///
  /// In zh, this message translates to:
  /// **'热门搜索'**
  String get hotSearchTitle;

  /// No description provided for @allTagsTitle.
  ///
  /// In zh, this message translates to:
  /// **'全部标签'**
  String get allTagsTitle;

  /// No description provided for @tagCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String tagCount(int count);

  /// No description provided for @popularOrder.
  ///
  /// In zh, this message translates to:
  /// **'热度'**
  String get popularOrder;

  /// No description provided for @updateOrder.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get updateOrder;

  /// No description provided for @searchResultSummary.
  ///
  /// In zh, this message translates to:
  /// **'搜索 \"{query}\" 找到 {total} 个{mode}结果'**
  String searchResultSummary(String query, int total, String mode);

  /// No description provided for @openFolderFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开文件夹失败：{error}'**
  String openFolderFailed(String error);

  /// No description provided for @deleteToastPrefix.
  ///
  /// In zh, this message translates to:
  /// **'已删除 '**
  String get deleteToastPrefix;

  /// No description provided for @deleteToastSuffixComic.
  ///
  /// In zh, this message translates to:
  /// **' 部本地漫画'**
  String get deleteToastSuffixComic;

  /// No description provided for @deleteToastSuffixAnime.
  ///
  /// In zh, this message translates to:
  /// **' 部本地动漫'**
  String get deleteToastSuffixAnime;

  /// No description provided for @chapterUnit.
  ///
  /// In zh, this message translates to:
  /// **'章'**
  String get chapterUnit;

  /// No description provided for @episodeUnit.
  ///
  /// In zh, this message translates to:
  /// **'集'**
  String get episodeUnit;

  /// No description provided for @generalTitle.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get generalTitle;

  /// No description provided for @autoLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动登录'**
  String get autoLoginTitle;

  /// No description provided for @autoLoginEnabledDesc.
  ///
  /// In zh, this message translates to:
  /// **'登录过期时自动重新登录'**
  String get autoLoginEnabledDesc;

  /// No description provided for @autoLoginUnavailableDesc.
  ///
  /// In zh, this message translates to:
  /// **'登录并保存账号密码后可用'**
  String get autoLoginUnavailableDesc;

  /// No description provided for @animeFeatureTitle.
  ///
  /// In zh, this message translates to:
  /// **'动漫功能'**
  String get animeFeatureTitle;

  /// No description provided for @animeFeatureDesc.
  ///
  /// In zh, this message translates to:
  /// **'关闭后隐藏动漫相关功能'**
  String get animeFeatureDesc;

  /// No description provided for @remoteNoticeTitle.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get remoteNoticeTitle;

  /// No description provided for @remoteNoticeDesc.
  ///
  /// In zh, this message translates to:
  /// **'开启后应用启动时自动检查通知；关闭后仅在进入通知中心时获取'**
  String get remoteNoticeDesc;

  /// No description provided for @noticeSettingsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'通知设置'**
  String get noticeSettingsTooltip;

  /// No description provided for @bannerVisibleTitle.
  ///
  /// In zh, this message translates to:
  /// **'显示Banner'**
  String get bannerVisibleTitle;

  /// No description provided for @bannerVisibleDesc.
  ///
  /// In zh, this message translates to:
  /// **'关闭后漫画和动漫主页顶部Banner不显示'**
  String get bannerVisibleDesc;

  /// No description provided for @languageTitle.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get languageTitle;

  /// No description provided for @languageSimplifiedSystem.
  ///
  /// In zh, this message translates to:
  /// **'简体中文（跟随系统）'**
  String get languageSimplifiedSystem;

  /// No description provided for @languageTraditional.
  ///
  /// In zh, this message translates to:
  /// **'繁體中文'**
  String get languageTraditional;

  /// No description provided for @cacheManagementTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存管理'**
  String get cacheManagementTitle;

  /// No description provided for @cacheManagementDesc.
  ///
  /// In zh, this message translates to:
  /// **'查看和删除本地缓存、历史和账号数据'**
  String get cacheManagementDesc;

  /// No description provided for @exportSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出设置'**
  String get exportSettingsTitle;

  /// No description provided for @exportSettingsDesc.
  ///
  /// In zh, this message translates to:
  /// **'复制配置到剪贴板'**
  String get exportSettingsDesc;

  /// No description provided for @importSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入设置'**
  String get importSettingsTitle;

  /// No description provided for @importSettingsDesc.
  ///
  /// In zh, this message translates to:
  /// **'粘贴导入配置'**
  String get importSettingsDesc;

  /// No description provided for @settingsCopiedWithSensitive.
  ///
  /// In zh, this message translates to:
  /// **'设置已复制，包含敏感信息'**
  String get settingsCopiedWithSensitive;

  /// No description provided for @settingsCopiedWithoutSensitive.
  ///
  /// In zh, this message translates to:
  /// **'设置已复制，未包含敏感信息'**
  String get settingsCopiedWithoutSensitive;

  /// No description provided for @exportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{error}'**
  String exportFailed(String error);

  /// No description provided for @noImportSettingsContent.
  ///
  /// In zh, this message translates to:
  /// **'没有可导入的配置内容'**
  String get noImportSettingsContent;

  /// No description provided for @settingsBackupEmptyClipboard.
  ///
  /// In zh, this message translates to:
  /// **'剪贴板里没有可导入的配置'**
  String get settingsBackupEmptyClipboard;

  /// No description provided for @settingsBackupInvalidJson.
  ///
  /// In zh, this message translates to:
  /// **'配置格式不是有效的 JSON'**
  String get settingsBackupInvalidJson;

  /// No description provided for @settingsBackupInvalidFormat.
  ///
  /// In zh, this message translates to:
  /// **'配置格式不正确'**
  String get settingsBackupInvalidFormat;

  /// No description provided for @settingsBackupWrongApp.
  ///
  /// In zh, this message translates to:
  /// **'这不是 Kira 的设置备份'**
  String get settingsBackupWrongApp;

  /// No description provided for @settingsBackupUnsupportedVersion.
  ///
  /// In zh, this message translates to:
  /// **'备份版本不受支持'**
  String get settingsBackupUnsupportedVersion;

  /// No description provided for @settingsBackupMissingContent.
  ///
  /// In zh, this message translates to:
  /// **'配置内容缺失或格式不正确'**
  String get settingsBackupMissingContent;

  /// No description provided for @settingsBackupUnsupportedField.
  ///
  /// In zh, this message translates to:
  /// **'配置中包含不支持的字段'**
  String get settingsBackupUnsupportedField;

  /// No description provided for @settingsBackupInvalidFieldFormat.
  ///
  /// In zh, this message translates to:
  /// **'配置字段格式不正确'**
  String get settingsBackupInvalidFieldFormat;

  /// No description provided for @settingsBackupUnsupportedFieldType.
  ///
  /// In zh, this message translates to:
  /// **'配置字段类型不受支持'**
  String get settingsBackupUnsupportedFieldType;

  /// No description provided for @importFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败：{error}'**
  String importFailed(String error);

  /// No description provided for @overwriteImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'覆盖导入'**
  String get overwriteImportTitle;

  /// No description provided for @overwriteImportContent.
  ///
  /// In zh, this message translates to:
  /// **'将覆盖当前 {count} 项持久化配置，包含账号、主题、阅读器设置和本地阅读记录。{backupTime}\n\n临时缓存不会导入，当前配置会被替换。是否继续？'**
  String overwriteImportContent(int count, String backupTime);

  /// No description provided for @backupTimeLine.
  ///
  /// In zh, this message translates to:
  /// **'\n\n备份时间：{time}'**
  String backupTimeLine(String time);

  /// No description provided for @confirmImportButton.
  ///
  /// In zh, this message translates to:
  /// **'确认导入'**
  String get confirmImportButton;

  /// No description provided for @settingsImportedToast.
  ///
  /// In zh, this message translates to:
  /// **'配置已导入并覆盖本地设置'**
  String get settingsImportedToast;

  /// No description provided for @resetAppTitle.
  ///
  /// In zh, this message translates to:
  /// **'重置应用'**
  String get resetAppTitle;

  /// No description provided for @resetAppDesc.
  ///
  /// In zh, this message translates to:
  /// **'清除本地设置、账号、阅读记录和缓存，不会删除已下载的本地漫画文件'**
  String get resetAppDesc;

  /// No description provided for @resettingApp.
  ///
  /// In zh, this message translates to:
  /// **'正在重置...'**
  String get resettingApp;

  /// No description provided for @appResetToast.
  ///
  /// In zh, this message translates to:
  /// **'应用已重置，已清除 {count} 项本地数据'**
  String appResetToast(int count);

  /// No description provided for @resetFailed.
  ///
  /// In zh, this message translates to:
  /// **'重置失败：{error}'**
  String resetFailed(String error);

  /// No description provided for @exportSettingsContent.
  ///
  /// In zh, this message translates to:
  /// **'将复制 {count} 项持久化配置到剪贴板，导出内容为明文，请谨慎保管。'**
  String exportSettingsContent(int count);

  /// No description provided for @includeSensitiveSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'包含密码和 API 重要信息'**
  String get includeSensitiveSettingsTitle;

  /// No description provided for @noSensitiveSettingsFound.
  ///
  /// In zh, this message translates to:
  /// **'当前没有检测到已保存的敏感项'**
  String get noSensitiveSettingsFound;

  /// No description provided for @includeSensitiveSettingsDesc.
  ///
  /// In zh, this message translates to:
  /// **'将额外包含 {count} 项令牌、密码、API Key 或凭据信息'**
  String includeSensitiveSettingsDesc(int count);

  /// No description provided for @copyButton.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copyButton;

  /// No description provided for @pasteExportedSettingsHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴导出的配置 JSON'**
  String get pasteExportedSettingsHint;

  /// No description provided for @continueButton.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get continueButton;

  /// No description provided for @confirmResetAppTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认重置应用'**
  String get confirmResetAppTitle;

  /// No description provided for @resetAppWarning.
  ///
  /// In zh, this message translates to:
  /// **'此操作会清除应用本地保存的设置、账号、阅读记录和缓存，且无法撤销。'**
  String get resetAppWarning;

  /// No description provided for @resetAppInstruction.
  ///
  /// In zh, this message translates to:
  /// **'如需继续，请在下方输入框中输入“{text}”。'**
  String resetAppInstruction(String text);

  /// No description provided for @confirmTextLabel.
  ///
  /// In zh, this message translates to:
  /// **'确认文本'**
  String get confirmTextLabel;

  /// No description provided for @confirmResetButton.
  ///
  /// In zh, this message translates to:
  /// **'确认重置'**
  String get confirmResetButton;

  /// No description provided for @animeUnavailableToast.
  ///
  /// In zh, this message translates to:
  /// **'当前动漫暂时无法打开'**
  String get animeUnavailableToast;

  /// No description provided for @animeEditorRecommend.
  ///
  /// In zh, this message translates to:
  /// **'编辑推荐'**
  String get animeEditorRecommend;

  /// No description provided for @animeRecentUpdate.
  ///
  /// In zh, this message translates to:
  /// **'最近更新'**
  String get animeRecentUpdate;

  /// No description provided for @animeClassicRecommend.
  ///
  /// In zh, this message translates to:
  /// **'经典推荐'**
  String get animeClassicRecommend;

  /// No description provided for @animeClassicAnimation.
  ///
  /// In zh, this message translates to:
  /// **'经典动画'**
  String get animeClassicAnimation;

  /// No description provided for @animeHotAnime.
  ///
  /// In zh, this message translates to:
  /// **'热门动漫'**
  String get animeHotAnime;

  /// No description provided for @loginRequiredTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要登录'**
  String get loginRequiredTitle;

  /// No description provided for @playbackFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'播放失败'**
  String get playbackFailedTitle;

  /// No description provided for @viewLogButton.
  ///
  /// In zh, this message translates to:
  /// **'查看日志'**
  String get viewLogButton;

  /// No description provided for @errorLogTitle.
  ///
  /// In zh, this message translates to:
  /// **'错误日志'**
  String get errorLogTitle;

  /// No description provided for @noLogInfo.
  ///
  /// In zh, this message translates to:
  /// **'无日志信息'**
  String get noLogInfo;

  /// No description provided for @closeButton.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get closeButton;

  /// No description provided for @videoLinkTitle.
  ///
  /// In zh, this message translates to:
  /// **'视频链接'**
  String get videoLinkTitle;

  /// No description provided for @videoLinkPending.
  ///
  /// In zh, this message translates to:
  /// **'加载后显示视频链接'**
  String get videoLinkPending;

  /// No description provided for @copyVideoLinkButton.
  ///
  /// In zh, this message translates to:
  /// **'复制视频链接'**
  String get copyVideoLinkButton;

  /// No description provided for @openInBrowserButton.
  ///
  /// In zh, this message translates to:
  /// **'浏览器打开'**
  String get openInBrowserButton;

  /// No description provided for @switchLineTooltip.
  ///
  /// In zh, this message translates to:
  /// **'切换线路'**
  String get switchLineTooltip;

  /// No description provided for @profileCopyCredentialLabel.
  ///
  /// In zh, this message translates to:
  /// **'拷贝'**
  String get profileCopyCredentialLabel;

  /// No description provided for @profileHotCredentialLabel.
  ///
  /// In zh, this message translates to:
  /// **'热辣'**
  String get profileHotCredentialLabel;

  /// No description provided for @accountSwitchedToast.
  ///
  /// In zh, this message translates to:
  /// **'账号已切换'**
  String get accountSwitchedToast;

  /// No description provided for @switchAccountTitle.
  ///
  /// In zh, this message translates to:
  /// **'切换账号'**
  String get switchAccountTitle;

  /// No description provided for @addAccountButton.
  ///
  /// In zh, this message translates to:
  /// **'添加账号'**
  String get addAccountButton;

  /// No description provided for @switchAccountFailedToast.
  ///
  /// In zh, this message translates to:
  /// **'切换失败，请重试'**
  String get switchAccountFailedToast;

  /// No description provided for @logoutTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logoutTitle;

  /// No description provided for @logoutConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要退出登录吗？'**
  String get logoutConfirmContent;

  /// No description provided for @userInfoRefreshedToast.
  ///
  /// In zh, this message translates to:
  /// **'用户信息已刷新'**
  String get userInfoRefreshedToast;

  /// No description provided for @userInfoRefreshFailedToast.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败，请重试'**
  String get userInfoRefreshFailedToast;

  /// No description provided for @tokenUnavailableToast.
  ///
  /// In zh, this message translates to:
  /// **'暂无可复制的令牌'**
  String get tokenUnavailableToast;

  /// No description provided for @tokenCopiedToast.
  ///
  /// In zh, this message translates to:
  /// **'令牌已复制到剪贴板'**
  String get tokenCopiedToast;

  /// No description provided for @appearanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearanceTitle;

  /// No description provided for @appearanceLogoChanged.
  ///
  /// In zh, this message translates to:
  /// **'桌面图标已更换，可能需要重启应用后生效'**
  String get appearanceLogoChanged;

  /// No description provided for @appearanceColorPickerHeading.
  ///
  /// In zh, this message translates to:
  /// **'点击色盘选择一个自定义主题色'**
  String get appearanceColorPickerHeading;

  /// No description provided for @appearanceColorPickerSubheading.
  ///
  /// In zh, this message translates to:
  /// **'拖动取色点，实时预览主题色'**
  String get appearanceColorPickerSubheading;

  /// No description provided for @appearanceThemeColorUpdated.
  ///
  /// In zh, this message translates to:
  /// **'主题配色已更新为 {color}'**
  String appearanceThemeColorUpdated(String color);

  /// No description provided for @appearanceBottomNavShowLabels.
  ///
  /// In zh, this message translates to:
  /// **'底部导航栏显示文字'**
  String get appearanceBottomNavShowLabels;

  /// No description provided for @appearanceBottomNavLabelMode.
  ///
  /// In zh, this message translates to:
  /// **'底部导航栏文字'**
  String get appearanceBottomNavLabelMode;

  /// No description provided for @appearanceBottomNavLabelModeSelectedOnly.
  ///
  /// In zh, this message translates to:
  /// **'选中时显示'**
  String get appearanceBottomNavLabelModeSelectedOnly;

  /// No description provided for @appearanceBottomNavLabelModeSelectedOnlyDesc.
  ///
  /// In zh, this message translates to:
  /// **'胶囊导航，仅选中项显示文字'**
  String get appearanceBottomNavLabelModeSelectedOnlyDesc;

  /// No description provided for @appearanceBottomNavLabelModeHidden.
  ///
  /// In zh, this message translates to:
  /// **'不显示文字'**
  String get appearanceBottomNavLabelModeHidden;

  /// No description provided for @appearanceBottomNavLabelModeHiddenDesc.
  ///
  /// In zh, this message translates to:
  /// **'胶囊导航，只显示图标'**
  String get appearanceBottomNavLabelModeHiddenDesc;

  /// No description provided for @appearanceBottomNavLabelModeAlways.
  ///
  /// In zh, this message translates to:
  /// **'始终显示文字'**
  String get appearanceBottomNavLabelModeAlways;

  /// No description provided for @appearanceBottomNavLabelModeAlwaysDesc.
  ///
  /// In zh, this message translates to:
  /// **'经典导航，文字显示在图标下方'**
  String get appearanceBottomNavLabelModeAlwaysDesc;

  /// No description provided for @appearanceNavOrder.
  ///
  /// In zh, this message translates to:
  /// **'导航栏顺序'**
  String get appearanceNavOrder;

  /// No description provided for @appearanceNavOrderDragHint.
  ///
  /// In zh, this message translates to:
  /// **'长按可拖放排序'**
  String get appearanceNavOrderDragHint;

  /// No description provided for @appearanceAppIcon.
  ///
  /// In zh, this message translates to:
  /// **'应用图标'**
  String get appearanceAppIcon;

  /// No description provided for @appearanceAppIconRestartHint.
  ///
  /// In zh, this message translates to:
  /// **'更换后重启应用生效'**
  String get appearanceAppIconRestartHint;

  /// No description provided for @appearanceRefreshRateTitle.
  ///
  /// In zh, this message translates to:
  /// **'屏幕刷新率'**
  String get appearanceRefreshRateTitle;

  /// No description provided for @appearanceThemeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get appearanceThemeMode;

  /// No description provided for @appearanceSystemMode.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get appearanceSystemMode;

  /// No description provided for @appearanceLightMode.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get appearanceLightMode;

  /// No description provided for @appearanceDarkMode.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get appearanceDarkMode;

  /// No description provided for @appearanceDarkCoverBrightness.
  ///
  /// In zh, this message translates to:
  /// **'暗色模式封面亮度'**
  String get appearanceDarkCoverBrightness;

  /// No description provided for @appearanceDarkCoverBrightnessDesc.
  ///
  /// In zh, this message translates to:
  /// **'暗色模式下降低各个界面的卡片封面亮度'**
  String get appearanceDarkCoverBrightnessDesc;

  /// No description provided for @appearanceShadowTitle.
  ///
  /// In zh, this message translates to:
  /// **'阴影'**
  String get appearanceShadowTitle;

  /// No description provided for @appearanceCardShadowSize.
  ///
  /// In zh, this message translates to:
  /// **'统一阴影大小'**
  String get appearanceCardShadowSize;

  /// No description provided for @appearanceCardShadowSizeDesc.
  ///
  /// In zh, this message translates to:
  /// **'统一调整应用内普通卡片的阴影大小'**
  String get appearanceCardShadowSizeDesc;

  /// No description provided for @appearanceDefaultFontSize.
  ///
  /// In zh, this message translates to:
  /// **'默认字体大小'**
  String get appearanceDefaultFontSize;

  /// No description provided for @appearanceDefaultFontSizeDesc.
  ///
  /// In zh, this message translates to:
  /// **'当前默认正文为 14；标题与辅助文字会按比例调整'**
  String get appearanceDefaultFontSizeDesc;

  /// No description provided for @appearanceThemeStyle.
  ///
  /// In zh, this message translates to:
  /// **'主题风格'**
  String get appearanceThemeStyle;

  /// No description provided for @appearanceCurrentStyle.
  ///
  /// In zh, this message translates to:
  /// **'当前风格：{label} · {description}'**
  String appearanceCurrentStyle(String label, String description);

  /// No description provided for @appearanceThemeColor.
  ///
  /// In zh, this message translates to:
  /// **'主题配色'**
  String get appearanceThemeColor;

  /// No description provided for @appearanceThemeColorDesc.
  ///
  /// In zh, this message translates to:
  /// **'点击颜色块切换主题色，带勾选的为当前配色。'**
  String get appearanceThemeColorDesc;

  /// No description provided for @appearanceRefreshRateRequested.
  ///
  /// In zh, this message translates to:
  /// **'已请求刷新率 {rate}'**
  String appearanceRefreshRateRequested(String rate);

  /// No description provided for @appearanceRefreshRateSaved.
  ///
  /// In zh, this message translates to:
  /// **'刷新率偏好已保存'**
  String get appearanceRefreshRateSaved;

  /// No description provided for @appearanceRefreshRateLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'获取设备刷新率失败：{error}'**
  String appearanceRefreshRateLoadFailed(String error);

  /// No description provided for @appearanceUnknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get appearanceUnknownError;

  /// No description provided for @appearanceAutoSystem.
  ///
  /// In zh, this message translates to:
  /// **'自动（跟随系统）'**
  String get appearanceAutoSystem;

  /// No description provided for @appearanceRefreshRateCurrent.
  ///
  /// In zh, this message translates to:
  /// **'{rate}Hz（当前）'**
  String appearanceRefreshRateCurrent(int rate);

  /// No description provided for @appearanceApplyingRefreshRate.
  ///
  /// In zh, this message translates to:
  /// **'正在应用 {rate}'**
  String appearanceApplyingRefreshRate(String rate);

  /// No description provided for @appearanceRefreshRateDesc.
  ///
  /// In zh, this message translates to:
  /// **'实际生效取决于系统和屏幕，部分设备可能需要重启应用后完全生效。'**
  String get appearanceRefreshRateDesc;

  /// No description provided for @appearanceDefaultFontRestored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复系统默认字体，重启应用后完全生效'**
  String get appearanceDefaultFontRestored;

  /// No description provided for @appearanceFontChanged.
  ///
  /// In zh, this message translates to:
  /// **'字体已切换为 {font}'**
  String appearanceFontChanged(String font);

  /// No description provided for @appearanceFontLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载字体失败：{error}'**
  String appearanceFontLoadFailed(String error);

  /// No description provided for @appearanceAppFont.
  ///
  /// In zh, this message translates to:
  /// **'应用字体'**
  String get appearanceAppFont;

  /// No description provided for @appearanceSystemDefault.
  ///
  /// In zh, this message translates to:
  /// **'系统默认'**
  String get appearanceSystemDefault;

  /// No description provided for @appearanceChooseFont.
  ///
  /// In zh, this message translates to:
  /// **'选择字体'**
  String get appearanceChooseFont;

  /// No description provided for @appearanceSearchFont.
  ///
  /// In zh, this message translates to:
  /// **'搜索字体'**
  String get appearanceSearchFont;

  /// No description provided for @appearanceFontDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除字体'**
  String get appearanceFontDeleteTitle;

  /// No description provided for @appearanceFontDeleteContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除字体 {fontId} 吗？删除后将恢复为系统默认字体。'**
  String appearanceFontDeleteContent(String fontId);

  /// No description provided for @appearanceFontNeedDownload.
  ///
  /// In zh, this message translates to:
  /// **'请先下载字体后再使用'**
  String get appearanceFontNeedDownload;

  /// No description provided for @appearanceFontDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'{fontId} 下载完成'**
  String appearanceFontDownloaded(String fontId);

  /// No description provided for @appearanceFontDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'字体下载失败'**
  String get appearanceFontDownloadFailed;

  /// No description provided for @appearanceFontDownloadTooltip.
  ///
  /// In zh, this message translates to:
  /// **'下载字体'**
  String get appearanceFontDownloadTooltip;

  /// No description provided for @appearanceFontNotDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'未下载'**
  String get appearanceFontNotDownloaded;

  /// No description provided for @appearanceFontDownloadTitle.
  ///
  /// In zh, this message translates to:
  /// **'下载字体'**
  String get appearanceFontDownloadTitle;

  /// No description provided for @appearanceFontDownloadPrompt.
  ///
  /// In zh, this message translates to:
  /// **'字体 {fontName} 尚未下载，是否现在下载并应用？'**
  String appearanceFontDownloadPrompt(String fontName);

  /// No description provided for @appearanceAddCustomFont.
  ///
  /// In zh, this message translates to:
  /// **'添加自定义字体'**
  String get appearanceAddCustomFont;

  /// No description provided for @appearanceCustomFontNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'字体名称'**
  String get appearanceCustomFontNameLabel;

  /// No description provided for @appearanceCustomFontNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：Source Han Sans'**
  String get appearanceCustomFontNameHint;

  /// No description provided for @appearanceCustomFontUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'字体下载链接'**
  String get appearanceCustomFontUrlLabel;

  /// No description provided for @appearanceCustomFontUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com/font.ttf'**
  String get appearanceCustomFontUrlHint;

  /// No description provided for @appearanceCustomFontInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请填写有效的字体名称和 HTTP(S) 下载链接'**
  String get appearanceCustomFontInvalid;

  /// No description provided for @appearanceCustomFontAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加字体 {fontName}'**
  String appearanceCustomFontAdded(String fontName);

  /// No description provided for @appearanceCustomFontBadge.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get appearanceCustomFontBadge;

  /// No description provided for @appearanceCustomFontRemoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除自定义字体'**
  String get appearanceCustomFontRemoveTitle;

  /// No description provided for @appearanceCustomFontRemoveContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要移除自定义字体 {fontName} 吗？本地文件也会被删除。'**
  String appearanceCustomFontRemoveContent(String fontName);

  /// No description provided for @cacheFontSection.
  ///
  /// In zh, this message translates to:
  /// **'字体缓存'**
  String get cacheFontSection;

  /// No description provided for @cacheFontLabel.
  ///
  /// In zh, this message translates to:
  /// **'下载字体'**
  String get cacheFontLabel;

  /// No description provided for @cacheFontDesc.
  ///
  /// In zh, this message translates to:
  /// **'已下载的字体文件，删除后将恢复为系统默认字体。'**
  String get cacheFontDesc;

  /// No description provided for @cacheClearFontTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除字体缓存'**
  String get cacheClearFontTitle;

  /// No description provided for @cacheClearFontContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除 {count} 个字体文件（{size}）吗？删除后将恢复为系统默认字体。'**
  String cacheClearFontContent(int count, String size);

  /// No description provided for @cacheFontClearedToast.
  ///
  /// In zh, this message translates to:
  /// **'字体缓存已清除'**
  String get cacheFontClearedToast;

  /// No description provided for @cacheFontDataTarget.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个字体文件（{size}）'**
  String cacheFontDataTarget(int count, String size);

  /// No description provided for @networkTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get networkTitle;

  /// No description provided for @networkApiRouteTitle.
  ///
  /// In zh, this message translates to:
  /// **'API 线路'**
  String get networkApiRouteTitle;

  /// No description provided for @networkSelectionMode.
  ///
  /// In zh, this message translates to:
  /// **'选择模式'**
  String get networkSelectionMode;

  /// No description provided for @networkModeRoute.
  ///
  /// In zh, this message translates to:
  /// **'线路'**
  String get networkModeRoute;

  /// No description provided for @networkModeFixedNode.
  ///
  /// In zh, this message translates to:
  /// **'固定节点'**
  String get networkModeFixedNode;

  /// No description provided for @networkTestOtherLatency.
  ///
  /// In zh, this message translates to:
  /// **'测试其他节点延迟'**
  String get networkTestOtherLatency;

  /// No description provided for @networkFixedNodeAutoSelected.
  ///
  /// In zh, this message translates to:
  /// **'测速后已选择延迟最低的节点'**
  String get networkFixedNodeAutoSelected;

  /// No description provided for @networkRouteLabel.
  ///
  /// In zh, this message translates to:
  /// **'线路 {index}'**
  String networkRouteLabel(int index);

  /// No description provided for @networkTestLatency.
  ///
  /// In zh, this message translates to:
  /// **'测试线路延迟'**
  String get networkTestLatency;

  /// No description provided for @networkTestingNodes.
  ///
  /// In zh, this message translates to:
  /// **'正在检测各节点...'**
  String get networkTestingNodes;

  /// No description provided for @networkNotTested.
  ///
  /// In zh, this message translates to:
  /// **'尚未进行检测'**
  String get networkNotTested;

  /// No description provided for @networkHighLatencyProxySuggestion.
  ///
  /// In zh, this message translates to:
  /// **'当前延迟较大，建议开启代理'**
  String get networkHighLatencyProxySuggestion;

  /// No description provided for @networkRateLimitMessage.
  ///
  /// In zh, this message translates to:
  /// **'请求过于频繁，已被限速，请稍后再试'**
  String get networkRateLimitMessage;

  /// No description provided for @networkRequestFailedCode.
  ///
  /// In zh, this message translates to:
  /// **'请求失败（code: {code}）'**
  String networkRequestFailedCode(String code);

  /// No description provided for @networkCopyLoginHost.
  ///
  /// In zh, this message translates to:
  /// **'拷贝登录'**
  String get networkCopyLoginHost;

  /// No description provided for @networkHotLoginHost.
  ///
  /// In zh, this message translates to:
  /// **'热辣登录'**
  String get networkHotLoginHost;

  /// No description provided for @networkFixedApiHost.
  ///
  /// In zh, this message translates to:
  /// **'固定接口'**
  String get networkFixedApiHost;

  /// No description provided for @networkSystemProxyNotDetected.
  ///
  /// In zh, this message translates to:
  /// **'系统代理：未检测到'**
  String get networkSystemProxyNotDetected;

  /// No description provided for @networkManualProxyNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'手动代理：未配置'**
  String get networkManualProxyNotConfigured;

  /// No description provided for @networkOtherRouteGroup.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get networkOtherRouteGroup;

  /// No description provided for @networkCollapseTestResults.
  ///
  /// In zh, this message translates to:
  /// **'收起测试结果'**
  String get networkCollapseTestResults;

  /// No description provided for @networkExpandTestResults.
  ///
  /// In zh, this message translates to:
  /// **'展开测试结果'**
  String get networkExpandTestResults;

  /// No description provided for @networkProxySettings.
  ///
  /// In zh, this message translates to:
  /// **'代理设置'**
  String get networkProxySettings;

  /// No description provided for @networkRefreshSystemProxy.
  ///
  /// In zh, this message translates to:
  /// **'重新检测系统代理'**
  String get networkRefreshSystemProxy;

  /// No description provided for @networkProxySystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get networkProxySystem;

  /// No description provided for @networkProxyManual.
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get networkProxyManual;

  /// No description provided for @networkCurrentProxy.
  ///
  /// In zh, this message translates to:
  /// **'当前代理'**
  String get networkCurrentProxy;

  /// No description provided for @networkProxyAddress.
  ///
  /// In zh, this message translates to:
  /// **'代理地址'**
  String get networkProxyAddress;

  /// No description provided for @networkProxyAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'127.0.0.1:7890 或 http://127.0.0.1:7890'**
  String get networkProxyAddressHint;

  /// No description provided for @networkSaveAndEnableManualProxy.
  ///
  /// In zh, this message translates to:
  /// **'保存并启用手动代理'**
  String get networkSaveAndEnableManualProxy;

  /// No description provided for @networkTestingGoogle.
  ///
  /// In zh, this message translates to:
  /// **'正在通过 {proxy} 访问 Google ...'**
  String networkTestingGoogle(String proxy);

  /// No description provided for @networkGoogleConnectivity.
  ///
  /// In zh, this message translates to:
  /// **'Google 连通性'**
  String get networkGoogleConnectivity;

  /// No description provided for @networkAdvancedSettings.
  ///
  /// In zh, this message translates to:
  /// **'高级设置'**
  String get networkAdvancedSettings;

  /// No description provided for @networkCopyAppVersion.
  ///
  /// In zh, this message translates to:
  /// **'COPY 请求版本号'**
  String get networkCopyAppVersion;

  /// No description provided for @networkCopyAutoUpdate.
  ///
  /// In zh, this message translates to:
  /// **'每天自动更新'**
  String get networkCopyAutoUpdate;

  /// No description provided for @networkCopyAutoUpdateNever.
  ///
  /// In zh, this message translates to:
  /// **'尚未更新'**
  String get networkCopyAutoUpdateNever;

  /// No description provided for @networkCopyAutoUpdateLast.
  ///
  /// In zh, this message translates to:
  /// **'上次更新：{time}'**
  String networkCopyAutoUpdateLast(String time);

  /// No description provided for @networkFill.
  ///
  /// In zh, this message translates to:
  /// **'填充'**
  String get networkFill;

  /// No description provided for @networkAverageTesting.
  ///
  /// In zh, this message translates to:
  /// **'平均：检测中'**
  String get networkAverageTesting;

  /// No description provided for @networkAverageTimeout.
  ///
  /// In zh, this message translates to:
  /// **'平均：超时'**
  String get networkAverageTimeout;

  /// No description provided for @networkAverageLatency.
  ///
  /// In zh, this message translates to:
  /// **'平均：{milliseconds} ms'**
  String networkAverageLatency(int milliseconds);

  /// No description provided for @networkNodeLabel.
  ///
  /// In zh, this message translates to:
  /// **'节点 {index}'**
  String networkNodeLabel(int index);

  /// No description provided for @networkTesting.
  ///
  /// In zh, this message translates to:
  /// **'检测中'**
  String get networkTesting;

  /// No description provided for @networkTimeout.
  ///
  /// In zh, this message translates to:
  /// **'超时'**
  String get networkTimeout;

  /// No description provided for @networkNoSystemProxyDetected.
  ///
  /// In zh, this message translates to:
  /// **'未检测到系统代理'**
  String get networkNoSystemProxyDetected;

  /// No description provided for @networkSystemProxyDetected.
  ///
  /// In zh, this message translates to:
  /// **'已检测到 {proxy}'**
  String networkSystemProxyDetected(String proxy);

  /// No description provided for @networkCopyAdvancedSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 COPY 高级设置'**
  String get networkCopyAdvancedSaved;

  /// No description provided for @networkCopyAdvancedReset.
  ///
  /// In zh, this message translates to:
  /// **'已重置 COPY 高级设置'**
  String get networkCopyAdvancedReset;

  /// No description provided for @networkCopyAutoFilled.
  ///
  /// In zh, this message translates to:
  /// **'已自动填充 COPY API 地址：{apiHost}，版本号：{version}'**
  String networkCopyAutoFilled(String apiHost, String version);

  /// No description provided for @networkAutoFillFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动填充失败：{error}'**
  String networkAutoFillFailed(String error);

  /// No description provided for @networkInvalidProxyAddress.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的代理地址，例如 127.0.0.1:7890'**
  String get networkInvalidProxyAddress;

  /// No description provided for @networkProxyEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用 {proxy}'**
  String networkProxyEnabled(String proxy);

  /// No description provided for @networkConnectionSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功，HTTP {statusCode}，{proxyRule}'**
  String networkConnectionSuccess(int statusCode, String proxyRule);

  /// No description provided for @networkConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败，HTTP {statusCode}，{proxyRule}'**
  String networkConnectionFailed(int statusCode, String proxyRule);

  /// No description provided for @networkConnectionTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接超时，{proxyRule}'**
  String networkConnectionTimeout(String proxyRule);

  /// No description provided for @networkProxyRuleError.
  ///
  /// In zh, this message translates to:
  /// **'{proxyRule}：{error}'**
  String networkProxyRuleError(String proxyRule, String error);

  /// No description provided for @networkTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'测试失败，{proxyRule}：{error}'**
  String networkTestFailed(String proxyRule, String error);

  /// No description provided for @networkStatusGood.
  ///
  /// In zh, this message translates to:
  /// **'网络通畅'**
  String get networkStatusGood;

  /// No description provided for @networkStatusGoodHint.
  ///
  /// In zh, this message translates to:
  /// **'当前最佳延迟 {ms} ms，状态良好'**
  String networkStatusGoodHint(int ms);

  /// No description provided for @networkStatusGoodFallback.
  ///
  /// In zh, this message translates to:
  /// **'连接正常，状态良好'**
  String get networkStatusGoodFallback;

  /// No description provided for @networkStatusWarn.
  ///
  /// In zh, this message translates to:
  /// **'延迟偏高'**
  String get networkStatusWarn;

  /// No description provided for @networkStatusWarnHint.
  ///
  /// In zh, this message translates to:
  /// **'当前延迟约 {ms} ms，建议开启代理'**
  String networkStatusWarnHint(int ms);

  /// No description provided for @networkStatusBad.
  ///
  /// In zh, this message translates to:
  /// **'连接异常'**
  String get networkStatusBad;

  /// No description provided for @networkStatusBusy.
  ///
  /// In zh, this message translates to:
  /// **'正在检测'**
  String get networkStatusBusy;

  /// No description provided for @networkStatusUnknown.
  ///
  /// In zh, this message translates to:
  /// **'尚未检测'**
  String get networkStatusUnknown;

  /// No description provided for @networkStatusUnknownHint.
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮测速，了解各节点延迟'**
  String get networkStatusUnknownHint;

  /// No description provided for @networkTestLatencyShort.
  ///
  /// In zh, this message translates to:
  /// **'测速'**
  String get networkTestLatencyShort;

  /// No description provided for @networkNodeGridRouteHint.
  ///
  /// In zh, this message translates to:
  /// **'选择一条线路，测速后自动切换到最快的'**
  String get networkNodeGridRouteHint;

  /// No description provided for @networkNodeGridFixedHint.
  ///
  /// In zh, this message translates to:
  /// **'点击节点卡片即可固定到该节点'**
  String get networkNodeGridFixedHint;

  /// No description provided for @networkModeFixedNodeShort.
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get networkModeFixedNodeShort;

  /// No description provided for @networkSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get networkSettings;

  /// No description provided for @networkSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'网络设置'**
  String get networkSettingsTitle;

  /// No description provided for @networkHistorySettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'节点历史记录'**
  String get networkHistorySettingsTitle;

  /// No description provided for @networkStatusAutoGoodHint.
  ///
  /// In zh, this message translates to:
  /// **'基于真实请求自动选择，状态健康'**
  String get networkStatusAutoGoodHint;

  /// No description provided for @aiConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI配置'**
  String get aiConfigTitle;

  /// No description provided for @aiConfigNewChat.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get aiConfigNewChat;

  /// No description provided for @aiConfigProvidersTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 供应商'**
  String get aiConfigProvidersTitle;

  /// No description provided for @aiConfigAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get aiConfigAdd;

  /// No description provided for @aiConfigProvidersDescription.
  ///
  /// In zh, this message translates to:
  /// **'支持任何 OpenAI 兼容接口；智谱清言作为内置预设保留，可为不同供应商分别保存 Base URL、API Key、模型和接口格式。'**
  String get aiConfigProvidersDescription;

  /// No description provided for @aiConfigEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get aiConfigEnabled;

  /// No description provided for @aiConfigDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已禁用'**
  String get aiConfigDisabled;

  /// No description provided for @aiConfigProviderSummary.
  ///
  /// In zh, this message translates to:
  /// **'{status} · {count} 个模型 · {format}\n{baseUrl}'**
  String aiConfigProviderSummary(
    String status,
    int count,
    String format,
    String baseUrl,
  );

  /// No description provided for @aiConfigEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get aiConfigEdit;

  /// No description provided for @aiConfigCustomProvider.
  ///
  /// In zh, this message translates to:
  /// **'自定义供应商'**
  String get aiConfigCustomProvider;

  /// No description provided for @aiConfigZhipuName.
  ///
  /// In zh, this message translates to:
  /// **'智谱清言'**
  String get aiConfigZhipuName;

  /// No description provided for @aiConfigAddModel.
  ///
  /// In zh, this message translates to:
  /// **'添加模型'**
  String get aiConfigAddModel;

  /// No description provided for @aiConfigModelIdLabel.
  ///
  /// In zh, this message translates to:
  /// **'模型 ID'**
  String get aiConfigModelIdLabel;

  /// No description provided for @aiConfigFillBaseUrlAndApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请先填写 Base URL 和 API Key'**
  String get aiConfigFillBaseUrlAndApiKey;

  /// No description provided for @aiConfigFetchModelsFailed.
  ///
  /// In zh, this message translates to:
  /// **'获取模型失败：{error}'**
  String aiConfigFetchModelsFailed(String error);

  /// No description provided for @aiConfigNoAvailableModels.
  ///
  /// In zh, this message translates to:
  /// **'未获取到可用模型'**
  String get aiConfigNoAvailableModels;

  /// No description provided for @aiConfigSelectModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get aiConfigSelectModel;

  /// No description provided for @aiConfigAddSelected.
  ///
  /// In zh, this message translates to:
  /// **'添加所选'**
  String get aiConfigAddSelected;

  /// No description provided for @aiConfigAddProvider.
  ///
  /// In zh, this message translates to:
  /// **'新增供应商'**
  String get aiConfigAddProvider;

  /// No description provided for @aiConfigEditProvider.
  ///
  /// In zh, this message translates to:
  /// **'编辑供应商'**
  String get aiConfigEditProvider;

  /// No description provided for @aiConfigProviderNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'供应商名称'**
  String get aiConfigProviderNameLabel;

  /// No description provided for @aiConfigCustomNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'自定义名称'**
  String get aiConfigCustomNameLabel;

  /// No description provided for @aiConfigCustomNameHint.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI / One API / 自定义'**
  String get aiConfigCustomNameHint;

  /// No description provided for @aiConfigApiFormatLabel.
  ///
  /// In zh, this message translates to:
  /// **'接口格式'**
  String get aiConfigApiFormatLabel;

  /// No description provided for @aiConfigDefaultModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'默认模型'**
  String get aiConfigDefaultModelLabel;

  /// No description provided for @aiConfigNoSelection.
  ///
  /// In zh, this message translates to:
  /// **'未选择'**
  String get aiConfigNoSelection;

  /// No description provided for @aiConfigFetch.
  ///
  /// In zh, this message translates to:
  /// **'获取'**
  String get aiConfigFetch;

  /// No description provided for @aiConfigClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get aiConfigClear;

  /// No description provided for @aiConfigGetZhipuApiKey.
  ///
  /// In zh, this message translates to:
  /// **'获取智谱 API 密钥'**
  String get aiConfigGetZhipuApiKey;

  /// No description provided for @aiConfigProviderSaved.
  ///
  /// In zh, this message translates to:
  /// **'供应商已保存'**
  String get aiConfigProviderSaved;

  /// No description provided for @aiConfigConfigureBaseUrlAndApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请先配置 Base URL 和 API 密钥'**
  String get aiConfigConfigureBaseUrlAndApiKey;

  /// No description provided for @aiConfigModelReturnedEmpty.
  ///
  /// In zh, this message translates to:
  /// **'(模型未返回内容)'**
  String get aiConfigModelReturnedEmpty;

  /// No description provided for @aiConfigRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求失败：{error}'**
  String aiConfigRequestFailed(String error);

  /// No description provided for @aiConfigPartialResponseError.
  ///
  /// In zh, this message translates to:
  /// **'{content}\n\n[出错：{error}]'**
  String aiConfigPartialResponseError(String content, String error);

  /// No description provided for @aiConfigSessionHistory.
  ///
  /// In zh, this message translates to:
  /// **'会话历史'**
  String get aiConfigSessionHistory;

  /// No description provided for @aiConfigNewSession.
  ///
  /// In zh, this message translates to:
  /// **'新会话'**
  String get aiConfigNewSession;

  /// No description provided for @aiConfigNoSessionHistory.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史会话'**
  String get aiConfigNoSessionHistory;

  /// No description provided for @aiConfigMessageCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条消息'**
  String aiConfigMessageCount(int count);

  /// No description provided for @aiConfigDeleteSession.
  ///
  /// In zh, this message translates to:
  /// **'删除会话'**
  String get aiConfigDeleteSession;

  /// No description provided for @aiConfigProviderConfig.
  ///
  /// In zh, this message translates to:
  /// **'接口配置'**
  String get aiConfigProviderConfig;

  /// No description provided for @aiConfigClearChat.
  ///
  /// In zh, this message translates to:
  /// **'清空对话'**
  String get aiConfigClearChat;

  /// No description provided for @aiConfigInputHint.
  ///
  /// In zh, this message translates to:
  /// **'说点什么…'**
  String get aiConfigInputHint;

  /// No description provided for @aiConfigSend.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get aiConfigSend;

  /// No description provided for @aiConfigReadyEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'配置AI后可以在章节评论中用于总结评论和屏蔽剧透'**
  String get aiConfigReadyEmptyHint;

  /// No description provided for @aiConfigSetupEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'先在右上角配置接口'**
  String get aiConfigSetupEmptyHint;

  /// No description provided for @aiLegacyDefaultPromptBasic.
  ///
  /// In zh, this message translates to:
  /// **'先梳理评论区的主流声音、分歧点、大家吐槽/夸赞的核心内容；之后直抒胸臆，大胆表达你的立场，好坏直接点明，不中和、不打太极；绝对不要虚构漫画剧情，所有内容都基于现有评论；语言干练接地气，用 Markdown 输出一份犀利总结，类似下面的格式：\n### 大家在聊什么 （不超过7项，取多数人讨论的，每一项字数保持在25字以内）\n- 很多人都表示...\n- 有些人觉得...\n- 个别人认为...\n### 我的评论\n（发表你的评论，简短10-20字左右，不要附和他人观点，不是对其他人的看法，而是直接说你自己的看法或吐槽，表现得自然一点）'**
  String get aiLegacyDefaultPromptBasic;

  /// No description provided for @aiDefaultPromptBasic.
  ///
  /// In zh, this message translates to:
  /// **'先梳理评论区的主流声音、分歧点、大家吐槽/夸赞的核心内容；之后直抒胸臆，大胆表达你的立场，好坏直接点明，不中和、不打太极；绝对不要虚构漫画剧情，所有内容都基于现有评论；语言干练接地气，用 Markdown 输出一份犀利总结，类似下面的格式：\n### 大家在聊什么 （不超过7项，取多数人讨论的，每一项字数保持在25字以内）\n- 角色A做了什么...\n- 很多人吐槽...\n- xxxx...\n### 我的评论\n（发表你的评论，简短10-20字左右，不要附和他人观点，不是对其他人的看法，而是直接说你自己的看法或吐槽，表现得自然一点）'**
  String get aiDefaultPromptBasic;

  /// No description provided for @aiSpoilerAnalysisPromptAppendix.
  ///
  /// In zh, this message translates to:
  /// **'【剧透分析附加要求】\n用户已开启剧透分析。请在遵循上方提示词的基础上，额外满足以下要求：\n- 正文总结中不要复述、描述、暗示或概括任何剧透内容；\n- 可以输出 **剧透警告**，但仅当存在剧透评论时才输出此段，且只能写\"本章评论中有 N（这个N是剧透的数量） 处涉及剧透，已遮罩\"这一句，绝对不要描述、暗示或概括任何剧情/转折/结局；如果没有任何剧透评论则整段省略。\n\n【剧透的判定标准 · 非常重要】\n只有同时满足以下全部条件的评论才应标记为剧透：\n- 明确透露（包含猜测，有些用户会通过猜测进行剧透）了尚未在当前章节及之前出场过的剧情走向、角色命运（死亡、复活、背叛等）或结局结果；\n- 普通的感想（如\"太好看了\"\"画风不错\"）、角色喜爱（如\"XX好帅\"）、对已发生情节的正常讨论、对后续的模糊期待（如\"期待下一话\"）【不算】剧透；\n【机读输出】用户消息中每条评论开头都是它的数字 id（形如 \"81216. xxx: ...\"）。在整篇输出的最末尾追加一个 fenced code block（用三个反引号包裹），里面只放一个 JSON 数字数组，列出【高度剧透嫌疑】的评论 id：\n```\n[81216, 81230]\n```\n如果没有任何高度剧透的评论，依然必须输出该代码块，数组为空：\n```\n[]\n```\n硬性要求：\n1) 必须是整篇输出的最后一段，下面不要再写任何字；\n2) 必须用三个反引号包裹（语言标识写不写都行）；\n3) 中括号里只能有数字和英文逗号，不要写解释、不要带 id= 前缀；\n4) 哪怕没有剧透也要写空数组 []，不能省略整个代码块；\n'**
  String get aiSpoilerAnalysisPromptAppendix;

  /// No description provided for @aiPromptBasicName.
  ///
  /// In zh, this message translates to:
  /// **'基础提示词'**
  String get aiPromptBasicName;

  /// No description provided for @noticeCenterTitle.
  ///
  /// In zh, this message translates to:
  /// **'通知中心'**
  String get noticeCenterTitle;

  /// No description provided for @downloadCenterTitle.
  ///
  /// In zh, this message translates to:
  /// **'下载中心'**
  String get downloadCenterTitle;

  /// No description provided for @browseHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'浏览记录'**
  String get browseHistoryTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get aboutTitle;

  /// No description provided for @notLoggedInTitle.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get notLoggedInTitle;

  /// No description provided for @loginPromptSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'点击登录以使用书架等功能'**
  String get loginPromptSubtitle;

  /// No description provided for @refreshUserButton.
  ///
  /// In zh, this message translates to:
  /// **'刷新用户'**
  String get refreshUserButton;

  /// No description provided for @switchAccountButton.
  ///
  /// In zh, this message translates to:
  /// **'切换账号'**
  String get switchAccountButton;

  /// No description provided for @copyTokenButton.
  ///
  /// In zh, this message translates to:
  /// **'复制令牌'**
  String get copyTokenButton;

  /// No description provided for @appDisclaimerIntro.
  ///
  /// In zh, this message translates to:
  /// **'请在使用本应用前仔细阅读以下声明：'**
  String get appDisclaimerIntro;

  /// No description provided for @appDisclaimerItem1.
  ///
  /// In zh, this message translates to:
  /// **'本应用（以下简称\"本软件\"）系独立开发的非官方第三方客户端，与任何内容平台、出版商或权利人均无隶属、合作或代理关系。'**
  String get appDisclaimerItem1;

  /// No description provided for @appDisclaimerItem2.
  ///
  /// In zh, this message translates to:
  /// **'本软件不生产、上传、存储、编辑、修改、推荐或预先审查任何具体内容。所有内容均来源于第三方平台公开接口或可访问资源，其合法性、准确性、完整性及合规性由相应内容提供方独立负责。'**
  String get appDisclaimerItem2;

  /// No description provided for @appDisclaimerItem3.
  ///
  /// In zh, this message translates to:
  /// **'本软件所展示的内容可能包含成人向、暴力、恐怖或其他不适宜未成年人浏览的信息。您确认您已年满 18 周岁，且您所在地法律法规允许您访问此类内容。如您不符合前述条件，请立即停止使用并卸载本软件。'**
  String get appDisclaimerItem3;

  /// No description provided for @appDisclaimerItem4.
  ///
  /// In zh, this message translates to:
  /// **'您应自行判断所浏览内容是否适合，并确保您的使用行为完全符合您所在地现行有效的法律法规。因您使用本软件而产生的一切法律后果由您自行承担。'**
  String get appDisclaimerItem4;

  /// No description provided for @appDisclaimerItem5.
  ///
  /// In zh, this message translates to:
  /// **'如任何第三方内容涉嫌侵犯他人合法权益或违反法律法规，权利人可通过本软件提供的联系方式向开发者发送有效通知，开发者将在合理期限内核实并采取必要措施。'**
  String get appDisclaimerItem5;

  /// No description provided for @appDisclaimerItem6.
  ///
  /// In zh, this message translates to:
  /// **'本软件按\"现状\"提供，开发者不对其功能性、可用性、准确性或可靠性作出任何明示或默示的保证。在任何情况下，开发者均不对因使用或无法使用本软件而产生的任何直接、间接、附带、特殊或后果性损害承担责任。'**
  String get appDisclaimerItem6;

  /// No description provided for @appDisclaimerFooter.
  ///
  /// In zh, this message translates to:
  /// **'继续使用本软件，即表示您已仔细阅读、充分理解并同意接受上述全部条款的约束。如您不同意任一条款，请立即停止使用并卸载本软件。'**
  String get appDisclaimerFooter;

  /// No description provided for @profileCurrentSelectedCredential.
  ///
  /// In zh, this message translates to:
  /// **'当前已选'**
  String get profileCurrentSelectedCredential;

  /// No description provided for @profileRemoveAccountTooltip.
  ///
  /// In zh, this message translates to:
  /// **'移除账号'**
  String get profileRemoveAccountTooltip;

  /// No description provided for @profileAccountRemovedToast.
  ///
  /// In zh, this message translates to:
  /// **'已移除 {username}'**
  String profileAccountRemovedToast(String username);

  /// No description provided for @profileRegisterSuccessLoginToast.
  ///
  /// In zh, this message translates to:
  /// **'注册成功，请登录'**
  String get profileRegisterSuccessLoginToast;

  /// No description provided for @profileUsernamePasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名和密码'**
  String get profileUsernamePasswordRequired;

  /// No description provided for @profileLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败'**
  String get profileLoginFailed;

  /// No description provided for @profileTokenRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入令牌'**
  String get profileTokenRequired;

  /// No description provided for @profileTokenInvalidOrExpired.
  ///
  /// In zh, this message translates to:
  /// **'令牌无效或已过期'**
  String get profileTokenInvalidOrExpired;

  /// No description provided for @profileLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get profileLoginTitle;

  /// No description provided for @profileAccountPasswordLoginMode.
  ///
  /// In zh, this message translates to:
  /// **'账号密码'**
  String get profileAccountPasswordLoginMode;

  /// No description provided for @profileTokenLoginMode.
  ///
  /// In zh, this message translates to:
  /// **'令牌'**
  String get profileTokenLoginMode;

  /// No description provided for @profileSavedAccountsTitle.
  ///
  /// In zh, this message translates to:
  /// **'已保存账号'**
  String get profileSavedAccountsTitle;

  /// No description provided for @profileSavedAccountsHint.
  ///
  /// In zh, this message translates to:
  /// **'点按快速填充账号密码，右侧可移除'**
  String get profileSavedAccountsHint;

  /// No description provided for @profileUsernameLabel.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get profileUsernameLabel;

  /// No description provided for @profilePasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get profilePasswordLabel;

  /// No description provided for @profileTokenLabel.
  ///
  /// In zh, this message translates to:
  /// **'令牌 (Token)'**
  String get profileTokenLabel;

  /// No description provided for @profileTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴你的登录令牌'**
  String get profileTokenHint;

  /// No description provided for @profileRememberAccountLabel.
  ///
  /// In zh, this message translates to:
  /// **'记住账号'**
  String get profileRememberAccountLabel;

  /// No description provided for @profileRegisterHotMangaAccountButton.
  ///
  /// In zh, this message translates to:
  /// **'注册热辣漫画账号'**
  String get profileRegisterHotMangaAccountButton;

  /// No description provided for @profileLoginButton.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get profileLoginButton;

  /// No description provided for @profileRegisterInfoRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写完整注册信息'**
  String get profileRegisterInfoRequired;

  /// No description provided for @profilePasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get profilePasswordMismatch;

  /// No description provided for @profileSecurityQuestionRequired.
  ///
  /// In zh, this message translates to:
  /// **'请选择安全问题'**
  String get profileSecurityQuestionRequired;

  /// No description provided for @profileRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'注册失败'**
  String get profileRegisterFailed;

  /// No description provided for @profileOpenOfficialRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开官网注册页'**
  String get profileOpenOfficialRegisterFailed;

  /// No description provided for @profileConfirmPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'确认密码'**
  String get profileConfirmPasswordLabel;

  /// No description provided for @profileSecurityQuestionLabel.
  ///
  /// In zh, this message translates to:
  /// **'账号安全问题'**
  String get profileSecurityQuestionLabel;

  /// No description provided for @profileSecurityAnswerLabel.
  ///
  /// In zh, this message translates to:
  /// **'安全问题答案'**
  String get profileSecurityAnswerLabel;

  /// No description provided for @profileReloadSecurityQuestionsButton.
  ///
  /// In zh, this message translates to:
  /// **'重新加载安全问题'**
  String get profileReloadSecurityQuestionsButton;

  /// No description provided for @profileRegisterButton.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get profileRegisterButton;

  /// No description provided for @profileOfficialRegisterPrompt.
  ///
  /// In zh, this message translates to:
  /// **'去官网注册'**
  String get profileOfficialRegisterPrompt;

  /// No description provided for @profileHotMangaLabel.
  ///
  /// In zh, this message translates to:
  /// **'热辣漫画'**
  String get profileHotMangaLabel;

  /// No description provided for @profileCopyMangaLabel.
  ///
  /// In zh, this message translates to:
  /// **'拷贝漫画'**
  String get profileCopyMangaLabel;

  /// No description provided for @aboutQqGroupTitle.
  ///
  /// In zh, this message translates to:
  /// **'QQ交流群'**
  String get aboutQqGroupTitle;

  /// No description provided for @aboutJoinGroupButton.
  ///
  /// In zh, this message translates to:
  /// **'加入群聊'**
  String get aboutJoinGroupButton;

  /// No description provided for @aboutGroupNumberCopiedToast.
  ///
  /// In zh, this message translates to:
  /// **'已复制群号'**
  String get aboutGroupNumberCopiedToast;

  /// No description provided for @aboutMirrorPrefixTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置镜像源'**
  String get aboutMirrorPrefixTitle;

  /// No description provided for @aboutMirrorPrefixDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于更新与播放组件下载的镜像链接，会拼接在 GitHub 下载地址前。'**
  String get aboutMirrorPrefixDesc;

  /// No description provided for @aboutMirrorPrefixLabel.
  ///
  /// In zh, this message translates to:
  /// **'镜像源地址'**
  String get aboutMirrorPrefixLabel;

  /// No description provided for @aboutMirrorPrefixHelper.
  ///
  /// In zh, this message translates to:
  /// **'留空将恢复默认镜像源'**
  String get aboutMirrorPrefixHelper;

  /// No description provided for @aboutInvalidMirrorPrefix.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 http(s) 地址'**
  String get aboutInvalidMirrorPrefix;

  /// No description provided for @aboutRestoreDefaultButton.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get aboutRestoreDefaultButton;

  /// No description provided for @aboutSaveButton.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get aboutSaveButton;

  /// No description provided for @aboutMirrorPrefixSavedToast.
  ///
  /// In zh, this message translates to:
  /// **'镜像源已保存'**
  String get aboutMirrorPrefixSavedToast;

  /// No description provided for @aboutStableChannelShort.
  ///
  /// In zh, this message translates to:
  /// **'稳定版'**
  String get aboutStableChannelShort;

  /// No description provided for @aboutUpdateChannelTitle.
  ///
  /// In zh, this message translates to:
  /// **'更新渠道'**
  String get aboutUpdateChannelTitle;

  /// No description provided for @aboutStableChannelTitle.
  ///
  /// In zh, this message translates to:
  /// **'稳定版 (Stable)'**
  String get aboutStableChannelTitle;

  /// No description provided for @aboutStableChannelDesc.
  ///
  /// In zh, this message translates to:
  /// **'仅检查正式发布版本'**
  String get aboutStableChannelDesc;

  /// No description provided for @aboutBetaChannelTitle.
  ///
  /// In zh, this message translates to:
  /// **'预览版（Beta）'**
  String get aboutBetaChannelTitle;

  /// No description provided for @aboutBetaChannelDesc.
  ///
  /// In zh, this message translates to:
  /// **'从最新提交构建的版本，可能不稳定'**
  String get aboutBetaChannelDesc;

  /// No description provided for @aboutBetaChannelSwitchedTitle.
  ///
  /// In zh, this message translates to:
  /// **'已切换到预览版'**
  String get aboutBetaChannelSwitchedTitle;

  /// No description provided for @aboutBetaChannelSwitchedContent.
  ///
  /// In zh, this message translates to:
  /// **'预览版一般用于测试新功能或修复问题，可能存在更多问题。'**
  String get aboutBetaChannelSwitchedContent;

  /// No description provided for @aboutGotItButton.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get aboutGotItButton;

  /// No description provided for @aboutRepositoryLabel.
  ///
  /// In zh, this message translates to:
  /// **'仓库'**
  String get aboutRepositoryLabel;

  /// No description provided for @aboutFeedbackLabel.
  ///
  /// In zh, this message translates to:
  /// **'反馈'**
  String get aboutFeedbackLabel;

  /// No description provided for @aboutCommunityLabel.
  ///
  /// In zh, this message translates to:
  /// **'交流'**
  String get aboutCommunityLabel;

  /// No description provided for @aboutCheckUpdateTitle.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get aboutCheckUpdateTitle;

  /// No description provided for @aboutAutoCheckUpdateTitle.
  ///
  /// In zh, this message translates to:
  /// **'启动时检查更新'**
  String get aboutAutoCheckUpdateTitle;

  /// No description provided for @aboutLogTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get aboutLogTitle;

  /// No description provided for @aboutAcknowledgementTitle.
  ///
  /// In zh, this message translates to:
  /// **'致谢'**
  String get aboutAcknowledgementTitle;

  /// No description provided for @acknowledgementThanksTitle.
  ///
  /// In zh, this message translates to:
  /// **'感谢以下服务与项目的支持'**
  String get acknowledgementThanksTitle;

  /// No description provided for @acknowledgementDandanplayTitle.
  ///
  /// In zh, this message translates to:
  /// **'弹弹play'**
  String get acknowledgementDandanplayTitle;

  /// No description provided for @acknowledgementDandanplayDesc.
  ///
  /// In zh, this message translates to:
  /// **'提供弹幕服务'**
  String get acknowledgementDandanplayDesc;

  /// No description provided for @acknowledgementZhconvertTitle.
  ///
  /// In zh, this message translates to:
  /// **'繁化姬'**
  String get acknowledgementZhconvertTitle;

  /// No description provided for @acknowledgementZhconvertDesc.
  ///
  /// In zh, this message translates to:
  /// **'提供简体化服务'**
  String get acknowledgementZhconvertDesc;

  /// No description provided for @aboutLicenseTitle.
  ///
  /// In zh, this message translates to:
  /// **'许可证'**
  String get aboutLicenseTitle;

  /// No description provided for @licenseMitSummary.
  ///
  /// In zh, this message translates to:
  /// **'本项目采用 MIT 开源许可证'**
  String get licenseMitSummary;

  /// No description provided for @cacheDeleteEntryTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除缓存项'**
  String get cacheDeleteEntryTitle;

  /// No description provided for @cacheDeleteEntryContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除 {key} 吗？此操作不可恢复。'**
  String cacheDeleteEntryContent(String key);

  /// No description provided for @cacheEntryDeletedToast.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {key}'**
  String cacheEntryDeletedToast(String key);

  /// No description provided for @cacheDeleteFailedToast.
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{error}'**
  String cacheDeleteFailedToast(String error);

  /// No description provided for @cacheLocalDataTarget.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项本地数据'**
  String cacheLocalDataTarget(int count);

  /// No description provided for @cacheImageDataTarget.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个图片缓存（{size}）'**
  String cacheImageDataTarget(int count, String size);

  /// No description provided for @cacheMediaKitDataTarget.
  ///
  /// In zh, this message translates to:
  /// **'播放组件（{size}）'**
  String cacheMediaKitDataTarget(String size);

  /// No description provided for @cacheDeleteSelectedTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除选中缓存'**
  String get cacheDeleteSelectedTitle;

  /// No description provided for @cacheDeleteSelectedContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除选中卡片中的 {targets} 吗？此操作不可恢复。'**
  String cacheDeleteSelectedContent(String targets);

  /// No description provided for @cacheSelectedDeletedToast.
  ///
  /// In zh, this message translates to:
  /// **'已删除选中缓存'**
  String get cacheSelectedDeletedToast;

  /// No description provided for @cacheNoImageCacheToClear.
  ///
  /// In zh, this message translates to:
  /// **'暂无可清理的图片缓存'**
  String get cacheNoImageCacheToClear;

  /// No description provided for @cacheClearImageCacheTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空图片缓存'**
  String get cacheClearImageCacheTitle;

  /// No description provided for @cacheClearImageCacheContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空 {label} 吗？将删除 {fileCount} 个文件，释放约 {size}。'**
  String cacheClearImageCacheContent(String label, int fileCount, String size);

  /// No description provided for @cacheClearButton.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get cacheClearButton;

  /// No description provided for @cacheClearDataSectionContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空 {sectionLabel} 中的所有数据吗？'**
  String cacheClearDataSectionContent(String sectionLabel);

  /// No description provided for @cacheImageCacheClearedToast.
  ///
  /// In zh, this message translates to:
  /// **'已清空 {label}'**
  String cacheImageCacheClearedToast(String label);

  /// No description provided for @cacheCleanFailedToast.
  ///
  /// In zh, this message translates to:
  /// **'清理失败：{error}'**
  String cacheCleanFailedToast(String error);

  /// No description provided for @cacheReaderImageLabel.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存 / 漫画阅读器'**
  String get cacheReaderImageLabel;

  /// No description provided for @cacheReaderImageDesc.
  ///
  /// In zh, this message translates to:
  /// **'漫画章节图片缓存。再次打开读过的章节时，图片会优先从这里读取。'**
  String get cacheReaderImageDesc;

  /// No description provided for @cacheDefaultImageLabel.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存 / 封面与头像'**
  String get cacheDefaultImageLabel;

  /// No description provided for @cacheDefaultImageDesc.
  ///
  /// In zh, this message translates to:
  /// **'封面、头像等 CachedNetworkImage 默认使用的图片缓存。'**
  String get cacheDefaultImageDesc;

  /// No description provided for @cacheMediaKitLabel.
  ///
  /// In zh, this message translates to:
  /// **'播放组件 / media_kit'**
  String get cacheMediaKitLabel;

  /// No description provided for @cacheMediaKitDesc.
  ///
  /// In zh, this message translates to:
  /// **'动漫播放器原生库（libmpv 等）。首次播放时按需下载；删除后下次播放会重新下载。'**
  String get cacheMediaKitDesc;

  /// No description provided for @cacheMediaKitSection.
  ///
  /// In zh, this message translates to:
  /// **'播放组件'**
  String get cacheMediaKitSection;

  /// No description provided for @cacheNoMediaKitToClear.
  ///
  /// In zh, this message translates to:
  /// **'尚未下载播放组件'**
  String get cacheNoMediaKitToClear;

  /// No description provided for @cacheClearMediaKitTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除播放组件'**
  String get cacheClearMediaKitTitle;

  /// No description provided for @cacheClearMediaKitContent.
  ///
  /// In zh, this message translates to:
  /// **'确定删除已下载的播放组件吗？将删除 {fileCount} 个文件，释放约 {size}。下次播放动漫时会重新下载。'**
  String cacheClearMediaKitContent(int fileCount, String size);

  /// No description provided for @cacheMediaKitClearedToast.
  ///
  /// In zh, this message translates to:
  /// **'已删除播放组件'**
  String get cacheMediaKitClearedToast;

  /// No description provided for @cacheMediaKitVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'组件版本'**
  String get cacheMediaKitVersionLabel;

  /// No description provided for @commentSettingsEditBuiltInPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑内置提示词'**
  String get commentSettingsEditBuiltInPromptTitle;

  /// No description provided for @commentSettingsEditPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑提示词'**
  String get commentSettingsEditPromptTitle;

  /// No description provided for @commentSettingsAddPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加提示词'**
  String get commentSettingsAddPromptTitle;

  /// No description provided for @commentSettingsNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get commentSettingsNameLabel;

  /// No description provided for @commentSettingsPromptLabel.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get commentSettingsPromptLabel;

  /// No description provided for @commentSettingsResetButton.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get commentSettingsResetButton;

  /// No description provided for @commentSettingsSaveButton.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commentSettingsSaveButton;

  /// No description provided for @commentSettingsAddButton.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get commentSettingsAddButton;

  /// No description provided for @commentSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'评论区设置'**
  String get commentSettingsTitle;

  /// No description provided for @commentSettingsLayoutSection.
  ///
  /// In zh, this message translates to:
  /// **'布局'**
  String get commentSettingsLayoutSection;

  /// No description provided for @commentSettingsCompactLayout.
  ///
  /// In zh, this message translates to:
  /// **'紧凑布局'**
  String get commentSettingsCompactLayout;

  /// No description provided for @commentSettingsListLayout.
  ///
  /// In zh, this message translates to:
  /// **'列表布局'**
  String get commentSettingsListLayout;

  /// No description provided for @commentSettingsShowAvatar.
  ///
  /// In zh, this message translates to:
  /// **'显示头像'**
  String get commentSettingsShowAvatar;

  /// No description provided for @commentSettingsShowUserName.
  ///
  /// In zh, this message translates to:
  /// **'显示用户名'**
  String get commentSettingsShowUserName;

  /// No description provided for @commentSettingsShowCommentTime.
  ///
  /// In zh, this message translates to:
  /// **'显示评论时间'**
  String get commentSettingsShowCommentTime;

  /// No description provided for @commentSettingsPreloadTitle.
  ///
  /// In zh, this message translates to:
  /// **'预加载评论'**
  String get commentSettingsPreloadTitle;

  /// No description provided for @commentSettingsPreloadDesc.
  ///
  /// In zh, this message translates to:
  /// **'进入章节时提前加载评论并显示数量'**
  String get commentSettingsPreloadDesc;

  /// No description provided for @commentSettingsAutoLoadAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动加载全部评论'**
  String get commentSettingsAutoLoadAllTitle;

  /// No description provided for @commentSettingsAutoLoadAllDesc.
  ///
  /// In zh, this message translates to:
  /// **'打开评论区时自动加载所有评论'**
  String get commentSettingsAutoLoadAllDesc;

  /// No description provided for @commentSettingsFontSizeTitle.
  ///
  /// In zh, this message translates to:
  /// **'评论内容字体大小'**
  String get commentSettingsFontSizeTitle;

  /// No description provided for @chapterCommentsNoSummaryComments.
  ///
  /// In zh, this message translates to:
  /// **'当前没有可总结的评论'**
  String get chapterCommentsNoSummaryComments;

  /// No description provided for @chapterCommentsEnableAiSummaryFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先在评论区设置中启用 AI 总结'**
  String get chapterCommentsEnableAiSummaryFirst;

  /// No description provided for @chapterCommentsPromptComicLine.
  ///
  /// In zh, this message translates to:
  /// **'漫画：{comicName}\n'**
  String chapterCommentsPromptComicLine(String comicName);

  /// No description provided for @chapterCommentsPromptUser.
  ///
  /// In zh, this message translates to:
  /// **'{comicLine}章节：{chapterName}\n共 {count} 条不同评论（相同内容已合并）。每条行首数字为该评论的 id：\n\n{snippets}'**
  String chapterCommentsPromptUser(
    String comicLine,
    String chapterName,
    int count,
    String snippets,
  );

  /// No description provided for @chapterCommentsMergedSnippet.
  ///
  /// In zh, this message translates to:
  /// **'{id}. [{count}人] {text}\n'**
  String chapterCommentsMergedSnippet(int id, int count, String text);

  /// No description provided for @chapterCommentsSingleSnippet.
  ///
  /// In zh, this message translates to:
  /// **'{id}. {userName}: {text}\n'**
  String chapterCommentsSingleSnippet(int id, String userName, String text);

  /// No description provided for @chapterCommentsSnippetsTruncated.
  ///
  /// In zh, this message translates to:
  /// **'…（已截断，共 {count} 条不同评论）'**
  String chapterCommentsSnippetsTruncated(int count);

  /// No description provided for @chapterCommentsDioException.
  ///
  /// In zh, this message translates to:
  /// **'Dio 异常'**
  String get chapterCommentsDioException;

  /// No description provided for @chapterCommentsCopyLog.
  ///
  /// In zh, this message translates to:
  /// **'复制日志'**
  String get chapterCommentsCopyLog;

  /// No description provided for @chapterCommentsLoginRequiredToPost.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再发表评论'**
  String get chapterCommentsLoginRequiredToPost;

  /// No description provided for @chapterCommentsLengthRange.
  ///
  /// In zh, this message translates to:
  /// **'评论字数需在 3-200 之间'**
  String get chapterCommentsLengthRange;

  /// No description provided for @chapterCommentsPosted.
  ///
  /// In zh, this message translates to:
  /// **'评论已发布'**
  String get chapterCommentsPosted;

  /// No description provided for @chapterCommentsPostTitle.
  ///
  /// In zh, this message translates to:
  /// **'发表评论'**
  String get chapterCommentsPostTitle;

  /// No description provided for @chapterCommentsPostHint.
  ///
  /// In zh, this message translates to:
  /// **'吐槽一下'**
  String get chapterCommentsPostHint;

  /// No description provided for @chapterCommentsLengthHelper.
  ///
  /// In zh, this message translates to:
  /// **'评论字数 3-200'**
  String get chapterCommentsLengthHelper;

  /// No description provided for @chapterCommentsLogCopied.
  ///
  /// In zh, this message translates to:
  /// **'日志已复制'**
  String get chapterCommentsLogCopied;

  /// No description provided for @chapterCommentsPublish.
  ///
  /// In zh, this message translates to:
  /// **'发布'**
  String get chapterCommentsPublish;

  /// No description provided for @chapterCommentsActionTitle.
  ///
  /// In zh, this message translates to:
  /// **'评论操作'**
  String get chapterCommentsActionTitle;

  /// No description provided for @chapterCommentsPlusOneSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'发送一条相同评论'**
  String get chapterCommentsPlusOneSubtitle;

  /// No description provided for @chapterCommentsBlockUser.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽用户'**
  String get chapterCommentsBlockUser;

  /// No description provided for @chapterCommentsHideUserComments.
  ///
  /// In zh, this message translates to:
  /// **'隐藏 {userName} 的评论'**
  String chapterCommentsHideUserComments(String userName);

  /// No description provided for @chapterCommentsCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get chapterCommentsCopied;

  /// No description provided for @chapterCommentsUserBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已屏蔽该用户'**
  String get chapterCommentsUserBlocked;

  /// No description provided for @chapterCommentsBlockUnnamedConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定屏蔽该用户吗？屏蔽后将不再显示其评论。'**
  String get chapterCommentsBlockUnnamedConfirm;

  /// No description provided for @chapterCommentsBlockNamedConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定屏蔽「{name}」吗？屏蔽后将不再显示其评论。\n可在评论区设置 → 黑名单中解除。'**
  String chapterCommentsBlockNamedConfirm(String name);

  /// No description provided for @chapterCommentsNoRemindAgain.
  ///
  /// In zh, this message translates to:
  /// **'不再提醒'**
  String get chapterCommentsNoRemindAgain;

  /// No description provided for @chapterCommentsBlock.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽'**
  String get chapterCommentsBlock;

  /// No description provided for @chapterCommentsPlusOneLengthInvalid.
  ///
  /// In zh, this message translates to:
  /// **'评论字数需在 3-200 之间，无法 +1'**
  String get chapterCommentsPlusOneLengthInvalid;

  /// No description provided for @chapterCommentsPlusOneSent.
  ///
  /// In zh, this message translates to:
  /// **'+1 已发送'**
  String get chapterCommentsPlusOneSent;

  /// No description provided for @chapterCommentsPostFailed.
  ///
  /// In zh, this message translates to:
  /// **'发表评论失败'**
  String get chapterCommentsPostFailed;

  /// No description provided for @chapterCommentsTitle.
  ///
  /// In zh, this message translates to:
  /// **'章节评论'**
  String get chapterCommentsTitle;

  /// No description provided for @chapterCommentsLoadAllTooltip.
  ///
  /// In zh, this message translates to:
  /// **'加载全部评论'**
  String get chapterCommentsLoadAllTooltip;

  /// No description provided for @chapterCommentsAiSummaryTooltip.
  ///
  /// In zh, this message translates to:
  /// **'AI 总结评论'**
  String get chapterCommentsAiSummaryTooltip;

  /// No description provided for @chapterCommentsRegenerateAiSummaryTooltip.
  ///
  /// In zh, this message translates to:
  /// **'重新生成 AI 总结'**
  String get chapterCommentsRegenerateAiSummaryTooltip;

  /// No description provided for @chapterCommentsSwitchToListLayout.
  ///
  /// In zh, this message translates to:
  /// **'切换为列表布局'**
  String get chapterCommentsSwitchToListLayout;

  /// No description provided for @chapterCommentsSwitchToCompactLayout.
  ///
  /// In zh, this message translates to:
  /// **'切换为紧凑布局'**
  String get chapterCommentsSwitchToCompactLayout;

  /// No description provided for @chapterCommentsTotalCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String chapterCommentsTotalCount(int count);

  /// No description provided for @chapterCommentsComment.
  ///
  /// In zh, this message translates to:
  /// **'评论'**
  String get chapterCommentsComment;

  /// No description provided for @chapterCommentsCatalog.
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get chapterCommentsCatalog;

  /// No description provided for @chapterCommentsNext.
  ///
  /// In zh, this message translates to:
  /// **'下一话'**
  String get chapterCommentsNext;

  /// No description provided for @chapterCommentsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'评论加载失败'**
  String get chapterCommentsLoadFailed;

  /// No description provided for @chapterCommentsEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有评论'**
  String get chapterCommentsEmptyTitle;

  /// No description provided for @chapterCommentsEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'这个章节暂时没人发言'**
  String get chapterCommentsEmptySubtitle;

  /// No description provided for @chapterCommentsSwitchModel.
  ///
  /// In zh, this message translates to:
  /// **'切换模型'**
  String get chapterCommentsSwitchModel;

  /// No description provided for @chapterCommentsCannotSwitchModelGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中无法切换模型'**
  String get chapterCommentsCannotSwitchModelGenerating;

  /// No description provided for @chapterCommentsModelSummary.
  ///
  /// In zh, this message translates to:
  /// **'{model} 总结'**
  String chapterCommentsModelSummary(String model);

  /// No description provided for @chapterCommentsActiveModel.
  ///
  /// In zh, this message translates to:
  /// **'当前模型：{provider} / {model}'**
  String chapterCommentsActiveModel(String provider, String model);

  /// No description provided for @chapterCommentsReasoning.
  ///
  /// In zh, this message translates to:
  /// **'思考过程'**
  String get chapterCommentsReasoning;

  /// No description provided for @chapterCommentsReasoningCollapsed.
  ///
  /// In zh, this message translates to:
  /// **'思考过程（已折叠）'**
  String get chapterCommentsReasoningCollapsed;

  /// No description provided for @chapterCommentsGenerating.
  ///
  /// In zh, this message translates to:
  /// **'正在生成中…'**
  String get chapterCommentsGenerating;

  /// No description provided for @chapterCommentsCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get chapterCommentsCollapse;

  /// No description provided for @chapterCommentsExpand.
  ///
  /// In zh, this message translates to:
  /// **'展开'**
  String get chapterCommentsExpand;

  /// No description provided for @chapterCommentsSummaryFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成失败：{error}'**
  String chapterCommentsSummaryFailed(String error);

  /// No description provided for @chapterCommentsStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get chapterCommentsStop;

  /// No description provided for @chapterCommentsRegenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get chapterCommentsRegenerate;

  /// No description provided for @chapterCommentsClearSummary.
  ///
  /// In zh, this message translates to:
  /// **'清除总结'**
  String get chapterCommentsClearSummary;

  /// No description provided for @comicCommentTitle.
  ///
  /// In zh, this message translates to:
  /// **'漫画评论'**
  String get comicCommentTitle;

  /// No description provided for @comicCommentSettingsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'评论设置'**
  String get comicCommentSettingsTooltip;

  /// No description provided for @comicCommentLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'评论加载失败'**
  String get comicCommentLoadFailed;

  /// No description provided for @comicCommentEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'这部漫画暂时没人发言'**
  String get comicCommentEmptySubtitle;

  /// No description provided for @comicCommentCollapseReplies.
  ///
  /// In zh, this message translates to:
  /// **'收起回复'**
  String get comicCommentCollapseReplies;

  /// No description provided for @comicCommentExpandReplies.
  ///
  /// In zh, this message translates to:
  /// **'展开 {count} 条回复'**
  String comicCommentExpandReplies(int count);

  /// No description provided for @comicCommentReplyLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'回复加载失败'**
  String get comicCommentReplyLoadFailed;

  /// No description provided for @comicCommentEmptyReplies.
  ///
  /// In zh, this message translates to:
  /// **'暂无可显示的回复'**
  String get comicCommentEmptyReplies;

  /// No description provided for @comicCommentRetryLoadMoreReplies.
  ///
  /// In zh, this message translates to:
  /// **'重试加载更多回复'**
  String get comicCommentRetryLoadMoreReplies;

  /// No description provided for @comicCommentLoadMoreReplies.
  ///
  /// In zh, this message translates to:
  /// **'加载更多回复 ({loaded}/{total})'**
  String comicCommentLoadMoreReplies(int loaded, int total);

  /// No description provided for @comicCommentCopied.
  ///
  /// In zh, this message translates to:
  /// **'评论已复制'**
  String get comicCommentCopied;

  /// No description provided for @comicCommentBlockNamedConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定屏蔽「{name}」吗？屏蔽后将不再显示其评论。\n可在黑名单中解除。'**
  String comicCommentBlockNamedConfirm(String name);

  /// No description provided for @comicCommentReplyTitle.
  ///
  /// In zh, this message translates to:
  /// **'回复 {userName}'**
  String comicCommentReplyTitle(String userName);

  /// No description provided for @comicCommentReplyHint.
  ///
  /// In zh, this message translates to:
  /// **'回复 {userName}...'**
  String comicCommentReplyHint(String userName);

  /// No description provided for @comicCommentPostHint.
  ///
  /// In zh, this message translates to:
  /// **'说点什么...'**
  String get comicCommentPostHint;

  /// No description provided for @comicCommentReplyPosted.
  ///
  /// In zh, this message translates to:
  /// **'回复已发布'**
  String get comicCommentReplyPosted;

  /// No description provided for @comicCommentReplyButton.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get comicCommentReplyButton;

  /// No description provided for @comicCommentExpandFullText.
  ///
  /// In zh, this message translates to:
  /// **'展开全文'**
  String get comicCommentExpandFullText;

  /// No description provided for @animeDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'动漫详情'**
  String get animeDetailTitle;

  /// No description provided for @animeDetailIntroTab.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get animeDetailIntroTab;

  /// No description provided for @animeDetailEpisodesTab.
  ///
  /// In zh, this message translates to:
  /// **'选集 ({count})'**
  String animeDetailEpisodesTab(int count);

  /// No description provided for @animeDetailIntroRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'简介刷新失败'**
  String get animeDetailIntroRefreshFailed;

  /// No description provided for @animeDetailEpisodeRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'选集刷新失败'**
  String get animeDetailEpisodeRefreshFailed;

  /// No description provided for @animeDetailDandanplayBindingCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除弹弹play绑定'**
  String get animeDetailDandanplayBindingCleared;

  /// No description provided for @animeDetailDandanplayBound.
  ///
  /// In zh, this message translates to:
  /// **'已绑定 {title}'**
  String animeDetailDandanplayBound(String title);

  /// No description provided for @animeDetailAlignmentCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除对齐'**
  String get animeDetailAlignmentCleared;

  /// No description provided for @animeDetailRealigned.
  ///
  /// In zh, this message translates to:
  /// **'已重新对齐弹幕'**
  String get animeDetailRealigned;

  /// No description provided for @animeDetailNoAvailableLine.
  ///
  /// In zh, this message translates to:
  /// **'当前选集暂无可用线路'**
  String get animeDetailNoAvailableLine;

  /// No description provided for @animeDetailPlaybackEpisodeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'播放记录对应选集暂不可用'**
  String get animeDetailPlaybackEpisodeUnavailable;

  /// No description provided for @animeDetailInfoLoadFailedForDownload.
  ///
  /// In zh, this message translates to:
  /// **'动漫信息加载失败，无法下载'**
  String get animeDetailInfoLoadFailedForDownload;

  /// No description provided for @animeDetailNoLineForDownload.
  ///
  /// In zh, this message translates to:
  /// **'当前选集暂无可用线路，无法下载'**
  String get animeDetailNoLineForDownload;

  /// No description provided for @animeDetailDownloadTasksAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {count} 个下载任务'**
  String animeDetailDownloadTasksAdded(int count);

  /// No description provided for @animeDetailCannotCollect.
  ///
  /// In zh, this message translates to:
  /// **'当前动漫暂时无法收藏'**
  String get animeDetailCannotCollect;

  /// No description provided for @animeDetailCollected.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get animeDetailCollected;

  /// No description provided for @animeDetailCollectCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消收藏'**
  String get animeDetailCollectCancelled;

  /// No description provided for @animeDetailCollectFailed.
  ///
  /// In zh, this message translates to:
  /// **'收藏状态修改失败'**
  String get animeDetailCollectFailed;

  /// No description provided for @animeDetailDownloadTaskCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个任务'**
  String animeDetailDownloadTaskCount(int count);

  /// No description provided for @animeDetailNoIntroInfo.
  ///
  /// In zh, this message translates to:
  /// **'暂无简介信息'**
  String get animeDetailNoIntroInfo;

  /// No description provided for @animeDetailInfoTitle.
  ///
  /// In zh, this message translates to:
  /// **'资料'**
  String get animeDetailInfoTitle;

  /// No description provided for @animeDetailIntroLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'简介加载失败，下拉重试'**
  String get animeDetailIntroLoadFailed;

  /// No description provided for @animeDetailIntroRefreshFailedCached.
  ///
  /// In zh, this message translates to:
  /// **'简介刷新失败，当前显示缓存内容'**
  String get animeDetailIntroRefreshFailedCached;

  /// No description provided for @animeDetailSelectedEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 集'**
  String animeDetailSelectedEpisodes(int count);

  /// No description provided for @animeDetailSelectAllUndownloaded.
  ///
  /// In zh, this message translates to:
  /// **'全选未下载'**
  String get animeDetailSelectAllUndownloaded;

  /// No description provided for @animeDetailDownloadSelected.
  ///
  /// In zh, this message translates to:
  /// **'下载选中'**
  String get animeDetailDownloadSelected;

  /// No description provided for @animeDetailEpisodeLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'选集加载失败，下拉重试'**
  String get animeDetailEpisodeLoadFailed;

  /// No description provided for @animeDetailNoEpisodes.
  ///
  /// In zh, this message translates to:
  /// **'暂无选集'**
  String get animeDetailNoEpisodes;

  /// No description provided for @animeDetailEpisodeRefreshFailedCached.
  ///
  /// In zh, this message translates to:
  /// **'选集刷新失败，当前显示上次结果'**
  String get animeDetailEpisodeRefreshFailedCached;

  /// No description provided for @animeDetailBindToViewComments.
  ///
  /// In zh, this message translates to:
  /// **'绑定弹弹play 后才可查看评论'**
  String get animeDetailBindToViewComments;

  /// No description provided for @animeDetailBindDanmaku.
  ///
  /// In zh, this message translates to:
  /// **'绑定弹幕'**
  String get animeDetailBindDanmaku;

  /// No description provided for @animeDetailRebind.
  ///
  /// In zh, this message translates to:
  /// **'重新绑定'**
  String get animeDetailRebind;

  /// No description provided for @animeDetailAlign.
  ///
  /// In zh, this message translates to:
  /// **'对齐'**
  String get animeDetailAlign;

  /// No description provided for @animeDetailDownloadButton.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get animeDetailDownloadButton;

  /// No description provided for @animeDetailEpisodeLoadFailedShort.
  ///
  /// In zh, this message translates to:
  /// **'选集加载失败'**
  String get animeDetailEpisodeLoadFailedShort;

  /// No description provided for @readerSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读设置'**
  String get readerSettingsTitle;

  /// No description provided for @readerScrollMode.
  ///
  /// In zh, this message translates to:
  /// **'滚动'**
  String get readerScrollMode;

  /// No description provided for @readerPageMode.
  ///
  /// In zh, this message translates to:
  /// **'翻页'**
  String get readerPageMode;

  /// No description provided for @readerLeftToRight.
  ///
  /// In zh, this message translates to:
  /// **'左到右'**
  String get readerLeftToRight;

  /// No description provided for @readerRightToLeft.
  ///
  /// In zh, this message translates to:
  /// **'右到左'**
  String get readerRightToLeft;

  /// No description provided for @readerTopToBottom.
  ///
  /// In zh, this message translates to:
  /// **'上到下'**
  String get readerTopToBottom;

  /// No description provided for @readerScrollSection.
  ///
  /// In zh, this message translates to:
  /// **'滚动'**
  String get readerScrollSection;

  /// No description provided for @readerImageGap.
  ///
  /// In zh, this message translates to:
  /// **'图片间距'**
  String get readerImageGap;

  /// No description provided for @readerContinuousReading.
  ///
  /// In zh, this message translates to:
  /// **'连续阅读'**
  String get readerContinuousReading;

  /// No description provided for @readerContinuousReadingDesc.
  ///
  /// In zh, this message translates to:
  /// **'到末页后直接拼接下一话，不重新加载'**
  String get readerContinuousReadingDesc;

  /// No description provided for @readerAutoScroll.
  ///
  /// In zh, this message translates to:
  /// **'自动滚动'**
  String get readerAutoScroll;

  /// No description provided for @readerAutoScrollDesc.
  ///
  /// In zh, this message translates to:
  /// **'开启后在导航栏显示自动滚动按钮'**
  String get readerAutoScrollDesc;

  /// No description provided for @readerAutoScrollDistance.
  ///
  /// In zh, this message translates to:
  /// **'滚动幅度'**
  String get readerAutoScrollDistance;

  /// No description provided for @readerAutoScrollPause.
  ///
  /// In zh, this message translates to:
  /// **'停顿时长'**
  String get readerAutoScrollPause;

  /// No description provided for @readerSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String readerSeconds(String seconds);

  /// No description provided for @readerAutoResume.
  ///
  /// In zh, this message translates to:
  /// **'自动恢复'**
  String get readerAutoResume;

  /// No description provided for @readerAutoResumeDesc.
  ///
  /// In zh, this message translates to:
  /// **'一段时间无动作后自动恢复滚动'**
  String get readerAutoResumeDesc;

  /// No description provided for @readerAutoResumeDelay.
  ///
  /// In zh, this message translates to:
  /// **'恢复延迟'**
  String get readerAutoResumeDelay;

  /// No description provided for @readerPageSection.
  ///
  /// In zh, this message translates to:
  /// **'翻页'**
  String get readerPageSection;

  /// No description provided for @readerVolumeKeyPageTurn.
  ///
  /// In zh, this message translates to:
  /// **'音量键翻页'**
  String get readerVolumeKeyPageTurn;

  /// No description provided for @readerVolumeKeyPageTurnDesc.
  ///
  /// In zh, this message translates to:
  /// **'音量+上一页，音量-下一页'**
  String get readerVolumeKeyPageTurnDesc;

  /// No description provided for @readerInstantPageTurn.
  ///
  /// In zh, this message translates to:
  /// **'无动画翻页'**
  String get readerInstantPageTurn;

  /// No description provided for @readerDisplaySection.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get readerDisplaySection;

  /// No description provided for @readerDimming.
  ///
  /// In zh, this message translates to:
  /// **'降低亮度'**
  String get readerDimming;

  /// No description provided for @readerImageLoadingSection.
  ///
  /// In zh, this message translates to:
  /// **'图片加载'**
  String get readerImageLoadingSection;

  /// No description provided for @readerTimeout.
  ///
  /// In zh, this message translates to:
  /// **'超时时间'**
  String get readerTimeout;

  /// No description provided for @readerTimeoutDesc.
  ///
  /// In zh, this message translates to:
  /// **'设置太小可能导致图片加载失败，太大可能导致长时间转圈'**
  String get readerTimeoutDesc;

  /// No description provided for @readerNoLoadStats.
  ///
  /// In zh, this message translates to:
  /// **'暂无加载记录（阅读图片后此处显示平均耗时供参考）'**
  String get readerNoLoadStats;

  /// No description provided for @readerRecentLoadStats.
  ///
  /// In zh, this message translates to:
  /// **'最近10分钟内加载了 {count} 张，平均 {seconds} s'**
  String readerRecentLoadStats(int count, String seconds);

  /// No description provided for @readerRetryCount.
  ///
  /// In zh, this message translates to:
  /// **'重试次数'**
  String get readerRetryCount;

  /// No description provided for @offButton.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get offButton;

  /// No description provided for @readerTimes.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String readerTimes(int count);

  /// No description provided for @browseHistoryClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空浏览记录'**
  String get browseHistoryClearTitle;

  /// No description provided for @browseHistoryClearContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空所有{mode}浏览记录吗？此操作不可撤销。'**
  String browseHistoryClearContent(String mode);

  /// No description provided for @browseHistoryCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清空{mode}浏览记录'**
  String browseHistoryCleared(String mode);

  /// No description provided for @browseHistoryClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空失败：{error}'**
  String browseHistoryClearFailed(String error);

  /// No description provided for @browseHistoryLoginExpiredContent.
  ///
  /// In zh, this message translates to:
  /// **'浏览记录需要登录后才能继续查看，是否现在重新登录？'**
  String get browseHistoryLoginExpiredContent;

  /// No description provided for @browseHistoryLoginToView.
  ///
  /// In zh, this message translates to:
  /// **'登录后可继续查看浏览记录'**
  String get browseHistoryLoginToView;

  /// No description provided for @browseHistoryLoginHintWithAnime.
  ///
  /// In zh, this message translates to:
  /// **'浏览过的漫画和动漫会同步显示在这里'**
  String get browseHistoryLoginHintWithAnime;

  /// No description provided for @browseHistoryLoginHintComicOnly.
  ///
  /// In zh, this message translates to:
  /// **'浏览过的漫画会同步显示在这里'**
  String get browseHistoryLoginHintComicOnly;

  /// No description provided for @browseHistoryEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有{mode}浏览记录'**
  String browseHistoryEmptyTitle(String mode);

  /// No description provided for @browseHistoryEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'去看几部{mode}后，这里会显示最近浏览内容'**
  String browseHistoryEmptySubtitle(String mode);

  /// No description provided for @browseHistoryTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条{mode}浏览记录'**
  String browseHistoryTotal(int count, String mode);

  /// No description provided for @hundredMillionUnit.
  ///
  /// In zh, this message translates to:
  /// **'{value}亿'**
  String hundredMillionUnit(String value);

  /// No description provided for @tenThousandUnit.
  ///
  /// In zh, this message translates to:
  /// **'{value}万'**
  String tenThousandUnit(String value);

  /// No description provided for @browseHistoryLatestChapter.
  ///
  /// In zh, this message translates to:
  /// **'最新 {chapter}'**
  String browseHistoryLatestChapter(String chapter);

  /// No description provided for @browseHistoryLastSeen.
  ///
  /// In zh, this message translates to:
  /// **'上次看到 {name}'**
  String browseHistoryLastSeen(String name);

  /// No description provided for @animePlayerLoginRequiredToPlay.
  ///
  /// In zh, this message translates to:
  /// **'登录后才能播放该视频'**
  String get animePlayerLoginRequiredToPlay;

  /// No description provided for @animePlayerEmptyVideoUrl.
  ///
  /// In zh, this message translates to:
  /// **'视频链接为空'**
  String get animePlayerEmptyVideoUrl;

  /// No description provided for @animePlayerRequestFailedStatus.
  ///
  /// In zh, this message translates to:
  /// **'请求失败（{statusCode}）'**
  String animePlayerRequestFailedStatus(int statusCode);

  /// No description provided for @animePlayerRequestFailedStatusText.
  ///
  /// In zh, this message translates to:
  /// **'请求失败（{statusCode}）'**
  String animePlayerRequestFailedStatusText(String statusCode);

  /// No description provided for @animePlayerMpvLogTitle.
  ///
  /// In zh, this message translates to:
  /// **'media_kit/mpv 日志:'**
  String get animePlayerMpvLogTitle;

  /// No description provided for @animePlayerQuickDiagnosisTitle.
  ///
  /// In zh, this message translates to:
  /// **'快速诊断:'**
  String get animePlayerQuickDiagnosisTitle;

  /// No description provided for @animePlayerDiagnosisManifestStatus.
  ///
  /// In zh, this message translates to:
  /// **'m3u8 状态: {statusCode}'**
  String animePlayerDiagnosisManifestStatus(int statusCode);

  /// No description provided for @animePlayerDiagnosisManifestHls.
  ///
  /// In zh, this message translates to:
  /// **'m3u8 内容: 已识别为 HLS 清单'**
  String get animePlayerDiagnosisManifestHls;

  /// No description provided for @animePlayerDiagnosisManifestNotHls.
  ///
  /// In zh, this message translates to:
  /// **'m3u8 内容: 返回 200，但内容不像标准 HLS 清单'**
  String get animePlayerDiagnosisManifestNotHls;

  /// No description provided for @animePlayerDiagnosisManifestError.
  ///
  /// In zh, this message translates to:
  /// **'m3u8 错误: {error}'**
  String animePlayerDiagnosisManifestError(String error);

  /// No description provided for @animePlayerDiagnosisFirstSegment.
  ///
  /// In zh, this message translates to:
  /// **'首个分片: {url}'**
  String animePlayerDiagnosisFirstSegment(String url);

  /// No description provided for @animePlayerDiagnosisSegmentStatus.
  ///
  /// In zh, this message translates to:
  /// **'首个分片状态: {statusCode}'**
  String animePlayerDiagnosisSegmentStatus(int statusCode);

  /// No description provided for @animePlayerDiagnosisSegmentBytes.
  ///
  /// In zh, this message translates to:
  /// **'首个分片字节数: {bytes}'**
  String animePlayerDiagnosisSegmentBytes(int bytes);

  /// No description provided for @animePlayerDiagnosisSegmentError.
  ///
  /// In zh, this message translates to:
  /// **'首个分片错误: {error}'**
  String animePlayerDiagnosisSegmentError(String error);

  /// No description provided for @animePlayerDiagnosisConclusionDecodeIssue.
  ///
  /// In zh, this message translates to:
  /// **'结论: m3u8 与首个分片都可访问，更像是播放器解析或解码兼容问题'**
  String get animePlayerDiagnosisConclusionDecodeIssue;

  /// No description provided for @animePlayerSourceForbidden.
  ///
  /// In zh, this message translates to:
  /// **'视频源拒绝访问（403）'**
  String get animePlayerSourceForbidden;

  /// No description provided for @animePlayerSourceNotFound.
  ///
  /// In zh, this message translates to:
  /// **'视频地址已失效（404）'**
  String get animePlayerSourceNotFound;

  /// No description provided for @animePlayerCertificateFailed.
  ///
  /// In zh, this message translates to:
  /// **'视频证书校验失败'**
  String get animePlayerCertificateFailed;

  /// No description provided for @animePlayerConnectionTimeout.
  ///
  /// In zh, this message translates to:
  /// **'视频连接超时'**
  String get animePlayerConnectionTimeout;

  /// No description provided for @animePlayerCannotParseStream.
  ///
  /// In zh, this message translates to:
  /// **'视频源可访问，但播放器无法解析该视频流'**
  String get animePlayerCannotParseStream;

  /// No description provided for @animePlayerEnableProxyToRetry.
  ///
  /// In zh, this message translates to:
  /// **'视频加载失败，请开启代理后重试'**
  String get animePlayerEnableProxyToRetry;

  /// No description provided for @animePlayerInvalidVideoUri.
  ///
  /// In zh, this message translates to:
  /// **'视频地址不是合法 URI'**
  String get animePlayerInvalidVideoUri;

  /// No description provided for @animePlayerDiagnosisRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'视频诊断请求失败'**
  String get animePlayerDiagnosisRequestFailed;

  /// No description provided for @animePlayerSegmentDiagnosisRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'视频分片诊断请求失败'**
  String get animePlayerSegmentDiagnosisRequestFailed;

  /// No description provided for @animePlayerSegmentUrlNotResolved.
  ///
  /// In zh, this message translates to:
  /// **'未解析出分片地址'**
  String get animePlayerSegmentUrlNotResolved;

  /// No description provided for @animePlayerLoadingCannotSwitch.
  ///
  /// In zh, this message translates to:
  /// **'视频加载中，请稍后再切换'**
  String get animePlayerLoadingCannotSwitch;

  /// No description provided for @animePlayerNoVideoUrlToCopy.
  ///
  /// In zh, this message translates to:
  /// **'暂无可复制的视频链接'**
  String get animePlayerNoVideoUrlToCopy;

  /// No description provided for @animePlayerVideoUrlCopied.
  ///
  /// In zh, this message translates to:
  /// **'视频链接已复制到剪贴板'**
  String get animePlayerVideoUrlCopied;

  /// No description provided for @animePlayerNoVideoUrlToOpen.
  ///
  /// In zh, this message translates to:
  /// **'暂无可打开的视频链接'**
  String get animePlayerNoVideoUrlToOpen;

  /// No description provided for @animePlayerOpenVideoUrlFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开视频链接'**
  String get animePlayerOpenVideoUrlFailed;

  /// No description provided for @animePlayerSeekedTo.
  ///
  /// In zh, this message translates to:
  /// **'已跳转到 {position}'**
  String animePlayerSeekedTo(String position);

  /// No description provided for @animePlayerSeekLastFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法跳转到上次进度'**
  String get animePlayerSeekLastFailed;

  /// No description provided for @animePlayerSearchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败: {error}'**
  String animePlayerSearchFailed(String error);

  /// No description provided for @animePlayerRefreshTooFrequent.
  ///
  /// In zh, this message translates to:
  /// **'不要频繁刷新！'**
  String get animePlayerRefreshTooFrequent;

  /// No description provided for @animePlayerLoadDanmakuFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载弹幕失败: {error}'**
  String animePlayerLoadDanmakuFailed(String error);

  /// No description provided for @animePlayerBuffering.
  ///
  /// In zh, this message translates to:
  /// **'正在缓冲...'**
  String get animePlayerBuffering;

  /// No description provided for @animePlayerProxySuggestion.
  ///
  /// In zh, this message translates to:
  /// **'如果网络卡顿，建议开启代理访问'**
  String get animePlayerProxySuggestion;

  /// No description provided for @animePlayerPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get animePlayerPlay;

  /// No description provided for @animePlayerFastForward.
  ///
  /// In zh, this message translates to:
  /// **'快进 {seconds}秒'**
  String animePlayerFastForward(int seconds);

  /// No description provided for @animePlayerHideDanmaku.
  ///
  /// In zh, this message translates to:
  /// **'隐藏弹幕'**
  String get animePlayerHideDanmaku;

  /// No description provided for @animePlayerChapterSelector.
  ///
  /// In zh, this message translates to:
  /// **'选集'**
  String get animePlayerChapterSelector;

  /// No description provided for @animePlayerChapterSelectorWithCount.
  ///
  /// In zh, this message translates to:
  /// **'选集 ({count})'**
  String animePlayerChapterSelectorWithCount(int count);

  /// No description provided for @animePlayerSetSkipSeconds.
  ///
  /// In zh, this message translates to:
  /// **'设置跳转秒数'**
  String get animePlayerSetSkipSeconds;

  /// No description provided for @animePlayerExitFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'退出全屏'**
  String get animePlayerExitFullscreen;

  /// No description provided for @animePlayerFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'全屏'**
  String get animePlayerFullscreen;

  /// No description provided for @backButton.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get backButton;

  /// No description provided for @cacheSelectedCards.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个卡片'**
  String cacheSelectedCards(int count);

  /// No description provided for @cacheDeleteSelectedCardsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除选中卡片'**
  String get cacheDeleteSelectedCardsTooltip;

  /// No description provided for @cacheExitMultiSelectTooltip.
  ///
  /// In zh, this message translates to:
  /// **'退出多选'**
  String get cacheExitMultiSelectTooltip;

  /// No description provided for @cacheMultiSelectTooltip.
  ///
  /// In zh, this message translates to:
  /// **'多选卡片'**
  String get cacheMultiSelectTooltip;

  /// No description provided for @cacheSummary.
  ///
  /// In zh, this message translates to:
  /// **'共 {localTotal} 项本地数据 · {size}'**
  String cacheSummary(int localTotal, String size);

  /// No description provided for @cacheManagementSummaryDesc.
  ///
  /// In zh, this message translates to:
  /// **'按缓存、账号、设置、历史等分类显示；AI 配置 key 已隐藏；图片与播放组件可单独清理。'**
  String get cacheManagementSummaryDesc;

  /// No description provided for @cacheImageCacheSection.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存'**
  String get cacheImageCacheSection;

  /// No description provided for @cacheDataCacheSection.
  ///
  /// In zh, this message translates to:
  /// **'数据缓存'**
  String get cacheDataCacheSection;

  /// No description provided for @cacheNoLocalKeyValueData.
  ///
  /// In zh, this message translates to:
  /// **'没有可显示的本地键值数据'**
  String get cacheNoLocalKeyValueData;

  /// No description provided for @cacheEntryCountSize.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项 · {size}'**
  String cacheEntryCountSize(int count, String size);

  /// No description provided for @cacheHideSensitiveTooltip.
  ///
  /// In zh, this message translates to:
  /// **'隐藏敏感内容'**
  String get cacheHideSensitiveTooltip;

  /// No description provided for @cacheShowSensitiveTooltip.
  ///
  /// In zh, this message translates to:
  /// **'显示敏感内容'**
  String get cacheShowSensitiveTooltip;

  /// No description provided for @cacheEntryDataTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存项数据'**
  String get cacheEntryDataTitle;

  /// No description provided for @cacheDataCopiedToast.
  ///
  /// In zh, this message translates to:
  /// **'缓存数据已复制'**
  String get cacheDataCopiedToast;

  /// No description provided for @cacheFileCountSize.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件 · {size}'**
  String cacheFileCountSize(int count, String size);

  /// No description provided for @cacheDescriptionTitle.
  ///
  /// In zh, this message translates to:
  /// **'说明'**
  String get cacheDescriptionTitle;

  /// No description provided for @cacheKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存标识'**
  String get cacheKeyTitle;

  /// No description provided for @cacheDirectoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'缓存目录'**
  String get cacheDirectoryTitle;

  /// No description provided for @cacheCategoryPersistentCache.
  ///
  /// In zh, this message translates to:
  /// **'业务缓存'**
  String get cacheCategoryPersistentCache;

  /// No description provided for @cacheCategoryAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号数据'**
  String get cacheCategoryAccount;

  /// No description provided for @cacheCategoryAppSettings.
  ///
  /// In zh, this message translates to:
  /// **'应用设置'**
  String get cacheCategoryAppSettings;

  /// No description provided for @cacheCategoryMangaHistory.
  ///
  /// In zh, this message translates to:
  /// **'漫画阅读历史'**
  String get cacheCategoryMangaHistory;

  /// No description provided for @cacheCategoryAnimeHistory.
  ///
  /// In zh, this message translates to:
  /// **'动漫播放历史'**
  String get cacheCategoryAnimeHistory;

  /// No description provided for @cacheCategoryBindings.
  ///
  /// In zh, this message translates to:
  /// **'弹幕绑定'**
  String get cacheCategoryBindings;

  /// No description provided for @cacheCategoryAiSummaryCache.
  ///
  /// In zh, this message translates to:
  /// **'AI 总结缓存'**
  String get cacheCategoryAiSummaryCache;

  /// No description provided for @cacheCategoryOther.
  ///
  /// In zh, this message translates to:
  /// **'其他数据'**
  String get cacheCategoryOther;

  /// No description provided for @themeColorBlueGrey.
  ///
  /// In zh, this message translates to:
  /// **'蓝灰'**
  String get themeColorBlueGrey;

  /// No description provided for @themeColorTeal.
  ///
  /// In zh, this message translates to:
  /// **'青绿'**
  String get themeColorTeal;

  /// No description provided for @themeColorIndigo.
  ///
  /// In zh, this message translates to:
  /// **'靛蓝'**
  String get themeColorIndigo;

  /// No description provided for @themeColorGreen.
  ///
  /// In zh, this message translates to:
  /// **'森绿'**
  String get themeColorGreen;

  /// No description provided for @themeColorOrange.
  ///
  /// In zh, this message translates to:
  /// **'橙金'**
  String get themeColorOrange;

  /// No description provided for @themeColorPink.
  ///
  /// In zh, this message translates to:
  /// **'粉色'**
  String get themeColorPink;

  /// No description provided for @themeColorBrightBlue.
  ///
  /// In zh, this message translates to:
  /// **'亮蓝'**
  String get themeColorBrightBlue;

  /// No description provided for @themeColorViolet.
  ///
  /// In zh, this message translates to:
  /// **'紫罗兰'**
  String get themeColorViolet;

  /// No description provided for @themeColorOrchid.
  ///
  /// In zh, this message translates to:
  /// **'兰紫'**
  String get themeColorOrchid;

  /// No description provided for @themeColorCyan.
  ///
  /// In zh, this message translates to:
  /// **'湖青'**
  String get themeColorCyan;

  /// No description provided for @themeColorEmerald.
  ///
  /// In zh, this message translates to:
  /// **'翡翠'**
  String get themeColorEmerald;

  /// No description provided for @themeColorLime.
  ///
  /// In zh, this message translates to:
  /// **'青柠'**
  String get themeColorLime;

  /// No description provided for @themeColorAmber.
  ///
  /// In zh, this message translates to:
  /// **'琥珀'**
  String get themeColorAmber;

  /// No description provided for @themeColorCoral.
  ///
  /// In zh, this message translates to:
  /// **'珊瑚'**
  String get themeColorCoral;

  /// No description provided for @themeColorCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定'**
  String get themeColorCustom;

  /// No description provided for @themeVariantTonalSpot.
  ///
  /// In zh, this message translates to:
  /// **'柔和'**
  String get themeVariantTonalSpot;

  /// No description provided for @themeVariantTonalSpotDesc.
  ///
  /// In zh, this message translates to:
  /// **'Material 默认风格，低饱和、耐看。'**
  String get themeVariantTonalSpotDesc;

  /// No description provided for @themeVariantVibrant.
  ///
  /// In zh, this message translates to:
  /// **'鲜明'**
  String get themeVariantVibrant;

  /// No description provided for @themeVariantVibrantDesc.
  ///
  /// In zh, this message translates to:
  /// **'提高主色饱和度，整体更醒目。'**
  String get themeVariantVibrantDesc;

  /// No description provided for @themeVariantExpressive.
  ///
  /// In zh, this message translates to:
  /// **'表现'**
  String get themeVariantExpressive;

  /// No description provided for @themeVariantExpressiveDesc.
  ///
  /// In zh, this message translates to:
  /// **'会偏移主色相，风格更有个性。'**
  String get themeVariantExpressiveDesc;

  /// No description provided for @themeVariantFidelity.
  ///
  /// In zh, this message translates to:
  /// **'准确'**
  String get themeVariantFidelity;

  /// No description provided for @themeVariantFidelityDesc.
  ///
  /// In zh, this message translates to:
  /// **'尽量贴近所选主色的原始观感。'**
  String get themeVariantFidelityDesc;

  /// No description provided for @themeVariantContent.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get themeVariantContent;

  /// No description provided for @themeVariantContentDesc.
  ///
  /// In zh, this message translates to:
  /// **'容器颜色更贴近主色，强调层次。'**
  String get themeVariantContentDesc;

  /// No description provided for @themeVariantNeutral.
  ///
  /// In zh, this message translates to:
  /// **'中性'**
  String get themeVariantNeutral;

  /// No description provided for @themeVariantNeutralDesc.
  ///
  /// In zh, this message translates to:
  /// **'接近灰阶，适合更克制的界面。'**
  String get themeVariantNeutralDesc;

  /// No description provided for @themeVariantMonochrome.
  ///
  /// In zh, this message translates to:
  /// **'黑白'**
  String get themeVariantMonochrome;

  /// No description provided for @themeVariantMonochromeDesc.
  ///
  /// In zh, this message translates to:
  /// **'完全灰阶，只保留明暗关系。'**
  String get themeVariantMonochromeDesc;

  /// No description provided for @themeVariantRainbow.
  ///
  /// In zh, this message translates to:
  /// **'彩虹'**
  String get themeVariantRainbow;

  /// No description provided for @themeVariantRainbowDesc.
  ///
  /// In zh, this message translates to:
  /// **'跳脱主色限制，整体更活泼。'**
  String get themeVariantRainbowDesc;

  /// No description provided for @appLogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无错误日志'**
  String get appLogEmpty;

  /// No description provided for @appLogCopied.
  ///
  /// In zh, this message translates to:
  /// **'日志已复制到剪贴板'**
  String get appLogCopied;

  /// No description provided for @appLogCopyFailed.
  ///
  /// In zh, this message translates to:
  /// **'复制失败：{error}'**
  String appLogCopyFailed(String error);

  /// No description provided for @appLogClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空错误日志'**
  String get appLogClearTitle;

  /// No description provided for @appLogClearContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除本地保存的错误日志吗？'**
  String get appLogClearContent;

  /// No description provided for @appLogCleared.
  ///
  /// In zh, this message translates to:
  /// **'错误日志已清空'**
  String get appLogCleared;

  /// No description provided for @appLogClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空失败：{error}'**
  String appLogClearFailed(String error);

  /// No description provided for @settingsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTooltip;

  /// No description provided for @appLogSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志设置'**
  String get appLogSettingsTitle;

  /// No description provided for @appLogRecordLogs.
  ///
  /// In zh, this message translates to:
  /// **'记录日志'**
  String get appLogRecordLogs;

  /// No description provided for @appLogLevel.
  ///
  /// In zh, this message translates to:
  /// **'日志级别'**
  String get appLogLevel;

  /// No description provided for @appLogLevelDebug.
  ///
  /// In zh, this message translates to:
  /// **'调试'**
  String get appLogLevelDebug;

  /// No description provided for @appLogLevelInfo.
  ///
  /// In zh, this message translates to:
  /// **'信息'**
  String get appLogLevelInfo;

  /// No description provided for @appLogLevelWarning.
  ///
  /// In zh, this message translates to:
  /// **'警告'**
  String get appLogLevelWarning;

  /// No description provided for @appLogLevelError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get appLogLevelError;

  /// No description provided for @appLogSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索日志（消息、来源、堆栈、上下文）'**
  String get appLogSearchHint;

  /// No description provided for @appLogClearLogsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'清空日志'**
  String get appLogClearLogsTooltip;

  /// No description provided for @appLogAllLevels.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get appLogAllLevels;

  /// No description provided for @appLogCopyThisLogTooltip.
  ///
  /// In zh, this message translates to:
  /// **'复制此日志'**
  String get appLogCopyThisLogTooltip;

  /// No description provided for @appLogContextTitle.
  ///
  /// In zh, this message translates to:
  /// **'上下文'**
  String get appLogContextTitle;

  /// No description provided for @appLogStackTitle.
  ///
  /// In zh, this message translates to:
  /// **'堆栈'**
  String get appLogStackTitle;

  /// No description provided for @relativeTimeJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get relativeTimeJustNow;

  /// No description provided for @relativeTimeMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{minutes}分钟前'**
  String relativeTimeMinutesAgo(int minutes);

  /// No description provided for @relativeTimeHoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{hours}小时前'**
  String relativeTimeHoursAgo(int hours);

  /// No description provided for @relativeTimeDaysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{days}天前'**
  String relativeTimeDaysAgo(int days);

  /// No description provided for @relativeTimeMonthsAgo.
  ///
  /// In zh, this message translates to:
  /// **'{months}个月前'**
  String relativeTimeMonthsAgo(int months);

  /// No description provided for @relativeTimeYearsAgo.
  ///
  /// In zh, this message translates to:
  /// **'{years}年前'**
  String relativeTimeYearsAgo(int years);

  /// No description provided for @comicDetailCommentsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前漫画暂时无法查看评论'**
  String get comicDetailCommentsUnavailable;

  /// No description provided for @comicDetailAuthorUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前作者暂时无法查看作品'**
  String get comicDetailAuthorUnavailable;

  /// No description provided for @comicDetailThemeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前主题暂时无法查看作品'**
  String get comicDetailThemeUnavailable;

  /// No description provided for @comicDetailSelectUndownloadedChapters.
  ///
  /// In zh, this message translates to:
  /// **'请选择未下载的章节'**
  String get comicDetailSelectUndownloadedChapters;

  /// No description provided for @comicDetailAddedToDownloadQueue.
  ///
  /// In zh, this message translates to:
  /// **'已加入下载队列：{count} 章（顺序下载）'**
  String comicDetailAddedToDownloadQueue(int count);

  /// No description provided for @comicDetailSelectedAlreadyDownloadedOrQueued.
  ///
  /// In zh, this message translates to:
  /// **'所选章节已下载或已在队列中'**
  String get comicDetailSelectedAlreadyDownloadedOrQueued;

  /// No description provided for @comicDetailSelectedChapters.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 章'**
  String comicDetailSelectedChapters(int count);

  /// No description provided for @comicDetailSequentialDownloading.
  ///
  /// In zh, this message translates to:
  /// **'顺序下载中 {count} 章'**
  String comicDetailSequentialDownloading(int count);

  /// No description provided for @downloadedStatus.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get downloadedStatus;

  /// No description provided for @comicDetailDownloadProgress.
  ///
  /// In zh, this message translates to:
  /// **'下载 {completed}/{total}'**
  String comicDetailDownloadProgress(int completed, int total);

  /// No description provided for @comicDetailQueued.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get comicDetailQueued;

  /// No description provided for @processingStatus.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get processingStatus;

  /// No description provided for @comicDetailReadWithStatus.
  ///
  /// In zh, this message translates to:
  /// **'已读 · {status}'**
  String comicDetailReadWithStatus(String status);

  /// No description provided for @collectButton.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get collectButton;

  /// No description provided for @downloadQueueTab.
  ///
  /// In zh, this message translates to:
  /// **'队列'**
  String get downloadQueueTab;

  /// No description provided for @downloadQueueEmpty.
  ///
  /// In zh, this message translates to:
  /// **'下载队列为空'**
  String get downloadQueueEmpty;

  /// No description provided for @downloadQueueEmptyComicHint.
  ///
  /// In zh, this message translates to:
  /// **'去漫画详情页添加下载任务'**
  String get downloadQueueEmptyComicHint;

  /// No description provided for @downloadQueueEmptyMixedHint.
  ///
  /// In zh, this message translates to:
  /// **'去漫画或动漫详情页添加下载任务'**
  String get downloadQueueEmptyMixedHint;

  /// No description provided for @downloadProgressApproxBytes.
  ///
  /// In zh, this message translates to:
  /// **'{percent}% · 约 {size}'**
  String downloadProgressApproxBytes(String percent, String size);

  /// No description provided for @downloadingStatus.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get downloadingStatus;

  /// No description provided for @waitingStatus.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get waitingStatus;

  /// No description provided for @pausedStatus.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get pausedStatus;

  /// No description provided for @downloadFailedStatus.
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get downloadFailedStatus;

  /// No description provided for @animeDownloadConnectionTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接超时'**
  String get animeDownloadConnectionTimeout;

  /// No description provided for @animeDownloadProxyRetrySuggestion.
  ///
  /// In zh, this message translates to:
  /// **'建议开启代理后重试'**
  String get animeDownloadProxyRetrySuggestion;

  /// No description provided for @animeDownloadUnknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get animeDownloadUnknownError;

  /// No description provided for @animeDownloadFailedMessage.
  ///
  /// In zh, this message translates to:
  /// **'{chapter} 下载失败：{error}'**
  String animeDownloadFailedMessage(String chapter, String error);

  /// No description provided for @animeDownloadEmptyVideoUrl.
  ///
  /// In zh, this message translates to:
  /// **'视频链接为空'**
  String get animeDownloadEmptyVideoUrl;

  /// No description provided for @pauseButton.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pauseButton;

  /// No description provided for @resumeButton.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get resumeButton;

  /// No description provided for @downloadProgressCount.
  ///
  /// In zh, this message translates to:
  /// **'{percent}% ({completed}/{total})'**
  String downloadProgressCount(String percent, int completed, int total);

  /// No description provided for @commentSettingsAiSummarySection.
  ///
  /// In zh, this message translates to:
  /// **'AI 总结'**
  String get commentSettingsAiSummarySection;

  /// No description provided for @commentSettingsEnableAiSummary.
  ///
  /// In zh, this message translates to:
  /// **'启用 AI 总结'**
  String get commentSettingsEnableAiSummary;

  /// No description provided for @commentSettingsAiSummaryEnabledDesc.
  ///
  /// In zh, this message translates to:
  /// **'评论顶部显示 AI 总结按钮'**
  String get commentSettingsAiSummaryEnabledDesc;

  /// No description provided for @commentSettingsAiSummaryDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get commentSettingsAiSummaryDisabled;

  /// No description provided for @commentSettingsConfigureAiFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先在「我的 → AI配置」中配置 API 密钥'**
  String get commentSettingsConfigureAiFirst;

  /// No description provided for @commentSettingsCollapseAiComment.
  ///
  /// In zh, this message translates to:
  /// **'折叠 AI 评论'**
  String get commentSettingsCollapseAiComment;

  /// No description provided for @commentSettingsCollapseAiCommentDesc.
  ///
  /// In zh, this message translates to:
  /// **'开启后 AI 评论默认折叠，生成中也保持折叠'**
  String get commentSettingsCollapseAiCommentDesc;

  /// No description provided for @commentSettingsAutoAiSummary.
  ///
  /// In zh, this message translates to:
  /// **'自动 AI 总结'**
  String get commentSettingsAutoAiSummary;

  /// No description provided for @commentSettingsAutoAiSummaryDesc.
  ///
  /// In zh, this message translates to:
  /// **'评论数 ≥ {count} 条时自动生成'**
  String commentSettingsAutoAiSummaryDesc(int count);

  /// No description provided for @commentSettingsMinCommentCount.
  ///
  /// In zh, this message translates to:
  /// **'最少评论数'**
  String get commentSettingsMinCommentCount;

  /// No description provided for @commentSettingsTriggerTiming.
  ///
  /// In zh, this message translates to:
  /// **'调用时机'**
  String get commentSettingsTriggerTiming;

  /// No description provided for @commentSettingsTimingOnOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开评论区时'**
  String get commentSettingsTimingOnOpen;

  /// No description provided for @commentSettingsTimingAfterPreload.
  ///
  /// In zh, this message translates to:
  /// **'预加载完成后'**
  String get commentSettingsTimingAfterPreload;

  /// No description provided for @commentSettingsPreloadRequiredForTiming.
  ///
  /// In zh, this message translates to:
  /// **'选择“预加载完成后”需要先开启预加载评论。'**
  String get commentSettingsPreloadRequiredForTiming;

  /// No description provided for @commentSettingsSpoilerAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'剧透分析'**
  String get commentSettingsSpoilerAnalysis;

  /// No description provided for @commentSettingsSpoilerAnalysisDesc.
  ///
  /// In zh, this message translates to:
  /// **'开启后会在当前提示词后自动追加剧透分析要求'**
  String get commentSettingsSpoilerAnalysisDesc;

  /// No description provided for @commentSettingsSpoilerWarn.
  ///
  /// In zh, this message translates to:
  /// **'打开剧透评论弹出提醒'**
  String get commentSettingsSpoilerWarn;

  /// No description provided for @commentSettingsPromptPresets.
  ///
  /// In zh, this message translates to:
  /// **'提示词预设'**
  String get commentSettingsPromptPresets;

  /// No description provided for @commentSettingsBlacklistSection.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get commentSettingsBlacklistSection;

  /// No description provided for @commentSettingsBlacklistDesc.
  ///
  /// In zh, this message translates to:
  /// **'长按评论可选择「屏蔽用户」，被屏蔽的评论将不再显示。'**
  String get commentSettingsBlacklistDesc;

  /// No description provided for @commentSettingsClearBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'清空黑名单'**
  String get commentSettingsClearBlacklist;

  /// No description provided for @commentSettingsAnonymousUser.
  ///
  /// In zh, this message translates to:
  /// **'匿名用户'**
  String get commentSettingsAnonymousUser;

  /// No description provided for @commentSettingsRemoveFromBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'移出黑名单'**
  String get commentSettingsRemoveFromBlacklist;

  /// No description provided for @profileFallbackQuestionWife.
  ///
  /// In zh, this message translates to:
  /// **'我的老婆叫什麼？'**
  String get profileFallbackQuestionWife;

  /// No description provided for @profileFallbackQuestionFriend.
  ///
  /// In zh, this message translates to:
  /// **'我的基友叫啥？'**
  String get profileFallbackQuestionFriend;

  /// No description provided for @profileFallbackQuestionBestFriendCount.
  ///
  /// In zh, this message translates to:
  /// **'我的好麻吉有幾個？'**
  String get profileFallbackQuestionBestFriendCount;

  /// No description provided for @profileFallbackQuestionParentName.
  ///
  /// In zh, this message translates to:
  /// **'我的父親(母親)叫什麽？'**
  String get profileFallbackQuestionParentName;

  /// No description provided for @animeDetailSubtitleChip.
  ///
  /// In zh, this message translates to:
  /// **'字幕'**
  String get animeDetailSubtitleChip;

  /// No description provided for @animeDetailLatestChapter.
  ///
  /// In zh, this message translates to:
  /// **'最新：{chapter}'**
  String animeDetailLatestChapter(String chapter);

  /// No description provided for @animeDetailOnAirChip.
  ///
  /// In zh, this message translates to:
  /// **'连载中'**
  String get animeDetailOnAirChip;

  /// No description provided for @animeDetailRestrictedChip.
  ///
  /// In zh, this message translates to:
  /// **'受限'**
  String get animeDetailRestrictedChip;

  /// No description provided for @animeDetailDirector.
  ///
  /// In zh, this message translates to:
  /// **'导演：{name}'**
  String animeDetailDirector(String name);

  /// No description provided for @playerSettingsPlaybackTitle.
  ///
  /// In zh, this message translates to:
  /// **'播放设置'**
  String get playerSettingsPlaybackTitle;

  /// No description provided for @playerSettingsSkipSeconds.
  ///
  /// In zh, this message translates to:
  /// **'快进秒数'**
  String get playerSettingsSkipSeconds;

  /// No description provided for @playerSettingsSkipSecondsDesc.
  ///
  /// In zh, this message translates to:
  /// **'动漫片头一般约90秒'**
  String get playerSettingsSkipSecondsDesc;

  /// No description provided for @playerSettingsSecondsLabel.
  ///
  /// In zh, this message translates to:
  /// **'秒数'**
  String get playerSettingsSecondsLabel;

  /// No description provided for @readerSecondsSuffix.
  ///
  /// In zh, this message translates to:
  /// **'秒'**
  String get readerSecondsSuffix;

  /// No description provided for @playerSettingsRecordProgress.
  ///
  /// In zh, this message translates to:
  /// **'记录播放进度'**
  String get playerSettingsRecordProgress;

  /// No description provided for @playerSettingsRecordProgressDesc.
  ///
  /// In zh, this message translates to:
  /// **'再次打开同一集时自动跳转到上次观看位置'**
  String get playerSettingsRecordProgressDesc;

  /// No description provided for @playerSettingsDanmakuTitle.
  ///
  /// In zh, this message translates to:
  /// **'弹幕设置'**
  String get playerSettingsDanmakuTitle;

  /// No description provided for @playerSettingsShowDanmaku.
  ///
  /// In zh, this message translates to:
  /// **'显示弹幕'**
  String get playerSettingsShowDanmaku;

  /// No description provided for @playerSettingsFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字体大小'**
  String get playerSettingsFontSize;

  /// No description provided for @playerSettingsDisplayArea.
  ///
  /// In zh, this message translates to:
  /// **'显示区域'**
  String get playerSettingsDisplayArea;

  /// No description provided for @playerSettingsOpacity.
  ///
  /// In zh, this message translates to:
  /// **'透明度'**
  String get playerSettingsOpacity;

  /// No description provided for @playerSettingsDanmakuType.
  ///
  /// In zh, this message translates to:
  /// **'弹幕类型'**
  String get playerSettingsDanmakuType;

  /// No description provided for @playerSettingsScrollDanmaku.
  ///
  /// In zh, this message translates to:
  /// **'滚动弹幕'**
  String get playerSettingsScrollDanmaku;

  /// No description provided for @playerSettingsTopDanmaku.
  ///
  /// In zh, this message translates to:
  /// **'顶部弹幕'**
  String get playerSettingsTopDanmaku;

  /// No description provided for @playerSettingsBottomDanmaku.
  ///
  /// In zh, this message translates to:
  /// **'底部弹幕'**
  String get playerSettingsBottomDanmaku;

  /// No description provided for @playerSettingsBlocklist.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽词'**
  String get playerSettingsBlocklist;

  /// No description provided for @playerSettingsBlocklistDesc.
  ///
  /// In zh, this message translates to:
  /// **'包含屏蔽词的弹幕将被自动过滤'**
  String get playerSettingsBlocklistDesc;

  /// No description provided for @playerSettingsBlocklistHint.
  ///
  /// In zh, this message translates to:
  /// **'输入屏蔽词'**
  String get playerSettingsBlocklistHint;

  /// No description provided for @playerSettingsDanmakuFont.
  ///
  /// In zh, this message translates to:
  /// **'弹幕字体'**
  String get playerSettingsDanmakuFont;

  /// No description provided for @playerSettingsDanmakuFontSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get playerSettingsDanmakuFontSystem;

  /// No description provided for @playerSettingsChineseConvertTooltip.
  ///
  /// In zh, this message translates to:
  /// **'简繁转换'**
  String get playerSettingsChineseConvertTooltip;

  /// No description provided for @readerImageLinksRefreshed.
  ///
  /// In zh, this message translates to:
  /// **'图片链接已刷新'**
  String get readerImageLinksRefreshed;

  /// No description provided for @refreshFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败：{error}'**
  String refreshFailedWithError(String error);

  /// No description provided for @readerLocalChapterNoRefresh.
  ///
  /// In zh, this message translates to:
  /// **'本地章节无需刷新'**
  String get readerLocalChapterNoRefresh;

  /// No description provided for @readerAutoSummaryFailed.
  ///
  /// In zh, this message translates to:
  /// **'后台自动总结失败：{error}'**
  String readerAutoSummaryFailed(String error);

  /// No description provided for @readerNoPreviousChapter.
  ///
  /// In zh, this message translates to:
  /// **'当前已无上一话'**
  String get readerNoPreviousChapter;

  /// No description provided for @readerPreviousChapter.
  ///
  /// In zh, this message translates to:
  /// **'上一章'**
  String get readerPreviousChapter;

  /// No description provided for @readerPauseAutoScroll.
  ///
  /// In zh, this message translates to:
  /// **'暂停自动滚动'**
  String get readerPauseAutoScroll;

  /// No description provided for @readerAutoScrollWillResume.
  ///
  /// In zh, this message translates to:
  /// **'自动滚动即将恢复'**
  String get readerAutoScrollWillResume;

  /// No description provided for @readerEnableAutoScroll.
  ///
  /// In zh, this message translates to:
  /// **'开启自动滚动'**
  String get readerEnableAutoScroll;

  /// No description provided for @readerLoadingNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'正在加载下一话…'**
  String get readerLoadingNextChapter;

  /// No description provided for @readerContinueScrollLoadNext.
  ///
  /// In zh, this message translates to:
  /// **'继续滚动加载下一话'**
  String get readerContinueScrollLoadNext;

  /// No description provided for @readerAlreadyFirstChapter.
  ///
  /// In zh, this message translates to:
  /// **'已经是第一章'**
  String get readerAlreadyFirstChapter;

  /// No description provided for @readerContinuePageNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'继续翻页进入下一话'**
  String get readerContinuePageNextChapter;

  /// No description provided for @readerAlreadyLastChapter.
  ///
  /// In zh, this message translates to:
  /// **'已经是最后一话'**
  String get readerAlreadyLastChapter;

  /// No description provided for @readerContinueScrollOrTapNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'继续下滑或点击按钮进入下一话'**
  String get readerContinueScrollOrTapNextChapter;

  /// No description provided for @readerImagePathCopied.
  ///
  /// In zh, this message translates to:
  /// **'图片路径已复制到剪贴板'**
  String get readerImagePathCopied;

  /// No description provided for @readerImageUrlCopied.
  ///
  /// In zh, this message translates to:
  /// **'图片链接已复制到剪贴板'**
  String get readerImageUrlCopied;

  /// No description provided for @readerLocalImageMissing.
  ///
  /// In zh, this message translates to:
  /// **'本地图片损坏或缺失'**
  String get readerLocalImageMissing;

  /// No description provided for @readerCopyImagePath.
  ///
  /// In zh, this message translates to:
  /// **'复制图片路径'**
  String get readerCopyImagePath;

  /// No description provided for @readerImageRetrying.
  ///
  /// In zh, this message translates to:
  /// **'加载失败，正在重试 {attempt}/{total}'**
  String readerImageRetrying(int attempt, int total);

  /// No description provided for @readerReloadImage.
  ///
  /// In zh, this message translates to:
  /// **'重新加载'**
  String get readerReloadImage;

  /// No description provided for @readerCopyImageUrl.
  ///
  /// In zh, this message translates to:
  /// **'复制图片链接'**
  String get readerCopyImageUrl;

  /// No description provided for @updateAlreadyLatest.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本'**
  String get updateAlreadyLatest;

  /// No description provided for @updateCheckFailedRetryLater.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，请稍后重试'**
  String get updateCheckFailedRetryLater;

  /// No description provided for @updateOpenDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开下载链接'**
  String get updateOpenDownloadFailed;

  /// No description provided for @updateNoReleaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'暂无更新说明'**
  String get updateNoReleaseNotes;

  /// No description provided for @updateMirrorDownload.
  ///
  /// In zh, this message translates to:
  /// **'镜像下载'**
  String get updateMirrorDownload;

  /// No description provided for @updateLatestBadge.
  ///
  /// In zh, this message translates to:
  /// **'最新'**
  String get updateLatestBadge;

  /// No description provided for @updateCollapseOtherVersions.
  ///
  /// In zh, this message translates to:
  /// **'收起其他版本'**
  String get updateCollapseOtherVersions;

  /// No description provided for @updateViewMoreVersions.
  ///
  /// In zh, this message translates to:
  /// **'查看更多版本 ({count})'**
  String updateViewMoreVersions(int count);

  /// No description provided for @updateCiBuildUnstable.
  ///
  /// In zh, this message translates to:
  /// **'CI 自动构建版本，不保证稳定性。'**
  String get updateCiBuildUnstable;

  /// No description provided for @updateOpenReleasePage.
  ///
  /// In zh, this message translates to:
  /// **'打开发布页'**
  String get updateOpenReleasePage;

  /// No description provided for @updatePackagesBeta.
  ///
  /// In zh, this message translates to:
  /// **'安装包（按版本号倒序）'**
  String get updatePackagesBeta;

  /// No description provided for @updatePackages.
  ///
  /// In zh, this message translates to:
  /// **'安装包'**
  String get updatePackages;

  /// No description provided for @updateSkipVersion.
  ///
  /// In zh, this message translates to:
  /// **'跳过此版本'**
  String get updateSkipVersion;

  /// No description provided for @updateDisableAutoCheck.
  ///
  /// In zh, this message translates to:
  /// **'取消自动检查更新'**
  String get updateDisableAutoCheck;

  /// No description provided for @updateInstallInApp.
  ///
  /// In zh, this message translates to:
  /// **'应用内安装'**
  String get updateInstallInApp;

  /// No description provided for @updateInstallInAppMirror.
  ///
  /// In zh, this message translates to:
  /// **'镜像应用内安装'**
  String get updateInstallInAppMirror;

  /// No description provided for @updateDownloading.
  ///
  /// In zh, this message translates to:
  /// **'下载中 {percent}%'**
  String updateDownloading(int percent);

  /// No description provided for @updateDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败，请稍后重试'**
  String get updateDownloadFailed;

  /// No description provided for @updateInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法启动安装，请改用浏览器下载'**
  String get updateInstallFailed;

  /// No description provided for @updateInstallPermissionNeeded.
  ///
  /// In zh, this message translates to:
  /// **'需要「安装未知应用」权限才能安装更新'**
  String get updateInstallPermissionNeeded;

  /// No description provided for @updateDownloadPreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备下载…'**
  String get updateDownloadPreparing;

  /// No description provided for @updateInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在安装…'**
  String get updateInstalling;

  /// No description provided for @updateCardChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查更新…'**
  String get updateCardChecking;

  /// No description provided for @updateCardLatest.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本'**
  String get updateCardLatest;

  /// No description provided for @updateCardFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败，点击重试'**
  String get updateCardFailed;

  /// No description provided for @updateCardRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get updateCardRetry;

  /// No description provided for @updateButtonUpdate.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get updateButtonUpdate;

  /// No description provided for @updateManualDownload.
  ///
  /// In zh, this message translates to:
  /// **'手动下载'**
  String get updateManualDownload;

  /// No description provided for @updateUseMirror.
  ///
  /// In zh, this message translates to:
  /// **'使用镜像'**
  String get updateUseMirror;

  /// No description provided for @totalRank.
  ///
  /// In zh, this message translates to:
  /// **'总榜'**
  String get totalRank;

  /// No description provided for @maleAudience.
  ///
  /// In zh, this message translates to:
  /// **'男生'**
  String get maleAudience;

  /// No description provided for @femaleAudience.
  ///
  /// In zh, this message translates to:
  /// **'女生'**
  String get femaleAudience;

  /// No description provided for @noticeRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'刷新通知失败，请稍后重试'**
  String get noticeRefreshFailed;

  /// No description provided for @noticeReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取通知失败'**
  String get noticeReadFailed;

  /// No description provided for @noticeAllMarkedRead.
  ///
  /// In zh, this message translates to:
  /// **'所有通知已标记为已读'**
  String get noticeAllMarkedRead;

  /// No description provided for @noticeMarkAllReadTooltip.
  ///
  /// In zh, this message translates to:
  /// **'全部已读'**
  String get noticeMarkAllReadTooltip;

  /// No description provided for @noticeRefreshTooltip.
  ///
  /// In zh, this message translates to:
  /// **'刷新通知'**
  String get noticeRefreshTooltip;

  /// No description provided for @noticeEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无通知'**
  String get noticeEmptyTitle;

  /// No description provided for @noticeExpiredTitle.
  ///
  /// In zh, this message translates to:
  /// **'过期通知'**
  String get noticeExpiredTitle;

  /// No description provided for @noticePinnedNodeSemantics.
  ///
  /// In zh, this message translates to:
  /// **'置顶通知节点'**
  String get noticePinnedNodeSemantics;

  /// No description provided for @noticeNodeSemantics.
  ///
  /// In zh, this message translates to:
  /// **'通知节点'**
  String get noticeNodeSemantics;

  /// No description provided for @noticeOpenLink.
  ///
  /// In zh, this message translates to:
  /// **'打开链接'**
  String get noticeOpenLink;

  /// No description provided for @noticeUnreadSemantics.
  ///
  /// In zh, this message translates to:
  /// **'未读通知'**
  String get noticeUnreadSemantics;

  /// No description provided for @noticeExpiredBadge.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get noticeExpiredBadge;

  /// No description provided for @readerImageViewerSettingsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'查看器设置'**
  String get readerImageViewerSettingsTooltip;

  /// No description provided for @resetButton.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get resetButton;

  /// No description provided for @readerRotateLeft.
  ///
  /// In zh, this message translates to:
  /// **'向左旋转'**
  String get readerRotateLeft;

  /// No description provided for @readerRotateRight.
  ///
  /// In zh, this message translates to:
  /// **'向右旋转'**
  String get readerRotateRight;

  /// No description provided for @readerImageViewerSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'图片查看器设置'**
  String get readerImageViewerSettingsTitle;

  /// No description provided for @readerAutoRotateLandscape.
  ///
  /// In zh, this message translates to:
  /// **'横向图片自动旋转'**
  String get readerAutoRotateLandscape;

  /// No description provided for @readerAutoRotateLandscapeDesc.
  ///
  /// In zh, this message translates to:
  /// **'打开宽图时自动旋转 90 度'**
  String get readerAutoRotateLandscapeDesc;

  /// No description provided for @readerRotationDirection.
  ///
  /// In zh, this message translates to:
  /// **'旋转方向'**
  String get readerRotationDirection;

  /// No description provided for @readerRotateLeftShort.
  ///
  /// In zh, this message translates to:
  /// **'向左'**
  String get readerRotateLeftShort;

  /// No description provided for @readerRotateRightShort.
  ///
  /// In zh, this message translates to:
  /// **'向右'**
  String get readerRotateRightShort;

  /// No description provided for @browseHistoryLastSeenLabel.
  ///
  /// In zh, this message translates to:
  /// **'上次看到'**
  String get browseHistoryLastSeenLabel;

  /// No description provided for @playerProgressAutoResumed.
  ///
  /// In zh, this message translates to:
  /// **'{progress}（已自动继续）'**
  String playerProgressAutoResumed(String progress);

  /// No description provided for @playerSeekButton.
  ///
  /// In zh, this message translates to:
  /// **'跳转'**
  String get playerSeekButton;

  /// No description provided for @bangumiCommentsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'评论加载失败'**
  String get bangumiCommentsLoadFailed;

  /// No description provided for @bangumiCommentsRetryHint.
  ///
  /// In zh, this message translates to:
  /// **'下拉或点按钮重试'**
  String get bangumiCommentsRetryHint;

  /// No description provided for @bangumiCommentsEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有评论'**
  String get bangumiCommentsEmptyTitle;

  /// No description provided for @bangumiCommentsEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'暂时没有可显示的 Bangumi 评论'**
  String get bangumiCommentsEmptySubtitle;

  /// No description provided for @bangumiCommentsLoadMoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'更多评论加载失败'**
  String get bangumiCommentsLoadMoreFailed;

  /// No description provided for @bangumiCommentsRetryLoadMore.
  ///
  /// In zh, this message translates to:
  /// **'重试加载更多'**
  String get bangumiCommentsRetryLoadMore;

  /// No description provided for @bangumiCommentsLoadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get bangumiCommentsLoadMore;

  /// No description provided for @bangumiCommentsEmptyComment.
  ///
  /// In zh, this message translates to:
  /// **'这条评论没有内容'**
  String get bangumiCommentsEmptyComment;

  /// No description provided for @danmakuSearchTitle.
  ///
  /// In zh, this message translates to:
  /// **'弹幕搜索'**
  String get danmakuSearchTitle;

  /// No description provided for @danmakuSearchTitleWithCount.
  ///
  /// In zh, this message translates to:
  /// **'弹幕搜索（{count}）'**
  String danmakuSearchTitleWithCount(int count);

  /// No description provided for @danmakuLoadedTitle.
  ///
  /// In zh, this message translates to:
  /// **'已装载{count}发弹幕'**
  String danmakuLoadedTitle(int count);

  /// No description provided for @danmakuSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'输入搜索关键词'**
  String get danmakuSearchHint;

  /// No description provided for @forceRefreshTooltip.
  ///
  /// In zh, this message translates to:
  /// **'强制刷新'**
  String get forceRefreshTooltip;

  /// No description provided for @danmakuSearchInstruction.
  ///
  /// In zh, this message translates to:
  /// **'请选择分段或输入搜索词后点击搜索'**
  String get danmakuSearchInstruction;

  /// No description provided for @danmakuSearchResultCount.
  ///
  /// In zh, this message translates to:
  /// **'共找到 {count} 条结果'**
  String danmakuSearchResultCount(int count);

  /// No description provided for @danmakuSearchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'未找到相关弹幕'**
  String get danmakuSearchNoResults;

  /// No description provided for @danmakuSearchNoResultsHint.
  ///
  /// In zh, this message translates to:
  /// **'减少关键词，仅搜索作品名称\n如：「Re：从零开始的异世界生活第四季丧失篇」搜索「从零开始的异世界生活第四季」'**
  String get danmakuSearchNoResultsHint;

  /// No description provided for @danmakuLabel.
  ///
  /// In zh, this message translates to:
  /// **'弹幕'**
  String get danmakuLabel;

  /// No description provided for @dandanplayBindingSearchKeyword.
  ///
  /// In zh, this message translates to:
  /// **'搜索关键词'**
  String get dandanplayBindingSearchKeyword;

  /// No description provided for @dandanplayBindingClear.
  ///
  /// In zh, this message translates to:
  /// **'清除绑定'**
  String get dandanplayBindingClear;

  /// No description provided for @dandanplayBindingSearchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败：{error}'**
  String dandanplayBindingSearchFailed(String error);

  /// No description provided for @dandanplayBindingNoResults.
  ///
  /// In zh, this message translates to:
  /// **'未找到相关番剧'**
  String get dandanplayBindingNoResults;

  /// No description provided for @dandanplayBindingSearchInstruction.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词后点击搜索'**
  String get dandanplayBindingSearchInstruction;

  /// No description provided for @dandanplayBindingCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前绑定'**
  String get dandanplayBindingCurrent;

  /// No description provided for @dandanplayBindingBound.
  ///
  /// In zh, this message translates to:
  /// **'已绑定'**
  String get dandanplayBindingBound;

  /// No description provided for @dandanplayBindingUnbound.
  ///
  /// In zh, this message translates to:
  /// **'未绑定'**
  String get dandanplayBindingUnbound;

  /// No description provided for @dandanplayBindingBind.
  ///
  /// In zh, this message translates to:
  /// **'绑定'**
  String get dandanplayBindingBind;

  /// No description provided for @dandanplayBindingRating.
  ///
  /// In zh, this message translates to:
  /// **'评分 {rating}'**
  String dandanplayBindingRating(String rating);

  /// No description provided for @dandanplayAlignmentTitle.
  ///
  /// In zh, this message translates to:
  /// **'对齐弹幕'**
  String get dandanplayAlignmentTitle;

  /// No description provided for @dandanplayAlignmentVideoFirstEpisode.
  ///
  /// In zh, this message translates to:
  /// **'视频第一集'**
  String get dandanplayAlignmentVideoFirstEpisode;

  /// No description provided for @dandanplayAlignmentDanmakuFirstEpisode.
  ///
  /// In zh, this message translates to:
  /// **'弹幕第一集'**
  String get dandanplayAlignmentDanmakuFirstEpisode;

  /// No description provided for @dandanplayAlignmentClear.
  ///
  /// In zh, this message translates to:
  /// **'清除对齐'**
  String get dandanplayAlignmentClear;

  /// No description provided for @spoilerWarningTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧透警告'**
  String get spoilerWarningTitle;

  /// No description provided for @spoilerWarningContent.
  ///
  /// In zh, this message translates to:
  /// **'真的要打开吗？前方是地狱啊！'**
  String get spoilerWarningContent;

  /// No description provided for @openButton.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get openButton;

  /// No description provided for @spoilerSuspectedComment.
  ///
  /// In zh, this message translates to:
  /// **'这是一条高度剧透嫌疑的评论'**
  String get spoilerSuspectedComment;

  /// No description provided for @spoilerTapToView.
  ///
  /// In zh, this message translates to:
  /// **'含剧透，点击查看'**
  String get spoilerTapToView;

  /// No description provided for @mediaKitDownloadTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要下载播放组件'**
  String get mediaKitDownloadTitle;

  /// No description provided for @mediaKitDownloadMessage.
  ///
  /// In zh, this message translates to:
  /// **'首次使用动漫播放功能需下载播放组件（{size}）。下载后会保存在本地，软件更新无需重新下载。'**
  String mediaKitDownloadMessage(String size);

  /// No description provided for @mediaKitDownloadSourceLabel.
  ///
  /// In zh, this message translates to:
  /// **'下载来源'**
  String get mediaKitDownloadSourceLabel;

  /// No description provided for @mediaKitDownloadSourceGithub.
  ///
  /// In zh, this message translates to:
  /// **'GitHub'**
  String get mediaKitDownloadSourceGithub;

  /// No description provided for @mediaKitDownloadSourceGithubHint.
  ///
  /// In zh, this message translates to:
  /// **'直连 GitHub 官方资源'**
  String get mediaKitDownloadSourceGithubHint;

  /// No description provided for @mediaKitDownloadSourceMirror.
  ///
  /// In zh, this message translates to:
  /// **'镜像下载'**
  String get mediaKitDownloadSourceMirror;

  /// No description provided for @mediaKitDownloadSourceMirrorHint.
  ///
  /// In zh, this message translates to:
  /// **'使用当前镜像：{mirror}'**
  String mediaKitDownloadSourceMirrorHint(String mirror);

  /// No description provided for @mediaKitDownloadConfirm.
  ///
  /// In zh, this message translates to:
  /// **'开始下载'**
  String get mediaKitDownloadConfirm;

  /// No description provided for @mediaKitDownloadingTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在下载播放组件'**
  String get mediaKitDownloadingTitle;

  /// No description provided for @mediaKitDownloadFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get mediaKitDownloadFailedTitle;

  /// No description provided for @mediaKitDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载播放组件失败：{error}'**
  String mediaKitDownloadFailed(String error);

  /// No description provided for @mediaKitInitFailed.
  ///
  /// In zh, this message translates to:
  /// **'播放器初始化失败：{error}'**
  String mediaKitInitFailed(String error);

  /// No description provided for @mediaKitDownloadStageConnect.
  ///
  /// In zh, this message translates to:
  /// **'正在连接…'**
  String get mediaKitDownloadStageConnect;

  /// No description provided for @mediaKitDownloadBytesProgress.
  ///
  /// In zh, this message translates to:
  /// **'{received} / {total}'**
  String mediaKitDownloadBytesProgress(String received, String total);

  /// No description provided for @mediaKitDownloadBytesOnly.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {received}'**
  String mediaKitDownloadBytesOnly(String received);

  /// No description provided for @mediaKitDownloadTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接或下载超时，请切换 GitHub/镜像后重试'**
  String get mediaKitDownloadTimeout;

  /// No description provided for @mediaKitDownloadNetworkError.
  ///
  /// In zh, this message translates to:
  /// **'网络连接失败，请检查网络或切换下载来源'**
  String get mediaKitDownloadNetworkError;

  /// No description provided for @mediaKitDownloadStagePrepare.
  ///
  /// In zh, this message translates to:
  /// **'准备中…'**
  String get mediaKitDownloadStagePrepare;

  /// No description provided for @mediaKitDownloadStageDownload.
  ///
  /// In zh, this message translates to:
  /// **'正在下载…'**
  String get mediaKitDownloadStageDownload;

  /// No description provided for @mediaKitDownloadStageVerify.
  ///
  /// In zh, this message translates to:
  /// **'校验文件…'**
  String get mediaKitDownloadStageVerify;

  /// No description provided for @mediaKitDownloadStageExtract.
  ///
  /// In zh, this message translates to:
  /// **'解压组件…'**
  String get mediaKitDownloadStageExtract;

  /// No description provided for @mediaKitDownloadStageLoad.
  ///
  /// In zh, this message translates to:
  /// **'加载组件…'**
  String get mediaKitDownloadStageLoad;

  /// No description provided for @mediaKitDownloadStageDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get mediaKitDownloadStageDone;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
