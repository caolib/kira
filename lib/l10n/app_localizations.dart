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

  /// No description provided for @historyModeOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get historyModeOnline;

  /// No description provided for @historyModeLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地'**
  String get historyModeLocal;

  /// No description provided for @localReadingHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地阅读记录'**
  String get localReadingHistoryTitle;

  /// No description provided for @localHistorySearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索作品名'**
  String get localHistorySearchHint;

  /// No description provided for @localHistorySearchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的作品'**
  String get localHistorySearchEmpty;

  /// No description provided for @localHistoryTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条阅读记录'**
  String localHistoryTotal(int count);

  /// No description provided for @localHistoryPageProgress.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} / {total} 页'**
  String localHistoryPageProgress(int page, int total);

  /// No description provided for @localHistoryRemoveConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定移除《{name}》的本机阅读进度和已读标记吗？不会删除下载内容、书签或在线记录。'**
  String localHistoryRemoveConfirm(String name);

  /// No description provided for @localHistoryClearConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定清空本机所有{type}阅读进度和已读标记吗？不会删除下载内容、书签或在线记录。'**
  String localHistoryClearConfirm(String type);

  /// No description provided for @browseHistorySeenLabel.
  ///
  /// In zh, this message translates to:
  /// **'看到'**
  String get browseHistorySeenLabel;

  /// No description provided for @browseHistoryUpdatedAt.
  ///
  /// In zh, this message translates to:
  /// **'更新于 {time}'**
  String browseHistoryUpdatedAt(String time);

  /// No description provided for @comicTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get comicTabLabel;

  /// No description provided for @novelTitle.
  ///
  /// In zh, this message translates to:
  /// **'轻小说'**
  String get novelTitle;

  /// No description provided for @novelDownloadUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'该卷未下载或本地文件已损坏，请前往下载中心重新下载。'**
  String get novelDownloadUnavailable;

  /// No description provided for @cacheCategoryNovelHistory.
  ///
  /// In zh, this message translates to:
  /// **'轻小说阅读记录'**
  String get cacheCategoryNovelHistory;

  /// No description provided for @cacheNovelTextLabel.
  ///
  /// In zh, this message translates to:
  /// **'轻小说正文缓存'**
  String get cacheNovelTextLabel;

  /// No description provided for @cacheNovelTextDesc.
  ///
  /// In zh, this message translates to:
  /// **'已阅读分卷的本地正文，清除后重新在线阅读需要重新请求；已下载到本机的分卷不受影响。'**
  String get cacheNovelTextDesc;

  /// No description provided for @cacheNovelTextClearConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除已缓存的轻小说正文？阅读进度会保留，但离线时将无法继续阅读这些分卷。'**
  String get cacheNovelTextClearConfirm;

  /// No description provided for @cacheNovelTextCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除轻小说正文缓存'**
  String get cacheNovelTextCleared;

  /// No description provided for @searchTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get searchTabLabel;

  /// No description provided for @discoverTabLabel.
  ///
  /// In zh, this message translates to:
  /// **'发现'**
  String get discoverTabLabel;

  /// No description provided for @searchFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get searchFilterAll;

  /// No description provided for @searchEmptyResults.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关漫画，试试其他关键词'**
  String get searchEmptyResults;

  /// No description provided for @searchRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败，请重试'**
  String get searchRequestFailed;

  /// No description provided for @discoverEmptyResults.
  ///
  /// In zh, this message translates to:
  /// **'暂无符合条件的漫画，试试其他筛选条件'**
  String get discoverEmptyResults;

  /// No description provided for @discoverRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'漫画加载失败，请重试'**
  String get discoverRequestFailed;

  /// No description provided for @discoverFiltersFailed.
  ///
  /// In zh, this message translates to:
  /// **'筛选项加载失败，请重试'**
  String get discoverFiltersFailed;

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

  /// No description provided for @startupFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'启动失败'**
  String get startupFailedTitle;

  /// No description provided for @startupFailedBody.
  ///
  /// In zh, this message translates to:
  /// **'应用初始化没有完成，通常是安装包与设备环境不匹配。可先重试；若仍失败，请卸载后重新安装，或把下面的错误信息反馈给开发者。'**
  String get startupFailedBody;

  /// No description provided for @startupFailedDetails.
  ///
  /// In zh, this message translates to:
  /// **'错误信息'**
  String get startupFailedDetails;

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

  /// No description provided for @copyTopics.
  ///
  /// In zh, this message translates to:
  /// **'专题'**
  String get copyTopics;

  /// No description provided for @copyTopicComics.
  ///
  /// In zh, this message translates to:
  /// **'专题漫画'**
  String get copyTopicComics;

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

  /// No description provided for @switchToHotSource.
  ///
  /// In zh, this message translates to:
  /// **'切换到热辣源'**
  String get switchToHotSource;

  /// No description provided for @switchToCopySource.
  ///
  /// In zh, this message translates to:
  /// **'切换到拷贝源'**
  String get switchToCopySource;

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

  /// No description provided for @noNovelUpdates.
  ///
  /// In zh, this message translates to:
  /// **'没有轻小说更新'**
  String get noNovelUpdates;

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

  /// No description provided for @refreshFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败：{detail}'**
  String refreshFailedDetail(String detail);

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

  /// No description provided for @loginToViewBookshelf.
  ///
  /// In zh, this message translates to:
  /// **'登录后可继续查看书架'**
  String get loginToViewBookshelf;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索{mode}…'**
  String searchHint(String mode);

  /// No description provided for @searchClearTooltip.
  ///
  /// In zh, this message translates to:
  /// **'清空搜索内容'**
  String get searchClearTooltip;

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

  /// No description provided for @tagsExpandAll.
  ///
  /// In zh, this message translates to:
  /// **'展开'**
  String get tagsExpandAll;

  /// No description provided for @tagsCollapseAll.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get tagsCollapseAll;

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

  /// No description provided for @loadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get loadMore;

  /// No description provided for @loadMoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载更多失败，请重试'**
  String get loadMoreFailed;

  /// No description provided for @loadMoreProgress.
  ///
  /// In zh, this message translates to:
  /// **'加载更多（{loaded}/{total}）'**
  String loadMoreProgress(int loaded, int total);

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

  /// No description provided for @chapterUnit.
  ///
  /// In zh, this message translates to:
  /// **'章'**
  String get chapterUnit;

  /// No description provided for @generalTitle.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get generalTitle;

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

  /// No description provided for @autoCheckClipboardSharedLinksTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动识别剪贴板分享链接'**
  String get autoCheckClipboardSharedLinksTitle;

  /// No description provided for @backExitConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'返回两次退出应用'**
  String get backExitConfirmTitle;

  /// No description provided for @backAgainToExitToast.
  ///
  /// In zh, this message translates to:
  /// **'再次返回退出应用'**
  String get backAgainToExitToast;

  /// No description provided for @languageTitle.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get languageTitle;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageSimplified.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageSimplified;

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

  /// No description provided for @settingsBackupEmptyFile.
  ///
  /// In zh, this message translates to:
  /// **'文件里没有可导入的配置'**
  String get settingsBackupEmptyFile;

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

  /// No description provided for @resetAppTitle.
  ///
  /// In zh, this message translates to:
  /// **'重置应用'**
  String get resetAppTitle;

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

  /// No description provided for @copyButton.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copyButton;

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

  /// No description provided for @errorLogTitle.
  ///
  /// In zh, this message translates to:
  /// **'错误日志'**
  String get errorLogTitle;

  /// No description provided for @closeButton.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get closeButton;

  /// No description provided for @profileCopyCredentialLabel.
  ///
  /// In zh, this message translates to:
  /// **'拷贝漫画'**
  String get profileCopyCredentialLabel;

  /// No description provided for @profileHotCredentialLabel.
  ///
  /// In zh, this message translates to:
  /// **'热辣漫画'**
  String get profileHotCredentialLabel;

  /// No description provided for @accountAddedToast.
  ///
  /// In zh, this message translates to:
  /// **'账号已添加'**
  String get accountAddedToast;

  /// No description provided for @accountSwitchedToast.
  ///
  /// In zh, this message translates to:
  /// **'账号已切换'**
  String get accountSwitchedToast;

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

  /// No description provided for @userInfoRefreshFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'刷新失败：{detail}'**
  String userInfoRefreshFailedDetail(String detail);

  /// No description provided for @tokenUnavailableToast.
  ///
  /// In zh, this message translates to:
  /// **'暂无可复制的令牌'**
  String get tokenUnavailableToast;

  /// No description provided for @tokenCopiedToast.
  ///
  /// In zh, this message translates to:
  /// **'令牌已复制'**
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

  /// No description provided for @appearanceBottomNavLabelModeHidden.
  ///
  /// In zh, this message translates to:
  /// **'不显示文字'**
  String get appearanceBottomNavLabelModeHidden;

  /// No description provided for @appearanceBottomNavLabelModeAlways.
  ///
  /// In zh, this message translates to:
  /// **'始终显示文字'**
  String get appearanceBottomNavLabelModeAlways;

  /// No description provided for @appearanceFloatingNavLabelModeHint.
  ///
  /// In zh, this message translates to:
  /// **'悬浮底栏不支持始终显示文字，已改为选中时显示'**
  String get appearanceFloatingNavLabelModeHint;

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

  /// No description provided for @appearanceNavSwipeTitle.
  ///
  /// In zh, this message translates to:
  /// **'左右滑动切换页面'**
  String get appearanceNavSwipeTitle;

  /// No description provided for @appearanceFloatingNavTitle.
  ///
  /// In zh, this message translates to:
  /// **'悬浮导航栏'**
  String get appearanceFloatingNavTitle;

  /// No description provided for @appearanceAppIcon.
  ///
  /// In zh, this message translates to:
  /// **'应用图标'**
  String get appearanceAppIcon;

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

  /// No description provided for @appearanceCardShadowSize.
  ///
  /// In zh, this message translates to:
  /// **'统一阴影大小'**
  String get appearanceCardShadowSize;

  /// No description provided for @appearanceTextScale.
  ///
  /// In zh, this message translates to:
  /// **'全局文字缩放'**
  String get appearanceTextScale;

  /// No description provided for @appearanceThemeStyle.
  ///
  /// In zh, this message translates to:
  /// **'主题风格'**
  String get appearanceThemeStyle;

  /// No description provided for @appearanceThemeColor.
  ///
  /// In zh, this message translates to:
  /// **'主题配色'**
  String get appearanceThemeColor;

  /// No description provided for @appearanceDynamicColor.
  ///
  /// In zh, this message translates to:
  /// **'动态颜色'**
  String get appearanceDynamicColor;

  /// No description provided for @appearanceAmoledDark.
  ///
  /// In zh, this message translates to:
  /// **'AMOLED 纯黑模式'**
  String get appearanceAmoledDark;

  /// No description provided for @appearanceReduceMotionTitle.
  ///
  /// In zh, this message translates to:
  /// **'减少动画'**
  String get appearanceReduceMotionTitle;

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

  /// No description provided for @appearanceAutoSystem.
  ///
  /// In zh, this message translates to:
  /// **'自动（跟随系统）'**
  String get appearanceAutoSystem;

  /// No description provided for @appearanceAutoShort.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get appearanceAutoShort;

  /// No description provided for @appearanceAutoRefreshRate.
  ///
  /// In zh, this message translates to:
  /// **'自动 · {rate}Hz'**
  String appearanceAutoRefreshRate(int rate);

  /// No description provided for @appearanceRefreshRateCurrent.
  ///
  /// In zh, this message translates to:
  /// **'{rate}Hz（当前）'**
  String appearanceRefreshRateCurrent(int rate);

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

  /// No description provided for @appearanceDesktopFont.
  ///
  /// In zh, this message translates to:
  /// **'系统字体'**
  String get appearanceDesktopFont;

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

  /// No description provided for @appearanceImportLocalFont.
  ///
  /// In zh, this message translates to:
  /// **'从本地导入字体'**
  String get appearanceImportLocalFont;

  /// No description provided for @appearanceImportFontInvalid.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该字体文件，请选择有效的 .ttf / .otf 字体'**
  String get appearanceImportFontInvalid;

  /// No description provided for @appearanceImportFontFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入字体失败：{error}'**
  String appearanceImportFontFailed(String error);

  /// No description provided for @appearanceCustomFontRemoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除自定义字体'**
  String get appearanceCustomFontRemoveTitle;

  /// No description provided for @appearanceCustomFontRemoveContent.
  ///
  /// In zh, this message translates to:
  /// **'确定要移除自定义字体 {fontName} 吗？'**
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

  /// No description provided for @networkSelectionMode.
  ///
  /// In zh, this message translates to:
  /// **'选择模式'**
  String get networkSelectionMode;

  /// No description provided for @networkAutoTestEnabled.
  ///
  /// In zh, this message translates to:
  /// **'定时测速并切换线路'**
  String get networkAutoTestEnabled;

  /// No description provided for @networkAutoTestInterval.
  ///
  /// In zh, this message translates to:
  /// **'测速间隔'**
  String get networkAutoTestInterval;

  /// No description provided for @networkModeRoute.
  ///
  /// In zh, this message translates to:
  /// **'线路'**
  String get networkModeRoute;

  /// No description provided for @networkRouteLabel.
  ///
  /// In zh, this message translates to:
  /// **'线路 {index}'**
  String networkRouteLabel(int index);

  /// No description provided for @networkTestingNodes.
  ///
  /// In zh, this message translates to:
  /// **'正在检测各节点…'**
  String get networkTestingNodes;

  /// No description provided for @networkSpeedTestFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'测速失败：{detail}'**
  String networkSpeedTestFailedDetail(String detail);

  /// No description provided for @networkHighLatencyHint.
  ///
  /// In zh, this message translates to:
  /// **'当前线路延迟较高'**
  String get networkHighLatencyHint;

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

  /// No description provided for @networkCopyApiHost.
  ///
  /// In zh, this message translates to:
  /// **'拷贝节点'**
  String get networkCopyApiHost;

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

  /// No description provided for @networkProxyDirect.
  ///
  /// In zh, this message translates to:
  /// **'直连'**
  String get networkProxyDirect;

  /// No description provided for @networkProxyDirectActive.
  ///
  /// In zh, this message translates to:
  /// **'直连（不使用代理）'**
  String get networkProxyDirectActive;

  /// No description provided for @networkProxyDirectHint.
  ///
  /// In zh, this message translates to:
  /// **'已忽略系统代理，所有请求直接连接'**
  String get networkProxyDirectHint;

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

  /// No description provided for @networkAdvancedSettings.
  ///
  /// In zh, this message translates to:
  /// **'高级设置'**
  String get networkAdvancedSettings;

  /// No description provided for @networkCopyLoginDomain.
  ///
  /// In zh, this message translates to:
  /// **'拷贝登录域名'**
  String get networkCopyLoginDomain;

  /// No description provided for @networkCopyLoginDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'拷贝账号登录接口使用的域名，登录失败时可切换重试'**
  String get networkCopyLoginDomainHint;

  /// No description provided for @networkCopyLoginDomainDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get networkCopyLoginDomainDefault;

  /// No description provided for @networkCopyLoginDomainCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get networkCopyLoginDomainCustom;

  /// No description provided for @networkCopyLoginDomainEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'修改登录域名'**
  String get networkCopyLoginDomainEditTitle;

  /// No description provided for @networkCopyLoginDomainDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'该域名已在列表中'**
  String get networkCopyLoginDomainDuplicate;

  /// No description provided for @networkCopyAppVersion.
  ///
  /// In zh, this message translates to:
  /// **'COPY 请求版本号'**
  String get networkCopyAppVersion;

  /// No description provided for @networkCopyVersionCode.
  ///
  /// In zh, this message translates to:
  /// **'COPY versionCode'**
  String get networkCopyVersionCode;

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
  /// **'当前延迟约 {ms} ms'**
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

  /// No description provided for @networkModeFixedNodeShort.
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get networkModeFixedNodeShort;

  /// No description provided for @networkCurrentInUse.
  ///
  /// In zh, this message translates to:
  /// **'使用中'**
  String get networkCurrentInUse;

  /// No description provided for @networkNodesSectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'线路与节点'**
  String get networkNodesSectionTitle;

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

  /// No description provided for @aiConfigProviderSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个模型 · {format}\n{baseUrl}'**
  String aiConfigProviderSummary(int count, String format, String baseUrl);

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

  /// No description provided for @aiConfigSearchModel.
  ///
  /// In zh, this message translates to:
  /// **'搜索模型'**
  String get aiConfigSearchModel;

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
  /// **'获取模型'**
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

  /// No description provided for @aiConfigAgnesName.
  ///
  /// In zh, this message translates to:
  /// **'Agnes'**
  String get aiConfigAgnesName;

  /// No description provided for @aiConfigGetAgnesApiKey.
  ///
  /// In zh, this message translates to:
  /// **'获取 Agnes API 密钥'**
  String get aiConfigGetAgnesApiKey;

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

  /// No description provided for @aiConfigClearSessions.
  ///
  /// In zh, this message translates to:
  /// **'清空会话'**
  String get aiConfigClearSessions;

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

  /// No description provided for @bookmarksTitle.
  ///
  /// In zh, this message translates to:
  /// **'书签'**
  String get bookmarksTitle;

  /// No description provided for @bookmarksTabClearContent.
  ///
  /// In zh, this message translates to:
  /// **'确定清空所有{type}书签？'**
  String bookmarksTabClearContent(String type);

  /// No description provided for @novelBookmarksEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读轻小说时，点击工具栏右上角添加书签'**
  String get novelBookmarksEmptySubtitle;

  /// No description provided for @bookmarksLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'书签加载失败，请重试'**
  String get bookmarksLoadFailed;

  /// No description provided for @bookmarksUpdateFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'书签保存失败：{detail}'**
  String bookmarksUpdateFailedDetail(String detail);

  /// No description provided for @bookmarksSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索书名或章节'**
  String get bookmarksSearchHint;

  /// No description provided for @bookmarksSearchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关书签，试试其他关键词'**
  String get bookmarksSearchEmpty;

  /// No description provided for @statsTitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读统计'**
  String get statsTitle;

  /// No description provided for @continueReadingPageLabel.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} 页'**
  String continueReadingPageLabel(int page);

  /// No description provided for @continueReadingChapterFallback.
  ///
  /// In zh, this message translates to:
  /// **'未知章节'**
  String get continueReadingChapterFallback;

  /// No description provided for @statsEnableTitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读统计'**
  String get statsEnableTitle;

  /// No description provided for @statsEnableButton.
  ///
  /// In zh, this message translates to:
  /// **'开启'**
  String get statsEnableButton;

  /// No description provided for @statsDisableButton.
  ///
  /// In zh, this message translates to:
  /// **'统计功能'**
  String get statsDisableButton;

  /// No description provided for @statsRecordComics.
  ///
  /// In zh, this message translates to:
  /// **'读过的漫画数量'**
  String get statsRecordComics;

  /// No description provided for @statsRecordChapters.
  ///
  /// In zh, this message translates to:
  /// **'读过的章节数量'**
  String get statsRecordChapters;

  /// No description provided for @statsRecordPages.
  ///
  /// In zh, this message translates to:
  /// **'阅读页数'**
  String get statsRecordPages;

  /// No description provided for @statsRecordTags.
  ///
  /// In zh, this message translates to:
  /// **'常看类型'**
  String get statsRecordTags;

  /// No description provided for @statsRecordHeatmap.
  ///
  /// In zh, this message translates to:
  /// **'每日阅读活跃度热力图'**
  String get statsRecordHeatmap;

  /// No description provided for @statsPrivacyNote.
  ///
  /// In zh, this message translates to:
  /// **'数据仅保存在本地，不上传服务器，可随时关闭或清除。'**
  String get statsPrivacyNote;

  /// No description provided for @statsComicsRead.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get statsComicsRead;

  /// No description provided for @statsChaptersRead.
  ///
  /// In zh, this message translates to:
  /// **'章节'**
  String get statsChaptersRead;

  /// No description provided for @statsPagesRead.
  ///
  /// In zh, this message translates to:
  /// **'页数'**
  String get statsPagesRead;

  /// No description provided for @statsTopTags.
  ///
  /// In zh, this message translates to:
  /// **'常看类型'**
  String get statsTopTags;

  /// No description provided for @statsNoTags.
  ///
  /// In zh, this message translates to:
  /// **'暂无标签数据'**
  String get statsNoTags;

  /// No description provided for @statsActivityHeatmap.
  ///
  /// In zh, this message translates to:
  /// **'阅读活跃度'**
  String get statsActivityHeatmap;

  /// No description provided for @statsHeatmapLess.
  ///
  /// In zh, this message translates to:
  /// **'少'**
  String get statsHeatmapLess;

  /// No description provided for @statsHeatmapMore.
  ///
  /// In zh, this message translates to:
  /// **'多'**
  String get statsHeatmapMore;

  /// No description provided for @statsHeatmapWeekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get statsHeatmapWeekdayMon;

  /// No description provided for @statsHeatmapWeekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get statsHeatmapWeekdayWed;

  /// No description provided for @statsHeatmapWeekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get statsHeatmapWeekdayFri;

  /// No description provided for @statsRecordingSince.
  ///
  /// In zh, this message translates to:
  /// **'开始于 {date}'**
  String statsRecordingSince(String date);

  /// No description provided for @statsPagesOnDate.
  ///
  /// In zh, this message translates to:
  /// **'{count} 页'**
  String statsPagesOnDate(int count);

  /// No description provided for @statsBarChartWeekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get statsBarChartWeekdayMon;

  /// No description provided for @statsBarChartWeekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'二'**
  String get statsBarChartWeekdayTue;

  /// No description provided for @statsBarChartWeekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get statsBarChartWeekdayWed;

  /// No description provided for @statsBarChartWeekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'四'**
  String get statsBarChartWeekdayThu;

  /// No description provided for @statsBarChartWeekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get statsBarChartWeekdayFri;

  /// No description provided for @statsBarChartWeekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'六'**
  String get statsBarChartWeekdaySat;

  /// No description provided for @statsBarChartWeekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get statsBarChartWeekdaySun;

  /// No description provided for @statsChartStyle.
  ///
  /// In zh, this message translates to:
  /// **'图表样式'**
  String get statsChartStyle;

  /// No description provided for @statsChartStyleHeatmap.
  ///
  /// In zh, this message translates to:
  /// **'热力图'**
  String get statsChartStyleHeatmap;

  /// No description provided for @statsChartStyleHeatmapDesc.
  ///
  /// In zh, this message translates to:
  /// **'按周展示近一年阅读活跃度'**
  String get statsChartStyleHeatmapDesc;

  /// No description provided for @statsChartStyleBar.
  ///
  /// In zh, this message translates to:
  /// **'条形图'**
  String get statsChartStyleBar;

  /// No description provided for @statsChartStyleBarDesc.
  ///
  /// In zh, this message translates to:
  /// **'按天展示两周阅读页数'**
  String get statsChartStyleBarDesc;

  /// No description provided for @statsShowSections.
  ///
  /// In zh, this message translates to:
  /// **'显示组件'**
  String get statsShowSections;

  /// No description provided for @statsDragToReorder.
  ///
  /// In zh, this message translates to:
  /// **'长按拖动排序'**
  String get statsDragToReorder;

  /// No description provided for @statsSectionOverview.
  ///
  /// In zh, this message translates to:
  /// **'概览'**
  String get statsSectionOverview;

  /// No description provided for @statsSectionTags.
  ///
  /// In zh, this message translates to:
  /// **'常看类型'**
  String get statsSectionTags;

  /// No description provided for @statsSectionActivity.
  ///
  /// In zh, this message translates to:
  /// **'阅读活跃度'**
  String get statsSectionActivity;

  /// No description provided for @statsKeepAtLeastOne.
  ///
  /// In zh, this message translates to:
  /// **'至少保留一个组件'**
  String get statsKeepAtLeastOne;

  /// No description provided for @statsClearButton.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get statsClearButton;

  /// No description provided for @statsClearConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除阅读统计？'**
  String get statsClearConfirmTitle;

  /// No description provided for @statsClearConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'将删除全部阅读统计数据，此操作不可恢复。'**
  String get statsClearConfirmContent;

  /// No description provided for @statsSettings.
  ///
  /// In zh, this message translates to:
  /// **'阅读统计设置'**
  String get statsSettings;

  /// No description provided for @bookmarkAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加书签'**
  String get bookmarkAdd;

  /// No description provided for @bookmarkRemove.
  ///
  /// In zh, this message translates to:
  /// **'取消书签'**
  String get bookmarkRemove;

  /// No description provided for @bookmarkAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加书签'**
  String get bookmarkAdded;

  /// No description provided for @bookmarkRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已取消书签'**
  String get bookmarkRemoved;

  /// No description provided for @bookmarkRemoveGroupContent.
  ///
  /// In zh, this message translates to:
  /// **'该作品有 {count} 条书签，取消书签会一并删除。'**
  String bookmarkRemoveGroupContent(int count);

  /// No description provided for @bookmarkPage.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} 页'**
  String bookmarkPage(int page);

  /// No description provided for @bookmarkDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除书签'**
  String get bookmarkDeleted;

  /// No description provided for @bookmarkUndo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get bookmarkUndo;

  /// No description provided for @bookmarksCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条书签'**
  String bookmarksCount(int count);

  /// No description provided for @bookmarksEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有书签'**
  String get bookmarksEmptyTitle;

  /// No description provided for @bookmarksEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读时点右上角书签即可标记'**
  String get bookmarksEmptySubtitle;

  /// No description provided for @bookmarksClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空书签'**
  String get bookmarksClearTitle;

  /// No description provided for @bookmarksGroupDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 条书签'**
  String bookmarksGroupDeleted(int count);

  /// No description provided for @bookmarksSwipeHint.
  ///
  /// In zh, this message translates to:
  /// **'向左滑动书签可以删除'**
  String get bookmarksSwipeHint;

  /// No description provided for @aboutTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get aboutTitle;

  /// No description provided for @aboutBrandTagline.
  ///
  /// In zh, this message translates to:
  /// **'Kira 是一个开源免费的漫画阅读 App'**
  String get aboutBrandTagline;

  /// No description provided for @notLoggedInTitle.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get notLoggedInTitle;

  /// No description provided for @refreshUserButton.
  ///
  /// In zh, this message translates to:
  /// **'刷新用户'**
  String get refreshUserButton;

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

  /// No description provided for @profileUsernamePasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名和密码'**
  String get profileUsernamePasswordRequired;

  /// No description provided for @profileLoginFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'登录失败：{detail}'**
  String profileLoginFailedDetail(String detail);

  /// No description provided for @profileLoginIpBlockedHint.
  ///
  /// In zh, this message translates to:
  /// **'当前 IP 被封禁，请更换网络环境或代理节点后重试'**
  String get profileLoginIpBlockedHint;

  /// No description provided for @profileTokenRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入令牌'**
  String get profileTokenRequired;

  /// No description provided for @profileLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get profileLoginTitle;

  /// No description provided for @profileTokenLoginEntry.
  ///
  /// In zh, this message translates to:
  /// **'令牌登录'**
  String get profileTokenLoginEntry;

  /// No description provided for @copyAccountChannelWebApi.
  ///
  /// In zh, this message translates to:
  /// **'网页接口'**
  String get copyAccountChannelWebApi;

  /// No description provided for @copyAccountChannelWeb.
  ///
  /// In zh, this message translates to:
  /// **'网页'**
  String get copyAccountChannelWeb;

  /// No description provided for @copyAccountChannelApp.
  ///
  /// In zh, this message translates to:
  /// **'App接口'**
  String get copyAccountChannelApp;

  /// No description provided for @copyAccountInterfaceLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败：{detail}'**
  String copyAccountInterfaceLoginFailed(String detail);

  /// No description provided for @profileWebLoginPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'官网登录'**
  String get profileWebLoginPageTitle;

  /// No description provided for @profileWebLoginHint.
  ///
  /// In zh, this message translates to:
  /// **'在应用内打开拷贝官网登录页并自动填入账号密码，由网页完成登录后自动回填。'**
  String get profileWebLoginHint;

  /// No description provided for @profileWebLoginCompleting.
  ///
  /// In zh, this message translates to:
  /// **'已获取登录信息，正在验证…'**
  String get profileWebLoginCompleting;

  /// No description provided for @profileWebLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'官网登录失败'**
  String get profileWebLoginFailed;

  /// No description provided for @profileCopyAutoLoginRejected.
  ///
  /// In zh, this message translates to:
  /// **'登录被拒绝：{detail}'**
  String profileCopyAutoLoginRejected(String detail);

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

  /// No description provided for @profileLoginButton.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get profileLoginButton;

  /// No description provided for @profileOpenOfficialRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开官网注册页'**
  String get profileOpenOfficialRegisterFailed;

  /// No description provided for @loginGoOfficialRegister.
  ///
  /// In zh, this message translates to:
  /// **'前往官网注册账号'**
  String get loginGoOfficialRegister;

  /// No description provided for @aboutMirrorPrefixTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置镜像源'**
  String get aboutMirrorPrefixTitle;

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

  /// No description provided for @aboutBetaChannelConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'是否切换?'**
  String get aboutBetaChannelConfirmTitle;

  /// No description provided for @aboutBetaChannelNote.
  ///
  /// In zh, this message translates to:
  /// **'预览版更新更快，问题也可能更多'**
  String get aboutBetaChannelNote;

  /// No description provided for @aboutBetaChannelArm64Only.
  ///
  /// In zh, this message translates to:
  /// **'仅限 Android arm64 设备。'**
  String get aboutBetaChannelArm64Only;

  /// No description provided for @aboutBetaChannelDevice.
  ///
  /// In zh, this message translates to:
  /// **'当前设备：{os} {arch}。'**
  String aboutBetaChannelDevice(String os, String arch);

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

  /// No description provided for @aboutLicenseTitle.
  ///
  /// In zh, this message translates to:
  /// **'开源许可'**
  String get aboutLicenseTitle;

  /// No description provided for @licenseMitSummary.
  ///
  /// In zh, this message translates to:
  /// **'本项目采用 MIT 开源许可证'**
  String get licenseMitSummary;

  /// No description provided for @licenseThirdPartyTitle.
  ///
  /// In zh, this message translates to:
  /// **'第三方依赖'**
  String get licenseThirdPartyTitle;

  /// No description provided for @licenseFontsTitle.
  ///
  /// In zh, this message translates to:
  /// **'字体'**
  String get licenseFontsTitle;

  /// No description provided for @licenseThirdPartyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'未收集到第三方许可'**
  String get licenseThirdPartyEmpty;

  /// No description provided for @licenseCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 份许可'**
  String licenseCount(int count);

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
  /// **'漫画阅读器'**
  String get cacheReaderImageLabel;

  /// No description provided for @cacheReaderImageDesc.
  ///
  /// In zh, this message translates to:
  /// **'漫画章节图片缓存。再次打开读过的章节时，图片会优先从这里读取。'**
  String get cacheReaderImageDesc;

  /// No description provided for @cacheDefaultImageLabel.
  ///
  /// In zh, this message translates to:
  /// **'封面与头像'**
  String get cacheDefaultImageLabel;

  /// No description provided for @cacheDefaultImageDesc.
  ///
  /// In zh, this message translates to:
  /// **'封面、头像等 CachedNetworkImage 默认使用的图片缓存。'**
  String get cacheDefaultImageDesc;

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

  /// No description provided for @commentSettingsDisplaySection.
  ///
  /// In zh, this message translates to:
  /// **'评论区布局'**
  String get commentSettingsDisplaySection;

  /// No description provided for @commentSettingsLoadingSection.
  ///
  /// In zh, this message translates to:
  /// **'加载'**
  String get commentSettingsLoadingSection;

  /// No description provided for @commentSettingsFilteringSection.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽'**
  String get commentSettingsFilteringSection;

  /// No description provided for @commentSettingsInitialCountTitle.
  ///
  /// In zh, this message translates to:
  /// **'初始加载{count}条评论'**
  String commentSettingsInitialCountTitle(int count);

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

  /// No description provided for @chapterCommentsTotalCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String chapterCommentsTotalCount(int count);

  /// No description provided for @chapterCommentsCountWithBlocked.
  ///
  /// In zh, this message translates to:
  /// **'{shown}/{total}|{blocked}'**
  String chapterCommentsCountWithBlocked(int shown, int total, int blocked);

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
  /// **'回复 {userName}…'**
  String comicCommentReplyHint(String userName);

  /// No description provided for @comicCommentPostHint.
  ///
  /// In zh, this message translates to:
  /// **'说点什么…'**
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
  /// **'到末页后直接拼接下一话，上滑到顶拼接上一话，不重新加载'**
  String get readerContinuousReadingDesc;

  /// No description provided for @readerHorizontalImageScale.
  ///
  /// In zh, this message translates to:
  /// **'横向图片大小'**
  String get readerHorizontalImageScale;

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

  /// No description provided for @readerLongPressZoom.
  ///
  /// In zh, this message translates to:
  /// **'长按缩放'**
  String get readerLongPressZoom;

  /// No description provided for @readerLongPressZoomDesc.
  ///
  /// In zh, this message translates to:
  /// **'长按图片放大，按住移动可查看细节，松手恢复'**
  String get readerLongPressZoomDesc;

  /// No description provided for @readerLongPressZoomPanSensitivity.
  ///
  /// In zh, this message translates to:
  /// **'拖动灵敏度'**
  String get readerLongPressZoomPanSensitivity;

  /// No description provided for @readerStatusOverlay.
  ///
  /// In zh, this message translates to:
  /// **'状态显示'**
  String get readerStatusOverlay;

  /// No description provided for @readerStatusTime.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get readerStatusTime;

  /// No description provided for @readerStatusNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get readerStatusNetwork;

  /// No description provided for @readerStatusBattery.
  ///
  /// In zh, this message translates to:
  /// **'电量'**
  String get readerStatusBattery;

  /// No description provided for @readerStatusChapter.
  ///
  /// In zh, this message translates to:
  /// **'章节名'**
  String get readerStatusChapter;

  /// No description provided for @readerStatusPage.
  ///
  /// In zh, this message translates to:
  /// **'页码'**
  String get readerStatusPage;

  /// No description provided for @readerStatusProgress.
  ///
  /// In zh, this message translates to:
  /// **'进度'**
  String get readerStatusProgress;

  /// No description provided for @readerStatusFps.
  ///
  /// In zh, this message translates to:
  /// **'帧率'**
  String get readerStatusFps;

  /// No description provided for @readerStatusOverlayPosition.
  ///
  /// In zh, this message translates to:
  /// **'显示位置'**
  String get readerStatusOverlayPosition;

  /// No description provided for @readerStatusOverlayTopLeft.
  ///
  /// In zh, this message translates to:
  /// **'左上'**
  String get readerStatusOverlayTopLeft;

  /// No description provided for @readerStatusOverlayTopCenter.
  ///
  /// In zh, this message translates to:
  /// **'顶部中间'**
  String get readerStatusOverlayTopCenter;

  /// No description provided for @readerStatusOverlayTopRight.
  ///
  /// In zh, this message translates to:
  /// **'右上'**
  String get readerStatusOverlayTopRight;

  /// No description provided for @readerStatusOverlayBottomRight.
  ///
  /// In zh, this message translates to:
  /// **'右下'**
  String get readerStatusOverlayBottomRight;

  /// No description provided for @readerStatusOverlayBottomCenter.
  ///
  /// In zh, this message translates to:
  /// **'底部中间'**
  String get readerStatusOverlayBottomCenter;

  /// No description provided for @readerStatusOverlayBottomLeft.
  ///
  /// In zh, this message translates to:
  /// **'左下'**
  String get readerStatusOverlayBottomLeft;

  /// No description provided for @readerStatusOverlayOpacity.
  ///
  /// In zh, this message translates to:
  /// **'背景不透明度'**
  String get readerStatusOverlayOpacity;

  /// No description provided for @readerStatusOverlayForeground.
  ///
  /// In zh, this message translates to:
  /// **'前景色'**
  String get readerStatusOverlayForeground;

  /// No description provided for @readerStatusOverlayBackground.
  ///
  /// In zh, this message translates to:
  /// **'背景色'**
  String get readerStatusOverlayBackground;

  /// No description provided for @readerStatusOverlayFollowTheme.
  ///
  /// In zh, this message translates to:
  /// **'跟随阅读主题'**
  String get readerStatusOverlayFollowTheme;

  /// No description provided for @readerStatusOverlayDefaultColor.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get readerStatusOverlayDefaultColor;

  /// No description provided for @readerStatusOverlayColorPicker.
  ///
  /// In zh, this message translates to:
  /// **'选择颜色'**
  String get readerStatusOverlayColorPicker;

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

  /// No description provided for @browseHistoryLoginHintComicOnly.
  ///
  /// In zh, this message translates to:
  /// **'浏览过的漫画会同步显示在这里'**
  String get browseHistoryLoginHintComicOnly;

  /// No description provided for @browseHistoryLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'浏览记录加载失败：{detail}'**
  String browseHistoryLoadFailed(String detail);

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

  /// No description provided for @browseHistoryLatestLabel.
  ///
  /// In zh, this message translates to:
  /// **'最新'**
  String get browseHistoryLatestLabel;

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

  /// No description provided for @cacheImageCacheSection.
  ///
  /// In zh, this message translates to:
  /// **'图片缓存'**
  String get cacheImageCacheSection;

  /// No description provided for @cacheNovelTextSection.
  ///
  /// In zh, this message translates to:
  /// **'轻小说缓存'**
  String get cacheNovelTextSection;

  /// No description provided for @cacheDataCacheSection.
  ///
  /// In zh, this message translates to:
  /// **'数据缓存'**
  String get cacheDataCacheSection;

  /// No description provided for @cacheDataCacheWarning.
  ///
  /// In zh, this message translates to:
  /// **'数据缓存包含书架、设置与阅读历史，删除会丢失。'**
  String get cacheDataCacheWarning;

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

  /// No description provided for @appLogDisabledTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志记录已关闭'**
  String get appLogDisabledTitle;

  /// No description provided for @appLogCopied.
  ///
  /// In zh, this message translates to:
  /// **'日志已复制'**
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

  /// No description provided for @appLogExportTooltip.
  ///
  /// In zh, this message translates to:
  /// **'导出日志文件'**
  String get appLogExportTooltip;

  /// No description provided for @appLogExported.
  ///
  /// In zh, this message translates to:
  /// **'日志已导出'**
  String get appLogExported;

  /// No description provided for @appLogExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{error}'**
  String appLogExportFailed(String error);

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

  /// No description provided for @comicDetailShare.
  ///
  /// In zh, this message translates to:
  /// **'分享漫画'**
  String get comicDetailShare;

  /// No description provided for @comicDetailShareContent.
  ///
  /// In zh, this message translates to:
  /// **'《{name}》 {url}'**
  String comicDetailShareContent(String name, String url);

  /// No description provided for @sharedLinkDetected.
  ///
  /// In zh, this message translates to:
  /// **'检测到分享的漫画《{name}》'**
  String sharedLinkDetected(String name);

  /// No description provided for @sharedLinkOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get sharedLinkOpen;

  /// No description provided for @comicDetailAddedToDownloadQueue.
  ///
  /// In zh, this message translates to:
  /// **'已加入下载队列：{count} 章'**
  String comicDetailAddedToDownloadQueue(int count);

  /// No description provided for @comicDetailSelectedAlreadyDownloadedOrQueued.
  ///
  /// In zh, this message translates to:
  /// **'所选章节已下载或已在队列中'**
  String get comicDetailSelectedAlreadyDownloadedOrQueued;

  /// No description provided for @comicDetailDownloadSelectedCount.
  ///
  /// In zh, this message translates to:
  /// **'下载{count}话'**
  String comicDetailDownloadSelectedCount(int count);

  /// No description provided for @downloadSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get downloadSettingsTitle;

  /// No description provided for @downloadImageConcurrency.
  ///
  /// In zh, this message translates to:
  /// **'并发线程数'**
  String get downloadImageConcurrency;

  /// No description provided for @downloadImageConcurrencyDesc.
  ///
  /// In zh, this message translates to:
  /// **'并发设置过大有 IP 被限流或封禁的风险，后果自负'**
  String get downloadImageConcurrencyDesc;

  /// No description provided for @downloadChapterComments.
  ///
  /// In zh, this message translates to:
  /// **'下载章节评论'**
  String get downloadChapterComments;

  /// No description provided for @comicDownloadSection.
  ///
  /// In zh, this message translates to:
  /// **'漫画下载设置'**
  String get comicDownloadSection;

  /// No description provided for @novelDownloadSection.
  ///
  /// In zh, this message translates to:
  /// **'轻小说下载设置'**
  String get novelDownloadSection;

  /// No description provided for @novelDownloadDirectoryOverlap.
  ///
  /// In zh, this message translates to:
  /// **'轻小说与漫画下载目录不能相同或互相包含'**
  String get novelDownloadDirectoryOverlap;

  /// No description provided for @novelDownloadMigrateConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'将把已下载的 {count} 部轻小说移动到新目录，迁移期间请勿退出应用。'**
  String novelDownloadMigrateConfirmContent(int count);

  /// No description provided for @downloadSaveLocation.
  ///
  /// In zh, this message translates to:
  /// **'保存位置'**
  String get downloadSaveLocation;

  /// No description provided for @downloadSaveLocationDefault.
  ///
  /// In zh, this message translates to:
  /// **'应用内部目录（默认）'**
  String get downloadSaveLocationDefault;

  /// No description provided for @downloadSaveLocationPickerTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择下载保存目录'**
  String get downloadSaveLocationPickerTitle;

  /// No description provided for @downloadSaveLocationPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'未授予存储权限，无法自定义保存目录'**
  String get downloadSaveLocationPermissionDenied;

  /// No description provided for @downloadSaveLocationNotWritable.
  ///
  /// In zh, this message translates to:
  /// **'所选目录不可写，请更换其他目录'**
  String get downloadSaveLocationNotWritable;

  /// No description provided for @downloadSaveLocationReset.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认目录'**
  String get downloadSaveLocationReset;

  /// No description provided for @downloadSaveLocationChanged.
  ///
  /// In zh, this message translates to:
  /// **'保存目录已更新'**
  String get downloadSaveLocationChanged;

  /// No description provided for @downloadMigrateConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'迁移已有下载？'**
  String get downloadMigrateConfirmTitle;

  /// No description provided for @downloadMigrateConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'将把已下载的 {count} 部漫画移动到新目录，迁移期间请勿退出应用。'**
  String downloadMigrateConfirmContent(int count);

  /// No description provided for @downloadMigratingTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在迁移下载内容'**
  String get downloadMigratingTitle;

  /// No description provided for @downloadMigratingProgress.
  ///
  /// In zh, this message translates to:
  /// **'{current} / {total}'**
  String downloadMigratingProgress(int current, int total);

  /// No description provided for @downloadQueueBusy.
  ///
  /// In zh, this message translates to:
  /// **'有下载任务进行中，请等待完成后再更改保存目录'**
  String get downloadQueueBusy;

  /// No description provided for @downloadSaveLocationFailed.
  ///
  /// In zh, this message translates to:
  /// **'更改保存目录失败：{reason}'**
  String downloadSaveLocationFailed(String reason);

  /// No description provided for @comicDetailSequentialDownloading.
  ///
  /// In zh, this message translates to:
  /// **'下载中 {count} 章'**
  String comicDetailSequentialDownloading(int count);

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

  /// No description provided for @novelDownloadCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get novelDownloadCompleted;

  /// No description provided for @novelDownloadPartial.
  ///
  /// In zh, this message translates to:
  /// **'正文已下载，部分插图缺失'**
  String get novelDownloadPartial;

  /// No description provided for @novelDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get novelDownloadFailed;

  /// No description provided for @novelDownloadUnauthorized.
  ///
  /// In zh, this message translates to:
  /// **'登录后重试'**
  String get novelDownloadUnauthorized;

  /// No description provided for @novelDownloadLocked.
  ///
  /// In zh, this message translates to:
  /// **'内容受限'**
  String get novelDownloadLocked;

  /// No description provided for @novelDownloadNeedsRepair.
  ///
  /// In zh, this message translates to:
  /// **'文件待修复'**
  String get novelDownloadNeedsRepair;

  /// No description provided for @novelDownloadDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{volume}」的轻小说下载吗？本地卷文件也会删除。'**
  String novelDownloadDeleteConfirm(String volume);

  /// No description provided for @downloadPauseButton.
  ///
  /// In zh, this message translates to:
  /// **'暂停下载'**
  String get downloadPauseButton;

  /// No description provided for @downloadResumeButton.
  ///
  /// In zh, this message translates to:
  /// **'继续下载'**
  String get downloadResumeButton;

  /// No description provided for @downloadQueuePause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get downloadQueuePause;

  /// No description provided for @downloadQueueResume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get downloadQueueResume;

  /// No description provided for @downloadQueueDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除下载任务'**
  String get downloadQueueDeleteTitle;

  /// No description provided for @downloadQueueDeleteContent.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{chapter}」的下载任务吗？已下载的 {count} 页文件将一并删除。'**
  String downloadQueueDeleteContent(String chapter, int count);

  /// No description provided for @downloadQueueDeleteBatchTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 {count} 个下载任务'**
  String downloadQueueDeleteBatchTitle(int count);

  /// No description provided for @downloadQueueDeleteSelectedConfirm.
  ///
  /// In zh, this message translates to:
  /// **'所选下载任务及已保存的相关文件都会被删除。'**
  String get downloadQueueDeleteSelectedConfirm;

  /// No description provided for @downloadQueueSelect.
  ///
  /// In zh, this message translates to:
  /// **'多选'**
  String get downloadQueueSelect;

  /// No description provided for @downloadQueueSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get downloadQueueSelectAll;

  /// No description provided for @downloadQueueDeselectAll.
  ///
  /// In zh, this message translates to:
  /// **'取消全选'**
  String get downloadQueueDeselectAll;

  /// No description provided for @downloadQueueFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get downloadQueueFilterAll;

  /// No description provided for @downloadQueueFilterDownloading.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get downloadQueueFilterDownloading;

  /// No description provided for @downloadQueueFilterPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get downloadQueueFilterPaused;

  /// No description provided for @downloadQueueDeleteSelected.
  ///
  /// In zh, this message translates to:
  /// **'删除所选'**
  String get downloadQueueDeleteSelected;

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

  /// No description provided for @downloadChapterPartialFailed.
  ///
  /// In zh, this message translates to:
  /// **'缺 {count} 页'**
  String downloadChapterPartialFailed(int count);

  /// No description provided for @downloadProgressPartial.
  ///
  /// In zh, this message translates to:
  /// **'{percent}% ({completed}/{total})，失败 {failed}'**
  String downloadProgressPartial(
    String percent,
    int completed,
    int total,
    int failed,
  );

  /// No description provided for @downloadBatchFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'有 {count} 章下载失败（自动重试后仍未成功）'**
  String downloadBatchFailedCount(int count);

  /// No description provided for @downloadBatchRetryAll.
  ///
  /// In zh, this message translates to:
  /// **'重试失败章节'**
  String get downloadBatchRetryAll;

  /// No description provided for @downloadBatchRequeued.
  ///
  /// In zh, this message translates to:
  /// **'已重新加入下载队列 {count} 章'**
  String downloadBatchRequeued(int count);

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
  /// **'最少已加载评论数'**
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

  /// No description provided for @commentSettingsBlockwordsSection.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽词'**
  String get commentSettingsBlockwordsSection;

  /// No description provided for @commentSettingsBlockwordsDesc.
  ///
  /// In zh, this message translates to:
  /// **'包含屏蔽词的评论将被自动过滤，大小写不敏感。'**
  String get commentSettingsBlockwordsDesc;

  /// No description provided for @commentSettingsBlockwordsHint.
  ///
  /// In zh, this message translates to:
  /// **'输入屏蔽词'**
  String get commentSettingsBlockwordsHint;

  /// No description provided for @commentSettingsClearBlockwords.
  ///
  /// In zh, this message translates to:
  /// **'清空屏蔽词'**
  String get commentSettingsClearBlockwords;

  /// No description provided for @commentSettingsBlockGroupSpam.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽群号广告'**
  String get commentSettingsBlockGroupSpam;

  /// No description provided for @commentSettingsBlockGroupSpamDesc.
  ///
  /// In zh, this message translates to:
  /// **'同时包含「群」和 8~12 位数字的评论将被自动过滤'**
  String get commentSettingsBlockGroupSpamDesc;

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

  /// No description provided for @readerChainChapterFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'加载相邻章节失败：{detail}'**
  String readerChainChapterFailedDetail(String detail);

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

  /// No description provided for @readerLoadingPrevChapter.
  ///
  /// In zh, this message translates to:
  /// **'正在加载上一话…'**
  String get readerLoadingPrevChapter;

  /// No description provided for @readerScrollUpPrevChapter.
  ///
  /// In zh, this message translates to:
  /// **'上滑加载上一话'**
  String get readerScrollUpPrevChapter;

  /// No description provided for @readerRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新本话'**
  String get readerRefresh;

  /// No description provided for @readerAlreadyFirstChapter.
  ///
  /// In zh, this message translates to:
  /// **'梦开始的地方'**
  String get readerAlreadyFirstChapter;

  /// No description provided for @readerContinuePageNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'继续翻页进入下一话'**
  String get readerContinuePageNextChapter;

  /// No description provided for @readerAlreadyLastChapter.
  ///
  /// In zh, this message translates to:
  /// **'当前已无下一话'**
  String get readerAlreadyLastChapter;

  /// No description provided for @readerContinueScrollOrTapNextChapter.
  ///
  /// In zh, this message translates to:
  /// **'继续下滑或点击按钮进入下一话'**
  String get readerContinueScrollOrTapNextChapter;

  /// No description provided for @readerImagePathCopied.
  ///
  /// In zh, this message translates to:
  /// **'图片路径已复制'**
  String get readerImagePathCopied;

  /// No description provided for @readerImageUrlCopied.
  ///
  /// In zh, this message translates to:
  /// **'图片链接已复制'**
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

  /// No description provided for @readerSaveImage.
  ///
  /// In zh, this message translates to:
  /// **'保存图片'**
  String get readerSaveImage;

  /// No description provided for @readerImageSaved.
  ///
  /// In zh, this message translates to:
  /// **'图片已保存到相册'**
  String get readerImageSaved;

  /// No description provided for @readerSaveImageFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'图片保存失败：{detail}'**
  String readerSaveImageFailedDetail(String detail);

  /// No description provided for @readerSaveImagePermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'没有相册写入权限，保存失败'**
  String get readerSaveImagePermissionDenied;

  /// No description provided for @updateAlreadyLatest.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本'**
  String get updateAlreadyLatest;

  /// No description provided for @updateNoPackageForPlatform.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂无安装包'**
  String get updateNoPackageForPlatform;

  /// No description provided for @updateOpenDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开下载链接'**
  String get updateOpenDownloadFailed;

  /// No description provided for @updateViewNotes.
  ///
  /// In zh, this message translates to:
  /// **'更新说明'**
  String get updateViewNotes;

  /// No description provided for @updateNoReleaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'暂无更新说明'**
  String get updateNoReleaseNotes;

  /// No description provided for @updateCurrentVersionNotes.
  ///
  /// In zh, this message translates to:
  /// **'当前版本'**
  String get updateCurrentVersionNotes;

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

  /// No description provided for @updateOtherPackages.
  ///
  /// In zh, this message translates to:
  /// **'其他安装包（{count}）'**
  String updateOtherPackages(int count);

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

  /// No description provided for @updateDownloadFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'下载失败：{detail}'**
  String updateDownloadFailedDetail(String detail);

  /// No description provided for @updateDownloadFallback.
  ///
  /// In zh, this message translates to:
  /// **'下载源切换中（第 {count} 个备用源）'**
  String updateDownloadFallback(int count);

  /// No description provided for @updateInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法启动安装，请改用浏览器下载'**
  String get updateInstallFailed;

  /// No description provided for @updateInstallFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'无法启动安装：{detail}'**
  String updateInstallFailedDetail(String detail);

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

  /// No description provided for @noticeRefreshFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'刷新通知失败：{detail}'**
  String noticeRefreshFailedDetail(String detail);

  /// No description provided for @noticeReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取通知失败'**
  String get noticeReadFailed;

  /// No description provided for @noticeReadFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'读取通知失败：{detail}'**
  String noticeReadFailedDetail(String detail);

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

  /// No description provided for @alreadyCollectedLabel.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get alreadyCollectedLabel;

  /// No description provided for @downloadActionButton.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get downloadActionButton;

  /// No description provided for @downloadForegroundTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在下载漫画'**
  String get downloadForegroundTitle;

  /// No description provided for @downloadForegroundChannel.
  ///
  /// In zh, this message translates to:
  /// **'漫画下载'**
  String get downloadForegroundChannel;

  /// No description provided for @downloadForegroundBody.
  ///
  /// In zh, this message translates to:
  /// **'下载中 {active} 章 · 等待 {pending} 章'**
  String downloadForegroundBody(int active, int pending);

  /// No description provided for @downloadForegroundGenericTitle.
  ///
  /// In zh, this message translates to:
  /// **'正在下载内容'**
  String get downloadForegroundGenericTitle;

  /// No description provided for @downloadForegroundGenericChannel.
  ///
  /// In zh, this message translates to:
  /// **'内容下载'**
  String get downloadForegroundGenericChannel;

  /// No description provided for @downloadForegroundGenericBody.
  ///
  /// In zh, this message translates to:
  /// **'下载中 {active} 项 · 等待 {pending} 项'**
  String downloadForegroundGenericBody(int active, int pending);

  /// No description provided for @downloadForegroundFiles.
  ///
  /// In zh, this message translates to:
  /// **'文件 {done}/{total}'**
  String downloadForegroundFiles(int done, int total);

  /// No description provided for @downloadForegroundImages.
  ///
  /// In zh, this message translates to:
  /// **'图片 {done}/{total}'**
  String downloadForegroundImages(int done, int total);

  /// No description provided for @backupTitle.
  ///
  /// In zh, this message translates to:
  /// **'备份与同步'**
  String get backupTitle;

  /// No description provided for @backupContent.
  ///
  /// In zh, this message translates to:
  /// **'备份内容'**
  String get backupContent;

  /// No description provided for @backupCategorySettings.
  ///
  /// In zh, this message translates to:
  /// **'应用设置'**
  String get backupCategorySettings;

  /// No description provided for @backupCategoryHistory.
  ///
  /// In zh, this message translates to:
  /// **'阅读历史'**
  String get backupCategoryHistory;

  /// No description provided for @backupCategoryStatistics.
  ///
  /// In zh, this message translates to:
  /// **'阅读统计'**
  String get backupCategoryStatistics;

  /// No description provided for @backupCategoryBookmarks.
  ///
  /// In zh, this message translates to:
  /// **'书签'**
  String get backupCategoryBookmarks;

  /// No description provided for @backupCategoryAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号信息'**
  String get backupCategoryAccount;

  /// No description provided for @backupCategoryAiConnection.
  ///
  /// In zh, this message translates to:
  /// **'AI 配置'**
  String get backupCategoryAiConnection;

  /// No description provided for @backupEncryption.
  ///
  /// In zh, this message translates to:
  /// **'备份文件加密'**
  String get backupEncryption;

  /// No description provided for @backupEncryptedFormat.
  ///
  /// In zh, this message translates to:
  /// **'备份文件已加密'**
  String get backupEncryptedFormat;

  /// No description provided for @backupUnencryptedFormat.
  ///
  /// In zh, this message translates to:
  /// **'备份文件未加密'**
  String get backupUnencryptedFormat;

  /// No description provided for @backupPassword.
  ///
  /// In zh, this message translates to:
  /// **'备份密码'**
  String get backupPassword;

  /// No description provided for @backupPasswordNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get backupPasswordNotSet;

  /// No description provided for @backupPasswordRemembered.
  ///
  /// In zh, this message translates to:
  /// **'已记住'**
  String get backupPasswordRemembered;

  /// No description provided for @backupPasswordSessionOnly.
  ///
  /// In zh, this message translates to:
  /// **'已设置'**
  String get backupPasswordSessionOnly;

  /// No description provided for @backupPasswordExplanation.
  ///
  /// In zh, this message translates to:
  /// **'请记好密码，旧备份仍需使用原来的密码。'**
  String get backupPasswordExplanation;

  /// No description provided for @backupConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'再次输入密码'**
  String get backupConfirmPassword;

  /// No description provided for @backupPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get backupPasswordMismatch;

  /// No description provided for @backupRememberPassword.
  ///
  /// In zh, this message translates to:
  /// **'记住密码'**
  String get backupRememberPassword;

  /// No description provided for @backupDecryptPassword.
  ///
  /// In zh, this message translates to:
  /// **'输入此备份的密码'**
  String get backupDecryptPassword;

  /// No description provided for @backupLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地文件'**
  String get backupLocal;

  /// No description provided for @backupWebDav.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV'**
  String get backupWebDav;

  /// No description provided for @backupSaveLocal.
  ///
  /// In zh, this message translates to:
  /// **'导出到文件'**
  String get backupSaveLocal;

  /// No description provided for @backupImportLocal.
  ///
  /// In zh, this message translates to:
  /// **'从文件恢复'**
  String get backupImportLocal;

  /// No description provided for @backupPreview.
  ///
  /// In zh, this message translates to:
  /// **'备份预览'**
  String get backupPreview;

  /// No description provided for @backupCategorySize.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项 · {bytes} · {percent}%'**
  String backupCategorySize(int count, String bytes, String percent);

  /// No description provided for @backupFinalSize.
  ///
  /// In zh, this message translates to:
  /// **'文件大小：{size}'**
  String backupFinalSize(String size);

  /// No description provided for @backupSensitiveWarningTitle.
  ///
  /// In zh, this message translates to:
  /// **'备份文件未加密？'**
  String get backupSensitiveWarningTitle;

  /// No description provided for @backupSensitiveWarning.
  ///
  /// In zh, this message translates to:
  /// **'这份备份包含账号或 AI 连接信息，拿到文件的人和服务器管理员都能读取其中的账号和密钥。仍要继续吗？'**
  String get backupSensitiveWarning;

  /// No description provided for @backupAcceptRisk.
  ///
  /// In zh, this message translates to:
  /// **'仍然继续'**
  String get backupAcceptRisk;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择恢复内容'**
  String get backupRestoreTitle;

  /// No description provided for @backupRestoreWarning.
  ///
  /// In zh, this message translates to:
  /// **'将覆盖所选内容，其他数据保持不变。'**
  String get backupRestoreWarning;

  /// No description provided for @backupCategoryCountSize.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项 · {bytes}'**
  String backupCategoryCountSize(int count, String bytes);

  /// No description provided for @backupLegacyWarning.
  ///
  /// In zh, this message translates to:
  /// **'已跳过 {count} 项不适用的数据。'**
  String backupLegacyWarning(int count);

  /// No description provided for @backupRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get backupRestore;

  /// No description provided for @backupRestored.
  ///
  /// In zh, this message translates to:
  /// **'恢复完成'**
  String get backupRestored;

  /// No description provided for @backupSaved.
  ///
  /// In zh, this message translates to:
  /// **'备份文件已保存'**
  String get backupSaved;

  /// No description provided for @backupUploaded.
  ///
  /// In zh, this message translates to:
  /// **'备份已上传'**
  String get backupUploaded;

  /// No description provided for @backupDeleted.
  ///
  /// In zh, this message translates to:
  /// **'远端备份已删除'**
  String get backupDeleted;

  /// No description provided for @backupWebDavConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'连接设置'**
  String get backupWebDavConfiguration;

  /// No description provided for @backupWebDavServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get backupWebDavServer;

  /// No description provided for @backupWebDavServerRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写服务器地址'**
  String get backupWebDavServerRequired;

  /// No description provided for @backupWebDavPresetTitle.
  ///
  /// In zh, this message translates to:
  /// **'常用服务器'**
  String get backupWebDavPresetTitle;

  /// No description provided for @backupWebDavPresetJianguoyun.
  ///
  /// In zh, this message translates to:
  /// **'坚果云'**
  String get backupWebDavPresetJianguoyun;

  /// No description provided for @backupWebDavDirectory.
  ///
  /// In zh, this message translates to:
  /// **'备份文件夹（可选）'**
  String get backupWebDavDirectory;

  /// No description provided for @backupWebDavDirectoryHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则保存到服务器根目录'**
  String get backupWebDavDirectoryHint;

  /// No description provided for @backupWebDavUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get backupWebDavUsername;

  /// No description provided for @backupWebDavUsernameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写用户名'**
  String get backupWebDavUsernameRequired;

  /// No description provided for @backupWebDavPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get backupWebDavPassword;

  /// No description provided for @backupWebDavPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写密码'**
  String get backupWebDavPasswordRequired;

  /// No description provided for @backupSaveConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get backupSaveConfiguration;

  /// No description provided for @backupWebDavNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未设置服务器'**
  String get backupWebDavNotConfigured;

  /// No description provided for @backupWebDavDisabledHint.
  ///
  /// In zh, this message translates to:
  /// **'开启后可配置服务器、定时备份与远端备份列表。'**
  String get backupWebDavDisabledHint;

  /// No description provided for @backupWebDavDisabledHintSaved.
  ///
  /// In zh, this message translates to:
  /// **'已关闭：不会上传备份，已保存的连接信息仍会保留。'**
  String get backupWebDavDisabledHintSaved;

  /// No description provided for @backupWebDavCleared.
  ///
  /// In zh, this message translates to:
  /// **'连接设置已清除'**
  String get backupWebDavCleared;

  /// No description provided for @backupSchedule.
  ///
  /// In zh, this message translates to:
  /// **'定时备份'**
  String get backupSchedule;

  /// No description provided for @backupSchedulePasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先设置备份密码'**
  String get backupSchedulePasswordRequired;

  /// No description provided for @backupScheduleInterval.
  ///
  /// In zh, this message translates to:
  /// **'备份间隔'**
  String get backupScheduleInterval;

  /// No description provided for @backupScheduleMinutes.
  ///
  /// In zh, this message translates to:
  /// **'分钟'**
  String get backupScheduleMinutes;

  /// No description provided for @backupScheduleHours.
  ///
  /// In zh, this message translates to:
  /// **'小时'**
  String get backupScheduleHours;

  /// No description provided for @backupScheduleDays.
  ///
  /// In zh, this message translates to:
  /// **'天'**
  String get backupScheduleDays;

  /// No description provided for @backupTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get backupTestConnection;

  /// No description provided for @backupTestSucceeded.
  ///
  /// In zh, this message translates to:
  /// **'连接正常'**
  String get backupTestSucceeded;

  /// No description provided for @backupUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get backupUpload;

  /// No description provided for @backupNoRemoteFiles.
  ///
  /// In zh, this message translates to:
  /// **'暂无备份'**
  String get backupNoRemoteFiles;

  /// No description provided for @backupRemoteFilesHint.
  ///
  /// In zh, this message translates to:
  /// **'刷新以查看备份'**
  String get backupRemoteFilesHint;

  /// No description provided for @backupDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除远端备份？'**
  String get backupDeleteTitle;

  /// No description provided for @backupDeleteWarning.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？删除后无法找回。'**
  String backupDeleteWarning(String name);

  /// No description provided for @backupHttpWarningTitle.
  ///
  /// In zh, this message translates to:
  /// **'继续使用此地址？'**
  String get backupHttpWarningTitle;

  /// No description provided for @backupHttpWarning.
  ///
  /// In zh, this message translates to:
  /// **'此连接无法保护你的账号和密码，仍要继续吗？'**
  String get backupHttpWarning;

  /// No description provided for @backupReading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取…'**
  String get backupReading;

  /// No description provided for @backupCompressing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备备份…'**
  String get backupCompressing;

  /// No description provided for @backupEncrypting.
  ///
  /// In zh, this message translates to:
  /// **'正在加密备份…'**
  String get backupEncrypting;

  /// No description provided for @backupDecoding.
  ///
  /// In zh, this message translates to:
  /// **'正在读取备份…'**
  String get backupDecoding;

  /// No description provided for @backupTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在测试连接…'**
  String get backupTesting;

  /// No description provided for @backupListing.
  ///
  /// In zh, this message translates to:
  /// **'正在读取备份列表…'**
  String get backupListing;

  /// No description provided for @backupUploading.
  ///
  /// In zh, this message translates to:
  /// **'正在上传…'**
  String get backupUploading;

  /// No description provided for @backupDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载…'**
  String get backupDownloading;

  /// No description provided for @backupRestoring.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复，请勿关闭应用…'**
  String get backupRestoring;

  /// No description provided for @backupDeleting.
  ///
  /// In zh, this message translates to:
  /// **'正在删除…'**
  String get backupDeleting;

  /// No description provided for @backupCancelling.
  ///
  /// In zh, this message translates to:
  /// **'正在取消…'**
  String get backupCancelling;

  /// No description provided for @backupCancelled.
  ///
  /// In zh, this message translates to:
  /// **'操作已取消'**
  String get backupCancelled;

  /// No description provided for @backupTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'备份文件不得超过 16 MiB，解压内容不得超过 64 MiB。'**
  String get backupTooLarge;

  /// No description provided for @backupPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入备份密码'**
  String get backupPasswordRequired;

  /// No description provided for @backupAuthenticationFailed.
  ///
  /// In zh, this message translates to:
  /// **'密码不正确，或文件已损坏。'**
  String get backupAuthenticationFailed;

  /// No description provided for @backupInvalidEncryptionParameters.
  ///
  /// In zh, this message translates to:
  /// **'无法读取这份备份，请检查文件是否完整。'**
  String get backupInvalidEncryptionParameters;

  /// No description provided for @backupSelectCategory.
  ///
  /// In zh, this message translates to:
  /// **'请选择要备份或恢复的内容'**
  String get backupSelectCategory;

  /// No description provided for @backupBusy.
  ///
  /// In zh, this message translates to:
  /// **'已有备份操作正在进行'**
  String get backupBusy;

  /// No description provided for @backupWriteFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败，已还原原有数据。请检查可用空间后重试。'**
  String get backupWriteFailed;

  /// No description provided for @backupRecoveryRequired.
  ///
  /// In zh, this message translates to:
  /// **'数据恢复尚未完成。请解锁设备、检查可用空间后重试。'**
  String get backupRecoveryRequired;

  /// No description provided for @backupRecoveryTitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复本机数据'**
  String get backupRecoveryTitle;

  /// No description provided for @backupOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败，请检查文件权限和可用空间后重试。'**
  String get backupOperationFailed;

  /// No description provided for @backupOperationFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{detail}'**
  String backupOperationFailedDetail(String detail);

  /// No description provided for @backupWebDavInvalidConfig.
  ///
  /// In zh, this message translates to:
  /// **'请检查服务器地址、用户名和文件夹路径。'**
  String get backupWebDavInvalidConfig;

  /// No description provided for @backupWebDavAuthentication.
  ///
  /// In zh, this message translates to:
  /// **'登录失败，请检查用户名和密码。'**
  String get backupWebDavAuthentication;

  /// No description provided for @backupWebDavForbidden.
  ///
  /// In zh, this message translates to:
  /// **'没有操作权限，请检查服务器设置。'**
  String get backupWebDavForbidden;

  /// No description provided for @backupWebDavNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到备份，请刷新后重试。'**
  String get backupWebDavNotFound;

  /// No description provided for @backupWebDavMoveUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'此服务器暂不支持备份上传，请更换服务器。'**
  String get backupWebDavMoveUnsupported;

  /// No description provided for @backupWebDavMethodUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'此地址无法用于备份，请检查服务器设置。'**
  String get backupWebDavMethodUnsupported;

  /// No description provided for @backupWebDavRedirectRefused.
  ///
  /// In zh, this message translates to:
  /// **'连接地址已变更，请填写新的服务器地址。'**
  String get backupWebDavRedirectRefused;

  /// No description provided for @backupWebDavUnsafePath.
  ///
  /// In zh, this message translates to:
  /// **'无法访问这份备份，请检查文件夹设置。'**
  String get backupWebDavUnsafePath;

  /// No description provided for @backupWebDavInvalidResponse.
  ///
  /// In zh, this message translates to:
  /// **'无法读取服务器上的备份，请检查连接设置。'**
  String get backupWebDavInvalidResponse;

  /// No description provided for @backupWebDavConnection.
  ///
  /// In zh, this message translates to:
  /// **'无法连接服务器，请检查网络和连接设置。'**
  String get backupWebDavConnection;

  /// No description provided for @backupWebDavTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接超时，请重试。'**
  String get backupWebDavTimeout;

  /// No description provided for @backupWebDavConflict.
  ///
  /// In zh, this message translates to:
  /// **'无法保存到此文件夹，原有备份未被覆盖。'**
  String get backupWebDavConflict;

  /// No description provided for @backupPreviewContents.
  ///
  /// In zh, this message translates to:
  /// **'内容占比（压缩前）'**
  String get backupPreviewContents;

  /// No description provided for @backupEmptyCategory.
  ///
  /// In zh, this message translates to:
  /// **'没有内容，恢复后将清空'**
  String get backupEmptyCategory;

  /// No description provided for @novelBookshelf.
  ///
  /// In zh, this message translates to:
  /// **'小说书架'**
  String get novelBookshelf;

  /// No description provided for @novelSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索轻小说'**
  String get novelSearchHint;

  /// No description provided for @novelSearchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有找到相关轻小说，换个关键词试试'**
  String get novelSearchEmpty;

  /// No description provided for @novelSearchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败，请重试'**
  String get novelSearchFailed;

  /// No description provided for @continueReadingComic.
  ///
  /// In zh, this message translates to:
  /// **'继续阅读漫画'**
  String get continueReadingComic;

  /// No description provided for @continueReadingNovel.
  ///
  /// In zh, this message translates to:
  /// **'继续阅读轻小说'**
  String get continueReadingNovel;

  /// No description provided for @historyTabComic.
  ///
  /// In zh, this message translates to:
  /// **'漫画'**
  String get historyTabComic;

  /// No description provided for @historyTabNovel.
  ///
  /// In zh, this message translates to:
  /// **'轻小说'**
  String get historyTabNovel;

  /// No description provided for @novelHistory.
  ///
  /// In zh, this message translates to:
  /// **'阅读记录'**
  String get novelHistory;

  /// No description provided for @novelCopyLoginRequired.
  ///
  /// In zh, this message translates to:
  /// **'登录拷贝账户后查看书架、收藏'**
  String get novelCopyLoginRequired;

  /// No description provided for @novelCopyLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录拷贝账户'**
  String get novelCopyLogin;

  /// No description provided for @novelContinueReading.
  ///
  /// In zh, this message translates to:
  /// **'继续阅读'**
  String get novelContinueReading;

  /// No description provided for @novelStartReading.
  ///
  /// In zh, this message translates to:
  /// **'开始阅读'**
  String get novelStartReading;

  /// No description provided for @novelAllThemes.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get novelAllThemes;

  /// No description provided for @novelThemes.
  ///
  /// In zh, this message translates to:
  /// **'题材'**
  String get novelThemes;

  /// No description provided for @novelEmptyBooks.
  ///
  /// In zh, this message translates to:
  /// **'暂无书籍，试试其他题材'**
  String get novelEmptyBooks;

  /// No description provided for @novelLoadMoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败，点击重试'**
  String get novelLoadMoreFailed;

  /// No description provided for @novelLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'书籍加载失败'**
  String get novelLoadFailed;

  /// No description provided for @novelThemesFailed.
  ///
  /// In zh, this message translates to:
  /// **'题材加载失败'**
  String get novelThemesFailed;

  /// No description provided for @novelVolumes.
  ///
  /// In zh, this message translates to:
  /// **'分卷目录'**
  String get novelVolumes;

  /// No description provided for @novelNoVolumes.
  ///
  /// In zh, this message translates to:
  /// **'暂无可阅读的分卷'**
  String get novelNoVolumes;

  /// No description provided for @novelVolumesFailed.
  ///
  /// In zh, this message translates to:
  /// **'目录加载失败'**
  String get novelVolumesFailed;

  /// No description provided for @novelLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'轻小说本地'**
  String get novelLocalTitle;

  /// No description provided for @novelNoLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有本地轻小说'**
  String get novelNoLocalTitle;

  /// No description provided for @novelNoLocalSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'去轻小说详情页下载分卷后，这里会显示离线内容'**
  String get novelNoLocalSubtitle;

  /// No description provided for @novelDeleteLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除本地轻小说'**
  String get novelDeleteLocalTitle;

  /// No description provided for @novelDeleteLocalContent.
  ///
  /// In zh, this message translates to:
  /// **'确定删除选中的 {count} 部本地轻小说吗？已下载分卷和封面都会被删除。'**
  String novelDeleteLocalContent(int count);

  /// No description provided for @novelLocalVolumesTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地分卷 ({count})'**
  String novelLocalVolumesTitle(int count);

  /// No description provided for @novelDeleteLocalVolumesTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除本地分卷'**
  String get novelDeleteLocalVolumesTitle;

  /// No description provided for @novelDeleteLocalVolumesContent.
  ///
  /// In zh, this message translates to:
  /// **'确定删除选中的 {count} 卷吗？对应的正文与插图都会被删除。'**
  String novelDeleteLocalVolumesContent(int count);

  /// No description provided for @novelDeletedVolumesToast.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 卷'**
  String novelDeletedVolumesToast(int count);

  /// No description provided for @novelManageVolumes.
  ///
  /// In zh, this message translates to:
  /// **'管理分卷'**
  String get novelManageVolumes;

  /// No description provided for @novelVolumeUnit.
  ///
  /// In zh, this message translates to:
  /// **'卷'**
  String get novelVolumeUnit;

  /// No description provided for @novelDeleteToastSuffix.
  ///
  /// In zh, this message translates to:
  /// **' 部本地轻小说'**
  String get novelDeleteToastSuffix;

  /// No description provided for @novelNoBrief.
  ///
  /// In zh, this message translates to:
  /// **'暂无简介'**
  String get novelNoBrief;

  /// No description provided for @novelUncollect.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get novelUncollect;

  /// No description provided for @novelCollectFailed.
  ///
  /// In zh, this message translates to:
  /// **'收藏操作失败，请重试'**
  String get novelCollectFailed;

  /// No description provided for @novelCollectFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'收藏操作失败：{detail}'**
  String novelCollectFailedDetail(String detail);

  /// No description provided for @novelDownloadEnqueueFailed.
  ///
  /// In zh, this message translates to:
  /// **'加入下载失败：{detail}'**
  String novelDownloadEnqueueFailed(String detail);

  /// No description provided for @novelQueryFailed.
  ///
  /// In zh, this message translates to:
  /// **'阅读与收藏状态加载失败'**
  String get novelQueryFailed;

  /// No description provided for @novelEmptyShelf.
  ///
  /// In zh, this message translates to:
  /// **'书架还是空的，去发现喜欢的小说吧'**
  String get novelEmptyShelf;

  /// No description provided for @novelEmptyHistory.
  ///
  /// In zh, this message translates to:
  /// **'开始阅读后，进度会保存在这里'**
  String get novelEmptyHistory;

  /// No description provided for @novelHistoryFailed.
  ///
  /// In zh, this message translates to:
  /// **'阅读记录加载失败'**
  String get novelHistoryFailed;

  /// No description provided for @novelClearHistory.
  ///
  /// In zh, this message translates to:
  /// **'清空阅读记录'**
  String get novelClearHistory;

  /// No description provided for @novelRemoveHistory.
  ///
  /// In zh, this message translates to:
  /// **'移除阅读记录'**
  String get novelRemoveHistory;

  /// No description provided for @novelHistoryDeleteFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'移除失败：{detail}'**
  String novelHistoryDeleteFailedDetail(String detail);

  /// No description provided for @novelBookDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看详情'**
  String get novelBookDetails;

  /// No description provided for @novelNoComments.
  ///
  /// In zh, this message translates to:
  /// **'暂无评论'**
  String get novelNoComments;

  /// No description provided for @novelCommentsFailed.
  ///
  /// In zh, this message translates to:
  /// **'评论加载失败'**
  String get novelCommentsFailed;

  /// No description provided for @novelCommentsClosed.
  ///
  /// In zh, this message translates to:
  /// **'本书已关闭评论'**
  String get novelCommentsClosed;

  /// No description provided for @novelWriteComment.
  ///
  /// In zh, this message translates to:
  /// **'写下你的评论'**
  String get novelWriteComment;

  /// No description provided for @novelPostComment.
  ///
  /// In zh, this message translates to:
  /// **'发表评论'**
  String get novelPostComment;

  /// No description provided for @novelCommentPosted.
  ///
  /// In zh, this message translates to:
  /// **'评论已发表'**
  String get novelCommentPosted;

  /// No description provided for @novelCommentFailed.
  ///
  /// In zh, this message translates to:
  /// **'发表失败，内容已保留，请重试'**
  String get novelCommentFailed;

  /// No description provided for @novelReply.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get novelReply;

  /// No description provided for @novelReplyTitle.
  ///
  /// In zh, this message translates to:
  /// **'评论回复'**
  String get novelReplyTitle;

  /// No description provided for @novelCommentCollapseReplies.
  ///
  /// In zh, this message translates to:
  /// **'收起回复'**
  String get novelCommentCollapseReplies;

  /// No description provided for @novelCommentExpandReplies.
  ///
  /// In zh, this message translates to:
  /// **'展开 {count} 条回复'**
  String novelCommentExpandReplies(Object count);

  /// No description provided for @novelCommentReplyLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'回复加载失败'**
  String get novelCommentReplyLoadFailed;

  /// No description provided for @novelCommentRetryLoadMoreReplies.
  ///
  /// In zh, this message translates to:
  /// **'重试加载更多回复'**
  String get novelCommentRetryLoadMoreReplies;

  /// No description provided for @novelCommentEmptyReplies.
  ///
  /// In zh, this message translates to:
  /// **'暂无可显示的回复'**
  String get novelCommentEmptyReplies;

  /// No description provided for @novelCommentLoadMoreReplies.
  ///
  /// In zh, this message translates to:
  /// **'加载更多回复 ({loaded}/{total})'**
  String novelCommentLoadMoreReplies(Object loaded, Object total);

  /// No description provided for @novelCommentReplyTitle.
  ///
  /// In zh, this message translates to:
  /// **'回复 {userName}'**
  String novelCommentReplyTitle(Object userName);

  /// No description provided for @novelCommentReplyHint.
  ///
  /// In zh, this message translates to:
  /// **'回复 {userName}…'**
  String novelCommentReplyHint(Object userName);

  /// No description provided for @novelSerializing.
  ///
  /// In zh, this message translates to:
  /// **'连载中'**
  String get novelSerializing;

  /// No description provided for @novelCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完结'**
  String get novelCompleted;

  /// No description provided for @novelReaderTitle.
  ///
  /// In zh, this message translates to:
  /// **'轻小说阅读器'**
  String get novelReaderTitle;

  /// No description provided for @novelReaderBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get novelReaderBack;

  /// No description provided for @novelReaderShowToolbar.
  ///
  /// In zh, this message translates to:
  /// **'展开工具栏'**
  String get novelReaderShowToolbar;

  /// No description provided for @novelReaderContents.
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get novelReaderContents;

  /// No description provided for @novelReaderCatalog.
  ///
  /// In zh, this message translates to:
  /// **'总目录'**
  String get novelReaderCatalog;

  /// No description provided for @novelReaderVolume.
  ///
  /// In zh, this message translates to:
  /// **'卷册'**
  String get novelReaderVolume;

  /// No description provided for @novelReaderBookmark.
  ///
  /// In zh, this message translates to:
  /// **'书签'**
  String get novelReaderBookmark;

  /// No description provided for @novelReaderVolumesRetry.
  ///
  /// In zh, this message translates to:
  /// **'卷册加载失败，重试'**
  String get novelReaderVolumesRetry;

  /// No description provided for @novelReaderVolumesRetryDetail.
  ///
  /// In zh, this message translates to:
  /// **'卷册加载失败：{detail}（点击重试）'**
  String novelReaderVolumesRetryDetail(String detail);

  /// No description provided for @novelReaderPrevious.
  ///
  /// In zh, this message translates to:
  /// **'上一卷'**
  String get novelReaderPrevious;

  /// No description provided for @novelReaderNext.
  ///
  /// In zh, this message translates to:
  /// **'下一卷'**
  String get novelReaderNext;

  /// No description provided for @novelReaderSettings.
  ///
  /// In zh, this message translates to:
  /// **'阅读设置'**
  String get novelReaderSettings;

  /// No description provided for @novelReaderRealisticPageTurn.
  ///
  /// In zh, this message translates to:
  /// **'仿真翻页'**
  String get novelReaderRealisticPageTurn;

  /// No description provided for @novelReaderFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get novelReaderFontSize;

  /// No description provided for @novelReaderLineHeight.
  ///
  /// In zh, this message translates to:
  /// **'行距'**
  String get novelReaderLineHeight;

  /// No description provided for @novelReaderParagraphSpacing.
  ///
  /// In zh, this message translates to:
  /// **'段距'**
  String get novelReaderParagraphSpacing;

  /// No description provided for @novelReaderContentWidth.
  ///
  /// In zh, this message translates to:
  /// **'正文宽度'**
  String get novelReaderContentWidth;

  /// No description provided for @novelReaderTheme.
  ///
  /// In zh, this message translates to:
  /// **'阅读主题'**
  String get novelReaderTheme;

  /// No description provided for @novelReaderFontFamily.
  ///
  /// In zh, this message translates to:
  /// **'正文字体'**
  String get novelReaderFontFamily;

  /// No description provided for @novelReaderFontFollowApp.
  ///
  /// In zh, this message translates to:
  /// **'跟随应用字体'**
  String get novelReaderFontFollowApp;

  /// No description provided for @novelReaderFontUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'{name}（不可用）'**
  String novelReaderFontUnavailable(String name);

  /// No description provided for @novelReaderThemePaper.
  ///
  /// In zh, this message translates to:
  /// **'纸张'**
  String get novelReaderThemePaper;

  /// No description provided for @novelReaderThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'夜间'**
  String get novelReaderThemeDark;

  /// No description provided for @novelReaderThemeWhite.
  ///
  /// In zh, this message translates to:
  /// **'白底'**
  String get novelReaderThemeWhite;

  /// No description provided for @novelReaderThemeGreen.
  ///
  /// In zh, this message translates to:
  /// **'护眼绿'**
  String get novelReaderThemeGreen;

  /// No description provided for @novelReaderThemeGray.
  ///
  /// In zh, this message translates to:
  /// **'灰'**
  String get novelReaderThemeGray;

  /// No description provided for @novelReaderThemeCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义主题'**
  String get novelReaderThemeCustom;

  /// No description provided for @novelReaderThemeLightMode.
  ///
  /// In zh, this message translates to:
  /// **'浅色模式'**
  String get novelReaderThemeLightMode;

  /// No description provided for @novelReaderThemeDarkMode.
  ///
  /// In zh, this message translates to:
  /// **'深色模式'**
  String get novelReaderThemeDarkMode;

  /// No description provided for @novelReaderThemeAdd.
  ///
  /// In zh, this message translates to:
  /// **'新建配色方案'**
  String get novelReaderThemeAdd;

  /// No description provided for @novelReaderThemeNameTitle.
  ///
  /// In zh, this message translates to:
  /// **'方案名称'**
  String get novelReaderThemeNameTitle;

  /// No description provided for @novelReaderThemeEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑「{name}」'**
  String novelReaderThemeEditTitle(String name);

  /// No description provided for @novelReaderThemeEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑方案'**
  String get novelReaderThemeEdit;

  /// No description provided for @novelReaderThemeDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除配色方案'**
  String get novelReaderThemeDeleteTitle;

  /// No description provided for @novelReaderThemeDeleteContent.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？绑定它的模式会回退到默认方案。'**
  String novelReaderThemeDeleteContent(String name);

  /// No description provided for @novelReaderBackgroundColor.
  ///
  /// In zh, this message translates to:
  /// **'背景颜色'**
  String get novelReaderBackgroundColor;

  /// No description provided for @novelReaderTextColor.
  ///
  /// In zh, this message translates to:
  /// **'文字颜色'**
  String get novelReaderTextColor;

  /// No description provided for @novelReaderPreviewText.
  ///
  /// In zh, this message translates to:
  /// **'夜色温柔，街灯次第亮起，故事从这一页开始。'**
  String get novelReaderPreviewText;

  /// No description provided for @novelReaderColorScheme.
  ///
  /// In zh, this message translates to:
  /// **'配色方案'**
  String get novelReaderColorScheme;

  /// No description provided for @novelReaderDialogueStyle.
  ///
  /// In zh, this message translates to:
  /// **'对白样式'**
  String get novelReaderDialogueStyle;

  /// No description provided for @novelReaderDialogueAutomatic.
  ///
  /// In zh, this message translates to:
  /// **'自动适配'**
  String get novelReaderDialogueAutomatic;

  /// No description provided for @novelReaderDialogueFollowBody.
  ///
  /// In zh, this message translates to:
  /// **'跟随正文'**
  String get novelReaderDialogueFollowBody;

  /// No description provided for @novelReaderDialogueCustom.
  ///
  /// In zh, this message translates to:
  /// **'自选颜色'**
  String get novelReaderDialogueCustom;

  /// No description provided for @novelReaderDialogueWeight.
  ///
  /// In zh, this message translates to:
  /// **'字重'**
  String get novelReaderDialogueWeight;

  /// No description provided for @novelReaderDialogueMedium.
  ///
  /// In zh, this message translates to:
  /// **'中等'**
  String get novelReaderDialogueMedium;

  /// No description provided for @novelReaderDialogueBold.
  ///
  /// In zh, this message translates to:
  /// **'加粗'**
  String get novelReaderDialogueBold;

  /// No description provided for @novelReaderDialogueBackground.
  ///
  /// In zh, this message translates to:
  /// **'对白底色'**
  String get novelReaderDialogueBackground;

  /// No description provided for @novelReaderDialogueBackgroundStrength.
  ///
  /// In zh, this message translates to:
  /// **'底色强度'**
  String get novelReaderDialogueBackgroundStrength;

  /// No description provided for @novelReaderDialogueLowContrast.
  ///
  /// In zh, this message translates to:
  /// **'对白与背景对比度较低'**
  String get novelReaderDialogueLowContrast;

  /// No description provided for @novelReaderDialoguePreviewText.
  ///
  /// In zh, this message translates to:
  /// **'夜色温柔，她翻开书页，窗外的风轻轻吹动帘角。\n「故事里还有『未说完的话』，我们继续吧。」\n街灯亮起，远处传来列车经过的声音，像一段熟悉的旋律。\n『等到天亮，我们就一起出发。』\n「如果路上迷失方向，\n就记住窗边这盏灯，我会在这里等你回来。」\n她合上书，笑着望向窗外。她说：「这一句尚未结束……'**
  String get novelReaderDialoguePreviewText;

  /// No description provided for @novelReaderKeepScreenOn.
  ///
  /// In zh, this message translates to:
  /// **'阅读时屏幕常亮'**
  String get novelReaderKeepScreenOn;

  /// No description provided for @novelReaderIgnoreBlankParagraphs.
  ///
  /// In zh, this message translates to:
  /// **'隐藏空白段落'**
  String get novelReaderIgnoreBlankParagraphs;

  /// No description provided for @novelReaderIgnoreBlankParagraphsDenseHint.
  ///
  /// In zh, this message translates to:
  /// **'可以适当增大段距以免文字过于密集'**
  String get novelReaderIgnoreBlankParagraphsDenseHint;

  /// No description provided for @novelReaderFocusMode.
  ///
  /// In zh, this message translates to:
  /// **'专注模式'**
  String get novelReaderFocusMode;

  /// No description provided for @novelReaderFocusKeepStatusVisible.
  ///
  /// In zh, this message translates to:
  /// **'不遮挡状态组件'**
  String get novelReaderFocusKeepStatusVisible;

  /// No description provided for @novelReaderFocusTopBound.
  ///
  /// In zh, this message translates to:
  /// **'上边界'**
  String get novelReaderFocusTopBound;

  /// No description provided for @novelReaderFocusBottomBound.
  ///
  /// In zh, this message translates to:
  /// **'下边界'**
  String get novelReaderFocusBottomBound;

  /// No description provided for @novelReaderFocusOpacity.
  ///
  /// In zh, this message translates to:
  /// **'遮罩浓度'**
  String get novelReaderFocusOpacity;

  /// No description provided for @novelReaderIllustration.
  ///
  /// In zh, this message translates to:
  /// **'插图'**
  String get novelReaderIllustration;

  /// No description provided for @novelReaderImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'插图加载失败'**
  String get novelReaderImageFailed;

  /// No description provided for @novelReaderEmptyChapter.
  ///
  /// In zh, this message translates to:
  /// **'本章节暂无正文'**
  String get novelReaderEmptyChapter;

  /// No description provided for @novelReaderEmptyVolume.
  ///
  /// In zh, this message translates to:
  /// **'本卷暂无可阅读的正文'**
  String get novelReaderEmptyVolume;

  /// No description provided for @novelReaderLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'正文加载失败，请重试或打开本地缓存'**
  String get novelReaderLoadFailed;

  /// No description provided for @novelReaderLocked.
  ///
  /// In zh, this message translates to:
  /// **'本卷暂不可访问，请确认拷贝账号的阅读权限'**
  String get novelReaderLocked;

  /// No description provided for @novelReaderLoginRequired.
  ///
  /// In zh, this message translates to:
  /// **'请登录拷贝账号后重试'**
  String get novelReaderLoginRequired;

  /// No description provided for @novelReaderCopyLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录拷贝账号'**
  String get novelReaderCopyLogin;

  /// No description provided for @novelReaderOpenCache.
  ///
  /// In zh, this message translates to:
  /// **'打开本地缓存'**
  String get novelReaderOpenCache;

  /// No description provided for @novelReaderNoCache.
  ///
  /// In zh, this message translates to:
  /// **'本卷没有可用的本地缓存'**
  String get novelReaderNoCache;

  /// No description provided for @novelReaderUnnamedChapter.
  ///
  /// In zh, this message translates to:
  /// **'章节 {number}'**
  String novelReaderUnnamedChapter(int number);

  /// No description provided for @copyAccountLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录拷贝账号'**
  String get copyAccountLoginTitle;

  /// No description provided for @copyAccountIndependentHint.
  ///
  /// In zh, this message translates to:
  /// **'仅用于拷贝轻小说。登录、切换或退出此账号都不会改变当前主账号。'**
  String get copyAccountIndependentHint;

  /// No description provided for @copyAccountStorageFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存拷贝账号，请稍后重试；原账号保持不变。'**
  String get copyAccountStorageFailed;

  /// No description provided for @copyAccountLoginSuperseded.
  ///
  /// In zh, this message translates to:
  /// **'账号状态已改变，本次登录已取消，请重试。'**
  String get copyAccountLoginSuperseded;

  /// No description provided for @accountCenterTitle.
  ///
  /// In zh, this message translates to:
  /// **'账号中心'**
  String get accountCenterTitle;

  /// No description provided for @accountCenterActiveLabel.
  ///
  /// In zh, this message translates to:
  /// **'使用中的账号'**
  String get accountCenterActiveLabel;

  /// No description provided for @accountCenterSavedLabel.
  ///
  /// In zh, this message translates to:
  /// **'登录过的账号'**
  String get accountCenterSavedLabel;

  /// No description provided for @accountCenterComicAccount.
  ///
  /// In zh, this message translates to:
  /// **'漫画账号'**
  String get accountCenterComicAccount;

  /// No description provided for @accountCenterNovelAccount.
  ///
  /// In zh, this message translates to:
  /// **'轻小说账号'**
  String get accountCenterNovelAccount;

  /// No description provided for @accountCenterNovelCopyOnlyHint.
  ///
  /// In zh, this message translates to:
  /// **'轻小说仅支持使用拷贝账号'**
  String get accountCenterNovelCopyOnlyHint;

  /// No description provided for @accountCenterNotLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get accountCenterNotLoggedIn;

  /// No description provided for @accountProfileMissing.
  ///
  /// In zh, this message translates to:
  /// **'已登录（未获取资料）'**
  String get accountProfileMissing;

  /// No description provided for @accountCenterRemoveConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定移除「{name}」吗？仅删除本机保存的登录状态。'**
  String accountCenterRemoveConfirm(String name);

  /// No description provided for @accountCenterNovelBoundToast.
  ///
  /// In zh, this message translates to:
  /// **'轻小说已切换到 {name}'**
  String accountCenterNovelBoundToast(String name);

  /// No description provided for @accountViewTitle.
  ///
  /// In zh, this message translates to:
  /// **'查看账号'**
  String get accountViewTitle;

  /// No description provided for @accountViewUsernameLabel.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get accountViewUsernameLabel;

  /// No description provided for @accountViewPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get accountViewPasswordLabel;

  /// No description provided for @accountViewPasswordUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'未保存密码（该账号未勾选「记住账号」或使用令牌登录）'**
  String get accountViewPasswordUnavailable;

  /// No description provided for @accountViewTokenLabel.
  ///
  /// In zh, this message translates to:
  /// **'令牌 (Token)'**
  String get accountViewTokenLabel;

  /// No description provided for @accountViewCopiedToast.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get accountViewCopiedToast;
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
