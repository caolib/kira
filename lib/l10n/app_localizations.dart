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
