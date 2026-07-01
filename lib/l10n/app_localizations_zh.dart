// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Kira';

  @override
  String get comicTabLabel => '漫画';

  @override
  String get animeTabLabel => '动漫';

  @override
  String get searchTabLabel => '搜索';

  @override
  String get bookshelfTabLabel => '书架';

  @override
  String get profileTabLabel => '我的';

  @override
  String get disclaimerTitle => '免责声明';

  @override
  String get disclaimerAgreeNote =>
      '继续使用本应用，即表示您已阅读、理解并同意上述说明；如您不同意，请立即停止使用并退出本应用。';

  @override
  String get disagreeAndExit => '不同意并退出';

  @override
  String get confirmButton => '确认';

  @override
  String get cancelButton => '取消';

  @override
  String get deleteButton => '删除';

  @override
  String get loadingFailed => '加载失败';

  @override
  String get retryButton => '重试';

  @override
  String get noContent => '暂无内容';

  @override
  String get hotRecommend => '热门推荐';

  @override
  String get comicRanking => '漫画排行';

  @override
  String get moreButton => '更多';

  @override
  String get dayRank => '日榜';

  @override
  String get weekRank => '周榜';

  @override
  String get monthRank => '月榜';

  @override
  String get copyRecommend => '推荐';

  @override
  String get copyRanking => '排行榜';

  @override
  String get copyHotUpdate => '热门更新';

  @override
  String get copyNewArrival => '全新上架';

  @override
  String get copyFinished => '已完结';

  @override
  String get switchToHotHome => '切换到 HOT 首页';

  @override
  String get switchToCopyHome => '切换到 COPY 首页';

  @override
  String get localComicsTitle => '本地漫画';

  @override
  String get noLocalComicsTitle => '还没有本地漫画';

  @override
  String get noLocalComicsSubtitle => '去漫画详情页下载章节后，这里会显示离线内容';

  @override
  String get deleteLocalComicsTitle => '删除本地漫画';

  @override
  String deleteLocalComicsContent(int count) {
    return '确定删除选中的 $count 部本地漫画吗？已下载章节和封面都会被删除。';
  }

  @override
  String deletedLocalComicsCount(int count) {
    return '已删除 $count 部本地漫画';
  }

  @override
  String get localAnimeTitle => '本地动漫';

  @override
  String get noLocalAnimeTitle => '还没有本地动漫';

  @override
  String get noLocalAnimeSubtitle => '去动漫详情页下载剧集后，这里会显示离线内容';

  @override
  String get deleteLocalAnimeTitle => '删除本地动漫';

  @override
  String deleteLocalAnimeContent(int count) {
    return '确定删除选中的 $count 部本地动漫吗？已下载视频和封面都会被删除。';
  }

  @override
  String deletedLocalAnimeCount(int count) {
    return '已删除 $count 部本地动漫';
  }

  @override
  String selectedCount(int count, String unit) {
    return '已选 $count $unit';
  }

  @override
  String selectedItems(int count) {
    return '已选 $count 部';
  }

  @override
  String downloadedChapterCount(int count) {
    return '已下载 $count 章';
  }

  @override
  String downloadedEpisodeCount(int count) {
    return '已下载 $count 集';
  }

  @override
  String downloadedCountUnit(int count, String unit) {
    return '已下载 $count $unit';
  }

  @override
  String localChaptersTitle(int count) {
    return '本地章节 ($count)';
  }

  @override
  String localEpisodesTitle(int count) {
    return '本地剧集 ($count)';
  }

  @override
  String get deleteLocalChaptersTitle => '删除本地章节';

  @override
  String deleteChaptersConfirm(int count) {
    return '确定删除选中的 $count 个章节吗？';
  }

  @override
  String deletedChaptersCount(int count) {
    return '已删除 $count 个章节';
  }

  @override
  String get deleteLocalEpisodesTitle => '删除本地剧集';

  @override
  String deleteEpisodesConfirm(int count) {
    return '确定删除选中的 $count 个剧集吗？';
  }

  @override
  String deletedEpisodesCount(int count) {
    return '已删除 $count 个剧集';
  }

  @override
  String get viewOnlineDetail => '查看在线详情';

  @override
  String get manageChapters => '管理章节';

  @override
  String get manageEpisodes => '管理剧集';

  @override
  String get selectAll => '全选';

  @override
  String get sortReverse => '逆序（新→旧）';

  @override
  String get sortNormal => '正序（旧→新）';

  @override
  String get readMark => '已读';

  @override
  String get videoFileNotFound => '视频文件不存在';

  @override
  String get openDownloadFolder => '打开下载位置';

  @override
  String get batchManage => '批量管理';

  @override
  String get comicLabel => '漫画';

  @override
  String get animeLabel => '动漫';

  @override
  String comicWithCount(int count) {
    return '漫画（$count）';
  }

  @override
  String animeWithCount(int count) {
    return '动漫（$count）';
  }

  @override
  String get hasUpdate => '有更新';

  @override
  String get updateBadge => '更新';

  @override
  String refreshedAt(String time) {
    return '刷新于 $time';
  }

  @override
  String get sortByUpdate => '按更新';

  @override
  String get sortByFavorite => '按收藏';

  @override
  String get sortByRead => '按阅读';

  @override
  String get sortLabel => '排序';

  @override
  String get sortMethod => '排序方式';

  @override
  String get sortByUpdateTime => '作品更新时间';

  @override
  String sortByUpdateTimeDesc(String type) {
    return '按$type最新章节的更新时间排序';
  }

  @override
  String get sortByFavoriteTime => '收藏时间';

  @override
  String get sortByFavoriteTimeDesc => '按加入书架的时间排序';

  @override
  String get sortByBrowseTime => '浏览时间';

  @override
  String get sortByBrowseTimeDesc => '按最近浏览的时间排序';

  @override
  String get bookshelfEmpty => '书架空空如也';

  @override
  String goFindSomething(String type) {
    return '去找点好看的$type吧';
  }

  @override
  String get refreshButton => '刷新';

  @override
  String get noComicUpdates => '没有漫画更新';

  @override
  String get backToTop => '回到顶部';

  @override
  String get refreshSuccess => '刷新成功';

  @override
  String get refreshFailed => '刷新失败';

  @override
  String get loginExpiredTitle => '登录已过期';

  @override
  String get loginExpiredBookshelfContent => '书架需要登录后才能继续使用，是否现在重新登录？';

  @override
  String get laterButton => '稍后再说';

  @override
  String get goLoginButton => '去登录';

  @override
  String get autoLoginFailed => '自动登录失败，请手动重新登录';

  @override
  String get loginToViewBookshelf => '登录后可继续查看书架';

  @override
  String totalEpisodes(int count) {
    return '共 $count 集';
  }

  @override
  String searchHint(String mode) {
    return '搜索$mode...';
  }

  @override
  String get hotSearchTitle => '热门搜索';

  @override
  String get allTagsTitle => '全部标签';

  @override
  String tagCount(int count) {
    return '$count 个';
  }

  @override
  String get popularOrder => '热度';

  @override
  String get updateOrder => '更新';

  @override
  String searchResultSummary(String query, int total, String mode) {
    return '搜索 \"$query\" 找到 $total 个$mode结果';
  }

  @override
  String openFolderFailed(String error) {
    return '打开文件夹失败：$error';
  }

  @override
  String get deleteToastPrefix => '已删除 ';

  @override
  String get deleteToastSuffixComic => ' 部本地漫画';

  @override
  String get deleteToastSuffixAnime => ' 部本地动漫';

  @override
  String get chapterUnit => '章';

  @override
  String get episodeUnit => '集';
}
