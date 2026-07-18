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
  String get disclaimerConfirmAgeAndTerms => '我已年满 18 周岁，并已仔细阅读、充分理解且同意上述全部条款';

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
  String get rankingAuthorWorks => '作者作品';

  @override
  String get rankingThemeWorks => '主题作品';

  @override
  String get rankingNoAuthorWorks => '暂无作者作品';

  @override
  String get rankingNoThemeWorks => '暂无主题作品';

  @override
  String get rankingNoComics => '暂无漫画';

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
  String get homeSourceHot => '热辣';

  @override
  String get homeSourceCopy => '拷贝';

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
  String loginExpiredFeatureContent(String featureName) {
    return '$featureName需要登录后才能继续使用，是否现在重新登录？';
  }

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

  @override
  String get generalTitle => '通用';

  @override
  String get autoLoginTitle => '自动登录';

  @override
  String get autoLoginEnabledDesc => '登录过期时自动重新登录';

  @override
  String get autoLoginUnavailableDesc => '登录并保存账号密码后可用';

  @override
  String get animeFeatureTitle => '动漫功能';

  @override
  String get animeFeatureDesc => '关闭后隐藏动漫相关功能';

  @override
  String get remoteNoticeTitle => '通知';

  @override
  String get remoteNoticeDesc => '开启后应用启动时自动检查通知；关闭后仅在进入通知中心时获取';

  @override
  String get noticeSettingsTooltip => '通知设置';

  @override
  String get bannerVisibleTitle => '显示Banner';

  @override
  String get bannerVisibleDesc => '关闭后漫画和动漫主页顶部Banner不显示';

  @override
  String get languageTitle => '语言';

  @override
  String get languageSimplifiedSystem => '简体中文（跟随系统）';

  @override
  String get languageTraditional => '繁體中文';

  @override
  String get cacheManagementTitle => '缓存管理';

  @override
  String get cacheManagementDesc => '查看和删除本地缓存、历史和账号数据';

  @override
  String get exportSettingsTitle => '导出设置';

  @override
  String get exportSettingsDesc => '复制配置到剪贴板';

  @override
  String get importSettingsTitle => '导入设置';

  @override
  String get importSettingsDesc => '粘贴导入配置';

  @override
  String get settingsCopiedWithSensitive => '设置已复制，包含敏感信息';

  @override
  String get settingsCopiedWithoutSensitive => '设置已复制，未包含敏感信息';

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get noImportSettingsContent => '没有可导入的配置内容';

  @override
  String get settingsBackupEmptyClipboard => '剪贴板里没有可导入的配置';

  @override
  String get settingsBackupInvalidJson => '配置格式不是有效的 JSON';

  @override
  String get settingsBackupInvalidFormat => '配置格式不正确';

  @override
  String get settingsBackupWrongApp => '这不是 Kira 的设置备份';

  @override
  String get settingsBackupUnsupportedVersion => '备份版本不受支持';

  @override
  String get settingsBackupMissingContent => '配置内容缺失或格式不正确';

  @override
  String get settingsBackupUnsupportedField => '配置中包含不支持的字段';

  @override
  String get settingsBackupInvalidFieldFormat => '配置字段格式不正确';

  @override
  String get settingsBackupUnsupportedFieldType => '配置字段类型不受支持';

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get overwriteImportTitle => '覆盖导入';

  @override
  String overwriteImportContent(int count, String backupTime) {
    return '将覆盖当前 $count 项持久化配置，包含账号、主题、阅读器设置和本地阅读记录。$backupTime\n\n临时缓存不会导入，当前配置会被替换。是否继续？';
  }

  @override
  String backupTimeLine(String time) {
    return '\n\n备份时间：$time';
  }

  @override
  String get confirmImportButton => '确认导入';

  @override
  String get settingsImportedToast => '配置已导入并覆盖本地设置';

  @override
  String get resetAppTitle => '重置应用';

  @override
  String get resetAppDesc => '清除本地设置、账号、阅读记录和缓存，不会删除已下载的本地漫画文件';

  @override
  String get resettingApp => '正在重置...';

  @override
  String appResetToast(int count) {
    return '应用已重置，已清除 $count 项本地数据';
  }

  @override
  String resetFailed(String error) {
    return '重置失败：$error';
  }

  @override
  String exportSettingsContent(int count) {
    return '将复制 $count 项持久化配置到剪贴板，导出内容为明文，请谨慎保管。';
  }

  @override
  String get includeSensitiveSettingsTitle => '包含密码和 API 重要信息';

  @override
  String get noSensitiveSettingsFound => '当前没有检测到已保存的敏感项';

  @override
  String includeSensitiveSettingsDesc(int count) {
    return '将额外包含 $count 项令牌、密码、API Key 或凭据信息';
  }

  @override
  String get copyButton => '复制';

  @override
  String get pasteExportedSettingsHint => '粘贴导出的配置 JSON';

  @override
  String get continueButton => '继续';

  @override
  String get confirmResetAppTitle => '确认重置应用';

  @override
  String get resetAppWarning => '此操作会清除应用本地保存的设置、账号、阅读记录和缓存，且无法撤销。';

  @override
  String resetAppInstruction(String text) {
    return '如需继续，请在下方输入框中输入“$text”。';
  }

  @override
  String get confirmTextLabel => '确认文本';

  @override
  String get confirmResetButton => '确认重置';

  @override
  String get animeUnavailableToast => '当前动漫暂时无法打开';

  @override
  String get animeEditorRecommend => '编辑推荐';

  @override
  String get animeRecentUpdate => '最近更新';

  @override
  String get animeClassicRecommend => '经典推荐';

  @override
  String get animeClassicAnimation => '经典动画';

  @override
  String get animeHotAnime => '热门动漫';

  @override
  String get loginRequiredTitle => '需要登录';

  @override
  String get playbackFailedTitle => '播放失败';

  @override
  String get viewLogButton => '查看日志';

  @override
  String get errorLogTitle => '错误日志';

  @override
  String get noLogInfo => '无日志信息';

  @override
  String get closeButton => '关闭';

  @override
  String get videoLinkTitle => '视频链接';

  @override
  String get videoLinkPending => '加载后显示视频链接';

  @override
  String get copyVideoLinkButton => '复制视频链接';

  @override
  String get openInBrowserButton => '浏览器打开';

  @override
  String get switchLineTooltip => '切换线路';

  @override
  String get profileCopyCredentialLabel => '拷贝';

  @override
  String get profileHotCredentialLabel => '热辣';

  @override
  String get accountSwitchedToast => '账号已切换';

  @override
  String get switchAccountTitle => '切换账号';

  @override
  String get addAccountButton => '添加账号';

  @override
  String get switchAccountFailedToast => '切换失败，请重试';

  @override
  String get logoutTitle => '退出登录';

  @override
  String get logoutConfirmContent => '确定要退出登录吗？';

  @override
  String get userInfoRefreshedToast => '用户信息已刷新';

  @override
  String get userInfoRefreshFailedToast => '刷新失败，请重试';

  @override
  String get tokenUnavailableToast => '暂无可复制的令牌';

  @override
  String get tokenCopiedToast => '令牌已复制到剪贴板';

  @override
  String get appearanceTitle => '外观';

  @override
  String get appearanceLogoChanged => '桌面图标已更换，可能需要重启应用后生效';

  @override
  String get appearanceColorPickerHeading => '点击色盘选择一个自定义主题色';

  @override
  String get appearanceColorPickerSubheading => '拖动取色点，实时预览主题色';

  @override
  String appearanceThemeColorUpdated(String color) {
    return '主题配色已更新为 $color';
  }

  @override
  String get appearanceBottomNavShowLabels => '底部导航栏显示文字';

  @override
  String get appearanceBottomNavLabelMode => '底部导航栏文字';

  @override
  String get appearanceBottomNavLabelModeSelectedOnly => '选中时显示';

  @override
  String get appearanceBottomNavLabelModeSelectedOnlyDesc => '胶囊导航，仅选中项显示文字';

  @override
  String get appearanceBottomNavLabelModeHidden => '不显示文字';

  @override
  String get appearanceBottomNavLabelModeHiddenDesc => '胶囊导航，只显示图标';

  @override
  String get appearanceBottomNavLabelModeAlways => '始终显示文字';

  @override
  String get appearanceBottomNavLabelModeAlwaysDesc => '经典导航，文字显示在图标下方';

  @override
  String get appearanceNavOrder => '导航栏顺序';

  @override
  String get appearanceNavOrderDragHint => '长按可拖放排序';

  @override
  String get appearanceAppIcon => '应用图标';

  @override
  String get appearanceAppIconRestartHint => '更换后重启应用生效';

  @override
  String get appearanceRefreshRateTitle => '屏幕刷新率';

  @override
  String get appearanceThemeMode => '主题模式';

  @override
  String get appearanceSystemMode => '系统';

  @override
  String get appearanceLightMode => '浅色';

  @override
  String get appearanceDarkMode => '深色';

  @override
  String get appearanceDarkCoverBrightness => '暗色模式封面亮度';

  @override
  String get appearanceDarkCoverBrightnessDesc => '暗色模式下降低各个界面的卡片封面亮度';

  @override
  String get appearanceThemeStyle => '主题风格';

  @override
  String appearanceCurrentStyle(String label, String description) {
    return '当前风格：$label · $description';
  }

  @override
  String get appearanceThemeColor => '主题配色';

  @override
  String get appearanceThemeColorDesc => '点击颜色块切换主题色，带勾选的为当前配色。';

  @override
  String appearanceRefreshRateRequested(String rate) {
    return '已请求刷新率 $rate';
  }

  @override
  String get appearanceRefreshRateSaved => '刷新率偏好已保存';

  @override
  String appearanceRefreshRateLoadFailed(String error) {
    return '获取设备刷新率失败：$error';
  }

  @override
  String get appearanceUnknownError => '未知错误';

  @override
  String get appearanceAutoSystem => '自动（跟随系统）';

  @override
  String appearanceRefreshRateCurrent(int rate) {
    return '${rate}Hz（当前）';
  }

  @override
  String appearanceApplyingRefreshRate(String rate) {
    return '正在应用 $rate';
  }

  @override
  String get appearanceRefreshRateDesc => '实际生效取决于系统和屏幕，部分设备可能需要重启应用后完全生效。';

  @override
  String get appearanceDefaultFontRestored => '已恢复系统默认字体，重启应用后完全生效';

  @override
  String appearanceFontChanged(String font) {
    return '字体已切换为 $font';
  }

  @override
  String appearanceFontLoadFailed(String error) {
    return '加载字体失败：$error';
  }

  @override
  String get appearanceAppFont => '应用字体';

  @override
  String get appearanceSystemDefault => '系统默认';

  @override
  String get appearanceChooseFont => '选择字体';

  @override
  String get appearanceSearchFont => '搜索字体';

  @override
  String get appearanceFontDeleteTitle => '删除字体';

  @override
  String appearanceFontDeleteContent(String fontId) {
    return '确定要删除字体 $fontId 吗？删除后将恢复为系统默认字体。';
  }

  @override
  String get appearanceFontNeedDownload => '请先下载字体后再使用';

  @override
  String appearanceFontDownloaded(String fontId) {
    return '$fontId 下载完成';
  }

  @override
  String get appearanceFontDownloadFailed => '字体下载失败';

  @override
  String get appearanceFontDownloadTooltip => '下载字体';

  @override
  String get appearanceFontNotDownloaded => '未下载';

  @override
  String get appearanceFontDownloadTitle => '下载字体';

  @override
  String appearanceFontDownloadPrompt(String fontName) {
    return '字体 $fontName 尚未下载，是否现在下载并应用？';
  }

  @override
  String get appearanceAddCustomFont => '添加自定义字体';

  @override
  String get appearanceCustomFontNameLabel => '字体名称';

  @override
  String get appearanceCustomFontNameHint => '例如：Source Han Sans';

  @override
  String get appearanceCustomFontUrlLabel => '字体下载链接';

  @override
  String get appearanceCustomFontUrlHint => 'https://example.com/font.ttf';

  @override
  String get appearanceCustomFontInvalid => '请填写有效的字体名称和 HTTP(S) 下载链接';

  @override
  String appearanceCustomFontAdded(String fontName) {
    return '已添加字体 $fontName';
  }

  @override
  String get appearanceCustomFontBadge => '自定义';

  @override
  String get appearanceCustomFontRemoveTitle => '移除自定义字体';

  @override
  String appearanceCustomFontRemoveContent(String fontName) {
    return '确定要移除自定义字体 $fontName 吗？本地文件也会被删除。';
  }

  @override
  String get cacheFontSection => '字体缓存';

  @override
  String get cacheFontLabel => '下载字体';

  @override
  String get cacheFontDesc => '已下载的字体文件，删除后将恢复为系统默认字体。';

  @override
  String get cacheClearFontTitle => '清除字体缓存';

  @override
  String cacheClearFontContent(int count, String size) {
    return '确定要删除 $count 个字体文件（$size）吗？删除后将恢复为系统默认字体。';
  }

  @override
  String get cacheFontClearedToast => '字体缓存已清除';

  @override
  String cacheFontDataTarget(int count, String size) {
    return '$count 个字体文件（$size）';
  }

  @override
  String get networkTitle => '网络';

  @override
  String get networkApiRouteTitle => 'API 线路';

  @override
  String get networkSelectionMode => '选择模式';

  @override
  String get networkModeRoute => '线路';

  @override
  String get networkModeFixedNode => '固定节点';

  @override
  String get networkModeAutomatic => '自动选择';

  @override
  String get networkAutomaticStatsTitle => '自动选择状态';

  @override
  String networkAutomaticBestNode(String node) {
    return '当前最佳：$node';
  }

  @override
  String get networkAutomaticLearning => '当前最佳：学习中';

  @override
  String get networkAutomaticCircuitOpen => '已熔断';

  @override
  String get networkAutomaticWaiting => '等待数据';

  @override
  String networkAutomaticRequestCount(int count) {
    return '$count 次请求';
  }

  @override
  String get networkTestOtherLatency => '测试其他节点延迟';

  @override
  String get networkFixedNodeAutoSelected => '测速后已选择延迟最低的节点';

  @override
  String networkRouteLabel(int index) {
    return '线路 $index';
  }

  @override
  String get networkTestLatency => '测试线路延迟';

  @override
  String get networkTestingNodes => '正在检测各节点...';

  @override
  String get networkNotTested => '尚未进行检测';

  @override
  String get networkHighLatencyProxySuggestion => '当前延迟较大，建议开启代理';

  @override
  String get networkRateLimitMessage => '请求过于频繁，已被限速，请稍后再试';

  @override
  String networkRequestFailedCode(String code) {
    return '请求失败（code: $code）';
  }

  @override
  String get networkCopyLoginHost => '拷贝登录';

  @override
  String get networkHotLoginHost => '热辣登录';

  @override
  String get networkFixedApiHost => '固定接口';

  @override
  String get networkSystemProxyNotDetected => '系统代理：未检测到';

  @override
  String get networkManualProxyNotConfigured => '手动代理：未配置';

  @override
  String get networkOtherRouteGroup => '其他';

  @override
  String get networkCollapseTestResults => '收起测试结果';

  @override
  String get networkExpandTestResults => '展开测试结果';

  @override
  String get networkProxySettings => '代理设置';

  @override
  String get networkRefreshSystemProxy => '重新检测系统代理';

  @override
  String get networkProxySystem => '系统';

  @override
  String get networkProxyManual => '手动';

  @override
  String get networkCurrentProxy => '当前代理';

  @override
  String get networkProxyAddress => '代理地址';

  @override
  String get networkProxyAddressHint =>
      '127.0.0.1:7890 或 http://127.0.0.1:7890';

  @override
  String get networkSaveAndEnableManualProxy => '保存并启用手动代理';

  @override
  String networkTestingGoogle(String proxy) {
    return '正在通过 $proxy 访问 Google ...';
  }

  @override
  String get networkGoogleConnectivity => 'Google 连通性';

  @override
  String get networkAdvancedSettings => '高级设置';

  @override
  String get networkCopyAppVersion => 'COPY 请求版本号';

  @override
  String get networkCopyAutoUpdate => '每天自动更新';

  @override
  String get networkCopyAutoUpdateNever => '尚未更新';

  @override
  String networkCopyAutoUpdateLast(String time) {
    return '上次更新：$time';
  }

  @override
  String get networkFill => '填充';

  @override
  String get networkAverageTesting => '平均：检测中';

  @override
  String get networkAverageTimeout => '平均：超时';

  @override
  String networkAverageLatency(int milliseconds) {
    return '平均：$milliseconds ms';
  }

  @override
  String networkNodeLabel(int index) {
    return '节点 $index';
  }

  @override
  String get networkTesting => '检测中';

  @override
  String get networkTimeout => '超时';

  @override
  String get networkNoSystemProxyDetected => '未检测到系统代理';

  @override
  String networkSystemProxyDetected(String proxy) {
    return '已检测到 $proxy';
  }

  @override
  String get networkCopyAdvancedSaved => '已保存 COPY 高级设置';

  @override
  String get networkCopyAdvancedReset => '已重置 COPY 高级设置';

  @override
  String networkCopyAutoFilled(String apiHost, String version) {
    return '已自动填充 COPY API 地址：$apiHost，版本号：$version';
  }

  @override
  String networkAutoFillFailed(String error) {
    return '自动填充失败：$error';
  }

  @override
  String get networkInvalidProxyAddress => '请输入有效的代理地址，例如 127.0.0.1:7890';

  @override
  String networkProxyEnabled(String proxy) {
    return '已启用 $proxy';
  }

  @override
  String networkConnectionSuccess(int statusCode, String proxyRule) {
    return '连接成功，HTTP $statusCode，$proxyRule';
  }

  @override
  String networkConnectionFailed(int statusCode, String proxyRule) {
    return '连接失败，HTTP $statusCode，$proxyRule';
  }

  @override
  String networkConnectionTimeout(String proxyRule) {
    return '连接超时，$proxyRule';
  }

  @override
  String networkProxyRuleError(String proxyRule, String error) {
    return '$proxyRule：$error';
  }

  @override
  String networkTestFailed(String proxyRule, String error) {
    return '测试失败，$proxyRule：$error';
  }

  @override
  String get aiConfigTitle => 'AI配置';

  @override
  String get aiConfigNewChat => '新对话';

  @override
  String get aiConfigProvidersTitle => 'AI 供应商';

  @override
  String get aiConfigAdd => '新增';

  @override
  String get aiConfigProvidersDescription =>
      '支持任何 OpenAI 兼容接口；智谱清言作为内置预设保留，可为不同供应商分别保存 Base URL、API Key、模型和接口格式。';

  @override
  String get aiConfigEnabled => '已启用';

  @override
  String get aiConfigDisabled => '已禁用';

  @override
  String aiConfigProviderSummary(
    String status,
    int count,
    String format,
    String baseUrl,
  ) {
    return '$status · $count 个模型 · $format\n$baseUrl';
  }

  @override
  String get aiConfigEdit => '编辑';

  @override
  String get aiConfigCustomProvider => '自定义供应商';

  @override
  String get aiConfigZhipuName => '智谱清言';

  @override
  String get aiConfigAddModel => '添加模型';

  @override
  String get aiConfigModelIdLabel => '模型 ID';

  @override
  String get aiConfigFillBaseUrlAndApiKey => '请先填写 Base URL 和 API Key';

  @override
  String aiConfigFetchModelsFailed(String error) {
    return '获取模型失败：$error';
  }

  @override
  String get aiConfigNoAvailableModels => '未获取到可用模型';

  @override
  String get aiConfigSelectModel => '选择模型';

  @override
  String get aiConfigAddSelected => '添加所选';

  @override
  String get aiConfigAddProvider => '新增供应商';

  @override
  String get aiConfigEditProvider => '编辑供应商';

  @override
  String get aiConfigProviderNameLabel => '供应商名称';

  @override
  String get aiConfigCustomNameLabel => '自定义名称';

  @override
  String get aiConfigCustomNameHint => 'OpenAI / One API / 自定义';

  @override
  String get aiConfigApiFormatLabel => '接口格式';

  @override
  String get aiConfigDefaultModelLabel => '默认模型';

  @override
  String get aiConfigNoSelection => '未选择';

  @override
  String get aiConfigFetch => '获取';

  @override
  String get aiConfigClear => '清空';

  @override
  String get aiConfigGetZhipuApiKey => '获取智谱 API 密钥';

  @override
  String get aiConfigProviderSaved => '供应商已保存';

  @override
  String get aiConfigConfigureBaseUrlAndApiKey => '请先配置 Base URL 和 API 密钥';

  @override
  String get aiConfigModelReturnedEmpty => '(模型未返回内容)';

  @override
  String aiConfigRequestFailed(String error) {
    return '请求失败：$error';
  }

  @override
  String aiConfigPartialResponseError(String content, String error) {
    return '$content\n\n[出错：$error]';
  }

  @override
  String get aiConfigSessionHistory => '会话历史';

  @override
  String get aiConfigNewSession => '新会话';

  @override
  String get aiConfigNoSessionHistory => '暂无历史会话';

  @override
  String aiConfigMessageCount(int count) {
    return '$count 条消息';
  }

  @override
  String get aiConfigDeleteSession => '删除会话';

  @override
  String get aiConfigProviderConfig => '接口配置';

  @override
  String get aiConfigClearChat => '清空对话';

  @override
  String get aiConfigInputHint => '说点什么…';

  @override
  String get aiConfigSend => '发送';

  @override
  String get aiConfigReadyEmptyHint => '配置AI后可以在章节评论中用于总结评论和屏蔽剧透';

  @override
  String get aiConfigSetupEmptyHint => '先在右上角配置接口';

  @override
  String get aiLegacyDefaultPromptBasic =>
      '先梳理评论区的主流声音、分歧点、大家吐槽/夸赞的核心内容；之后直抒胸臆，大胆表达你的立场，好坏直接点明，不中和、不打太极；绝对不要虚构漫画剧情，所有内容都基于现有评论；语言干练接地气，用 Markdown 输出一份犀利总结，类似下面的格式：\n### 大家在聊什么 （不超过7项，取多数人讨论的，每一项字数保持在25字以内）\n- 很多人都表示...\n- 有些人觉得...\n- 个别人认为...\n### 我的评论\n（发表你的评论，简短10-20字左右，不要附和他人观点，不是对其他人的看法，而是直接说你自己的看法或吐槽，表现得自然一点）';

  @override
  String get aiDefaultPromptBasic =>
      '先梳理评论区的主流声音、分歧点、大家吐槽/夸赞的核心内容；之后直抒胸臆，大胆表达你的立场，好坏直接点明，不中和、不打太极；绝对不要虚构漫画剧情，所有内容都基于现有评论；语言干练接地气，用 Markdown 输出一份犀利总结，类似下面的格式：\n### 大家在聊什么 （不超过7项，取多数人讨论的，每一项字数保持在25字以内）\n- 角色A做了什么...\n- 很多人吐槽...\n- xxxx...\n### 我的评论\n（发表你的评论，简短10-20字左右，不要附和他人观点，不是对其他人的看法，而是直接说你自己的看法或吐槽，表现得自然一点）';

  @override
  String get aiSpoilerAnalysisPromptAppendix =>
      '【剧透分析附加要求】\n用户已开启剧透分析。请在遵循上方提示词的基础上，额外满足以下要求：\n- 正文总结中不要复述、描述、暗示或概括任何剧透内容；\n- 可以输出 **剧透警告**，但仅当存在剧透评论时才输出此段，且只能写\"本章评论中有 N（这个N是剧透的数量） 处涉及剧透，已遮罩\"这一句，绝对不要描述、暗示或概括任何剧情/转折/结局；如果没有任何剧透评论则整段省略。\n\n【剧透的判定标准 · 非常重要】\n只有同时满足以下全部条件的评论才应标记为剧透：\n- 明确透露（包含猜测，有些用户会通过猜测进行剧透）了尚未在当前章节及之前出场过的剧情走向、角色命运（死亡、复活、背叛等）或结局结果；\n- 普通的感想（如\"太好看了\"\"画风不错\"）、角色喜爱（如\"XX好帅\"）、对已发生情节的正常讨论、对后续的模糊期待（如\"期待下一话\"）【不算】剧透；\n【机读输出】用户消息中每条评论开头都是它的数字 id（形如 \"81216. xxx: ...\"）。在整篇输出的最末尾追加一个 fenced code block（用三个反引号包裹），里面只放一个 JSON 数字数组，列出【高度剧透嫌疑】的评论 id：\n```\n[81216, 81230]\n```\n如果没有任何高度剧透的评论，依然必须输出该代码块，数组为空：\n```\n[]\n```\n硬性要求：\n1) 必须是整篇输出的最后一段，下面不要再写任何字；\n2) 必须用三个反引号包裹（语言标识写不写都行）；\n3) 中括号里只能有数字和英文逗号，不要写解释、不要带 id= 前缀；\n4) 哪怕没有剧透也要写空数组 []，不能省略整个代码块；\n';

  @override
  String get aiPromptBasicName => '基础提示词';

  @override
  String get noticeCenterTitle => '通知中心';

  @override
  String get downloadCenterTitle => '下载中心';

  @override
  String get browseHistoryTitle => '浏览记录';

  @override
  String get aboutTitle => '关于';

  @override
  String get notLoggedInTitle => '未登录';

  @override
  String get loginPromptSubtitle => '点击登录以使用书架等功能';

  @override
  String get refreshUserButton => '刷新用户';

  @override
  String get switchAccountButton => '切换账号';

  @override
  String get copyTokenButton => '复制令牌';

  @override
  String get appDisclaimerIntro => '请在使用本应用前仔细阅读以下声明：';

  @override
  String get appDisclaimerItem1 =>
      '本应用（以下简称\"本软件\"）系独立开发的非官方第三方客户端，与任何内容平台、出版商或权利人均无隶属、合作或代理关系。';

  @override
  String get appDisclaimerItem2 =>
      '本软件不生产、上传、存储、编辑、修改、推荐或预先审查任何具体内容。所有内容均来源于第三方平台公开接口或可访问资源，其合法性、准确性、完整性及合规性由相应内容提供方独立负责。';

  @override
  String get appDisclaimerItem3 =>
      '本软件所展示的内容可能包含成人向、暴力、恐怖或其他不适宜未成年人浏览的信息。您确认您已年满 18 周岁，且您所在地法律法规允许您访问此类内容。如您不符合前述条件，请立即停止使用并卸载本软件。';

  @override
  String get appDisclaimerItem4 =>
      '您应自行判断所浏览内容是否适合，并确保您的使用行为完全符合您所在地现行有效的法律法规。因您使用本软件而产生的一切法律后果由您自行承担。';

  @override
  String get appDisclaimerItem5 =>
      '如任何第三方内容涉嫌侵犯他人合法权益或违反法律法规，权利人可通过本软件提供的联系方式向开发者发送有效通知，开发者将在合理期限内核实并采取必要措施。';

  @override
  String get appDisclaimerItem6 =>
      '本软件按\"现状\"提供，开发者不对其功能性、可用性、准确性或可靠性作出任何明示或默示的保证。在任何情况下，开发者均不对因使用或无法使用本软件而产生的任何直接、间接、附带、特殊或后果性损害承担责任。';

  @override
  String get appDisclaimerFooter =>
      '继续使用本软件，即表示您已仔细阅读、充分理解并同意接受上述全部条款的约束。如您不同意任一条款，请立即停止使用并卸载本软件。';

  @override
  String get profileCurrentSelectedCredential => '当前已选';

  @override
  String get profileRemoveAccountTooltip => '移除账号';

  @override
  String profileAccountRemovedToast(String username) {
    return '已移除 $username';
  }

  @override
  String get profileRegisterSuccessLoginToast => '注册成功，请登录';

  @override
  String get profileUsernamePasswordRequired => '请输入用户名和密码';

  @override
  String get profileLoginFailed => '登录失败';

  @override
  String get profileTokenRequired => '请输入令牌';

  @override
  String get profileTokenInvalidOrExpired => '令牌无效或已过期';

  @override
  String get profileLoginTitle => '登录';

  @override
  String get profileAccountPasswordLoginMode => '账号密码';

  @override
  String get profileTokenLoginMode => '令牌';

  @override
  String get profileSavedAccountsTitle => '已保存账号';

  @override
  String get profileSavedAccountsHint => '点按快速填充账号密码，右侧可移除';

  @override
  String get profileUsernameLabel => '用户名';

  @override
  String get profilePasswordLabel => '密码';

  @override
  String get profileTokenLabel => '令牌 (Token)';

  @override
  String get profileTokenHint => '粘贴你的登录令牌';

  @override
  String get profileRememberAccountLabel => '记住账号';

  @override
  String get profileRegisterHotMangaAccountButton => '注册热辣漫画账号';

  @override
  String get profileLoginButton => '登录';

  @override
  String get profileRegisterInfoRequired => '请填写完整注册信息';

  @override
  String get profilePasswordMismatch => '两次输入的密码不一致';

  @override
  String get profileSecurityQuestionRequired => '请选择安全问题';

  @override
  String get profileRegisterFailed => '注册失败';

  @override
  String get profileOpenOfficialRegisterFailed => '无法打开官网注册页';

  @override
  String get profileConfirmPasswordLabel => '确认密码';

  @override
  String get profileSecurityQuestionLabel => '账号安全问题';

  @override
  String get profileSecurityAnswerLabel => '安全问题答案';

  @override
  String get profileReloadSecurityQuestionsButton => '重新加载安全问题';

  @override
  String get profileRegisterButton => '注册';

  @override
  String get profileOfficialRegisterPrompt => '去官网注册';

  @override
  String get profileHotMangaLabel => '热辣漫画';

  @override
  String get profileCopyMangaLabel => '拷贝漫画';

  @override
  String get aboutQqGroupTitle => 'QQ交流群';

  @override
  String get aboutJoinGroupButton => '加入群聊';

  @override
  String get aboutGroupNumberCopiedToast => '已复制群号';

  @override
  String get aboutMirrorPrefixTitle => '设置镜像源';

  @override
  String get aboutMirrorPrefixDesc => '用于更新与播放组件下载的镜像链接，会拼接在 GitHub 下载地址前。';

  @override
  String get aboutMirrorPrefixLabel => '镜像源地址';

  @override
  String get aboutMirrorPrefixHelper => '留空将恢复默认镜像源';

  @override
  String get aboutInvalidMirrorPrefix => '请输入有效的 http(s) 地址';

  @override
  String get aboutRestoreDefaultButton => '恢复默认';

  @override
  String get aboutSaveButton => '保存';

  @override
  String get aboutMirrorPrefixSavedToast => '镜像源已保存';

  @override
  String get aboutStableChannelShort => '稳定版';

  @override
  String get aboutUpdateChannelTitle => '更新渠道';

  @override
  String get aboutStableChannelTitle => '稳定版 (Stable)';

  @override
  String get aboutStableChannelDesc => '仅检查正式发布版本';

  @override
  String get aboutBetaChannelTitle => '预览版（Beta）';

  @override
  String get aboutBetaChannelDesc => '从最新提交构建的版本，可能不稳定';

  @override
  String get aboutBetaChannelSwitchedTitle => '已切换到预览版';

  @override
  String get aboutBetaChannelSwitchedContent => '预览版一般用于测试新功能或修复问题，可能存在更多问题。';

  @override
  String get aboutGotItButton => '知道了';

  @override
  String get aboutRepositoryLabel => '仓库';

  @override
  String get aboutFeedbackLabel => '反馈';

  @override
  String get aboutCommunityLabel => '交流';

  @override
  String get aboutCheckUpdateTitle => '检查更新';

  @override
  String get aboutAutoCheckUpdateTitle => '启动时检查更新';

  @override
  String get aboutLogTitle => '日志';

  @override
  String get aboutAcknowledgementTitle => '致谢';

  @override
  String get acknowledgementThanksTitle => '感谢以下服务与项目的支持';

  @override
  String get acknowledgementDandanplayTitle => '弹弹play';

  @override
  String get acknowledgementDandanplayDesc => '提供弹幕服务';

  @override
  String get acknowledgementZhconvertTitle => '繁化姬';

  @override
  String get acknowledgementZhconvertDesc => '提供简体化服务';

  @override
  String get aboutLicenseTitle => '许可证';

  @override
  String get licenseMitSummary => '本项目采用 MIT 开源许可证';

  @override
  String get cacheDeleteEntryTitle => '删除缓存项';

  @override
  String cacheDeleteEntryContent(String key) {
    return '确定要删除 $key 吗？此操作不可恢复。';
  }

  @override
  String cacheEntryDeletedToast(String key) {
    return '已删除 $key';
  }

  @override
  String cacheDeleteFailedToast(String error) {
    return '删除失败：$error';
  }

  @override
  String cacheLocalDataTarget(int count) {
    return '$count 项本地数据';
  }

  @override
  String cacheImageDataTarget(int count, String size) {
    return '$count 个图片缓存（$size）';
  }

  @override
  String cacheMediaKitDataTarget(String size) {
    return '播放组件（$size）';
  }

  @override
  String get cacheDeleteSelectedTitle => '删除选中缓存';

  @override
  String cacheDeleteSelectedContent(String targets) {
    return '确定要删除选中卡片中的 $targets 吗？此操作不可恢复。';
  }

  @override
  String get cacheSelectedDeletedToast => '已删除选中缓存';

  @override
  String get cacheNoImageCacheToClear => '暂无可清理的图片缓存';

  @override
  String get cacheClearImageCacheTitle => '清空图片缓存';

  @override
  String cacheClearImageCacheContent(String label, int fileCount, String size) {
    return '确定要清空 $label 吗？将删除 $fileCount 个文件，释放约 $size。';
  }

  @override
  String get cacheClearButton => '清空';

  @override
  String cacheClearDataSectionContent(String sectionLabel) {
    return '确定要清空 $sectionLabel 中的所有数据吗？';
  }

  @override
  String cacheImageCacheClearedToast(String label) {
    return '已清空 $label';
  }

  @override
  String cacheCleanFailedToast(String error) {
    return '清理失败：$error';
  }

  @override
  String get cacheReaderImageLabel => '图片缓存 / 漫画阅读器';

  @override
  String get cacheReaderImageDesc => '漫画章节图片缓存。再次打开读过的章节时，图片会优先从这里读取。';

  @override
  String get cacheDefaultImageLabel => '图片缓存 / 封面与头像';

  @override
  String get cacheDefaultImageDesc => '封面、头像等 CachedNetworkImage 默认使用的图片缓存。';

  @override
  String get cacheMediaKitLabel => '播放组件 / media_kit';

  @override
  String get cacheMediaKitDesc => '动漫播放器原生库（libmpv 等）。首次播放时按需下载；删除后下次播放会重新下载。';

  @override
  String get cacheMediaKitSection => '播放组件';

  @override
  String get cacheNoMediaKitToClear => '尚未下载播放组件';

  @override
  String get cacheClearMediaKitTitle => '删除播放组件';

  @override
  String cacheClearMediaKitContent(int fileCount, String size) {
    return '确定删除已下载的播放组件吗？将删除 $fileCount 个文件，释放约 $size。下次播放动漫时会重新下载。';
  }

  @override
  String get cacheMediaKitClearedToast => '已删除播放组件';

  @override
  String get cacheMediaKitVersionLabel => '组件版本';

  @override
  String get commentSettingsEditBuiltInPromptTitle => '编辑内置提示词';

  @override
  String get commentSettingsEditPromptTitle => '编辑提示词';

  @override
  String get commentSettingsAddPromptTitle => '添加提示词';

  @override
  String get commentSettingsNameLabel => '名称';

  @override
  String get commentSettingsPromptLabel => '提示词';

  @override
  String get commentSettingsResetButton => '重置';

  @override
  String get commentSettingsSaveButton => '保存';

  @override
  String get commentSettingsAddButton => '添加';

  @override
  String get commentSettingsTitle => '评论区设置';

  @override
  String get commentSettingsLayoutSection => '布局';

  @override
  String get commentSettingsCompactLayout => '紧凑布局';

  @override
  String get commentSettingsListLayout => '列表布局';

  @override
  String get commentSettingsShowAvatar => '显示头像';

  @override
  String get commentSettingsShowUserName => '显示用户名';

  @override
  String get commentSettingsShowCommentTime => '显示评论时间';

  @override
  String get commentSettingsPreloadTitle => '预加载评论';

  @override
  String get commentSettingsPreloadDesc => '进入章节时提前加载评论并显示数量';

  @override
  String get commentSettingsAutoLoadAllTitle => '自动加载全部评论';

  @override
  String get commentSettingsAutoLoadAllDesc => '打开评论区时自动加载所有评论';

  @override
  String get commentSettingsFontSizeTitle => '评论内容字体大小';

  @override
  String get chapterCommentsNoSummaryComments => '当前没有可总结的评论';

  @override
  String get chapterCommentsEnableAiSummaryFirst => '请先在评论区设置中启用 AI 总结';

  @override
  String chapterCommentsPromptComicLine(String comicName) {
    return '漫画：$comicName\n';
  }

  @override
  String chapterCommentsPromptUser(
    String comicLine,
    String chapterName,
    int count,
    String snippets,
  ) {
    return '$comicLine章节：$chapterName\n共 $count 条不同评论（相同内容已合并）。每条行首数字为该评论的 id：\n\n$snippets';
  }

  @override
  String chapterCommentsMergedSnippet(int id, int count, String text) {
    return '$id. [$count人] $text\n';
  }

  @override
  String chapterCommentsSingleSnippet(int id, String userName, String text) {
    return '$id. $userName: $text\n';
  }

  @override
  String chapterCommentsSnippetsTruncated(int count) {
    return '…（已截断，共 $count 条不同评论）';
  }

  @override
  String get chapterCommentsDioException => 'Dio 异常';

  @override
  String get chapterCommentsCopyLog => '复制日志';

  @override
  String get chapterCommentsLoginRequiredToPost => '请先登录后再发表评论';

  @override
  String get chapterCommentsLengthRange => '评论字数需在 3-200 之间';

  @override
  String get chapterCommentsPosted => '评论已发布';

  @override
  String get chapterCommentsPostTitle => '发表评论';

  @override
  String get chapterCommentsPostHint => '吐槽一下';

  @override
  String get chapterCommentsLengthHelper => '评论字数 3-200';

  @override
  String get chapterCommentsLogCopied => '日志已复制';

  @override
  String get chapterCommentsPublish => '发布';

  @override
  String get chapterCommentsActionTitle => '评论操作';

  @override
  String get chapterCommentsPlusOneSubtitle => '发送一条相同评论';

  @override
  String get chapterCommentsBlockUser => '屏蔽用户';

  @override
  String chapterCommentsHideUserComments(String userName) {
    return '隐藏 $userName 的评论';
  }

  @override
  String get chapterCommentsCopied => '已复制';

  @override
  String get chapterCommentsUserBlocked => '已屏蔽该用户';

  @override
  String get chapterCommentsBlockUnnamedConfirm => '确定屏蔽该用户吗？屏蔽后将不再显示其评论。';

  @override
  String chapterCommentsBlockNamedConfirm(String name) {
    return '确定屏蔽「$name」吗？屏蔽后将不再显示其评论。\n可在评论区设置 → 黑名单中解除。';
  }

  @override
  String get chapterCommentsNoRemindAgain => '不再提醒';

  @override
  String get chapterCommentsBlock => '屏蔽';

  @override
  String get chapterCommentsPlusOneLengthInvalid => '评论字数需在 3-200 之间，无法 +1';

  @override
  String get chapterCommentsPlusOneSent => '+1 已发送';

  @override
  String get chapterCommentsPostFailed => '发表评论失败';

  @override
  String get chapterCommentsTitle => '章节评论';

  @override
  String get chapterCommentsLoadAllTooltip => '加载全部评论';

  @override
  String get chapterCommentsAiSummaryTooltip => 'AI 总结评论';

  @override
  String get chapterCommentsRegenerateAiSummaryTooltip => '重新生成 AI 总结';

  @override
  String get chapterCommentsSwitchToListLayout => '切换为列表布局';

  @override
  String get chapterCommentsSwitchToCompactLayout => '切换为紧凑布局';

  @override
  String chapterCommentsTotalCount(int count) {
    return '$count 条';
  }

  @override
  String get chapterCommentsComment => '评论';

  @override
  String get chapterCommentsCatalog => '目录';

  @override
  String get chapterCommentsNext => '下一话';

  @override
  String get chapterCommentsLoadFailed => '评论加载失败';

  @override
  String get chapterCommentsEmptyTitle => '还没有评论';

  @override
  String get chapterCommentsEmptySubtitle => '这个章节暂时没人发言';

  @override
  String get chapterCommentsSwitchModel => '切换模型';

  @override
  String get chapterCommentsCannotSwitchModelGenerating => '生成中无法切换模型';

  @override
  String chapterCommentsModelSummary(String model) {
    return '$model 总结';
  }

  @override
  String chapterCommentsActiveModel(String provider, String model) {
    return '当前模型：$provider / $model';
  }

  @override
  String get chapterCommentsReasoning => '思考过程';

  @override
  String get chapterCommentsReasoningCollapsed => '思考过程（已折叠）';

  @override
  String get chapterCommentsGenerating => '正在生成中…';

  @override
  String get chapterCommentsCollapse => '收起';

  @override
  String get chapterCommentsExpand => '展开';

  @override
  String chapterCommentsSummaryFailed(String error) {
    return '生成失败：$error';
  }

  @override
  String get chapterCommentsStop => '停止';

  @override
  String get chapterCommentsRegenerate => '重新生成';

  @override
  String get chapterCommentsClearSummary => '清除总结';

  @override
  String get comicCommentTitle => '漫画评论';

  @override
  String get comicCommentSettingsTooltip => '评论设置';

  @override
  String get comicCommentLoadFailed => '评论加载失败';

  @override
  String get comicCommentEmptySubtitle => '这部漫画暂时没人发言';

  @override
  String get comicCommentCollapseReplies => '收起回复';

  @override
  String comicCommentExpandReplies(int count) {
    return '展开 $count 条回复';
  }

  @override
  String get comicCommentReplyLoadFailed => '回复加载失败';

  @override
  String get comicCommentEmptyReplies => '暂无可显示的回复';

  @override
  String get comicCommentRetryLoadMoreReplies => '重试加载更多回复';

  @override
  String comicCommentLoadMoreReplies(int loaded, int total) {
    return '加载更多回复 ($loaded/$total)';
  }

  @override
  String get comicCommentCopied => '评论已复制';

  @override
  String comicCommentBlockNamedConfirm(String name) {
    return '确定屏蔽「$name」吗？屏蔽后将不再显示其评论。\n可在黑名单中解除。';
  }

  @override
  String comicCommentReplyTitle(String userName) {
    return '回复 $userName';
  }

  @override
  String comicCommentReplyHint(String userName) {
    return '回复 $userName...';
  }

  @override
  String get comicCommentPostHint => '说点什么...';

  @override
  String get comicCommentReplyPosted => '回复已发布';

  @override
  String get comicCommentReplyButton => '回复';

  @override
  String get comicCommentExpandFullText => '展开全文';

  @override
  String get animeDetailTitle => '动漫详情';

  @override
  String get animeDetailIntroTab => '简介';

  @override
  String animeDetailEpisodesTab(int count) {
    return '选集 ($count)';
  }

  @override
  String get animeDetailIntroRefreshFailed => '简介刷新失败';

  @override
  String get animeDetailEpisodeRefreshFailed => '选集刷新失败';

  @override
  String get animeDetailDandanplayBindingCleared => '已清除弹弹play绑定';

  @override
  String animeDetailDandanplayBound(String title) {
    return '已绑定 $title';
  }

  @override
  String get animeDetailAlignmentCleared => '已清除对齐';

  @override
  String get animeDetailRealigned => '已重新对齐弹幕';

  @override
  String get animeDetailNoAvailableLine => '当前选集暂无可用线路';

  @override
  String get animeDetailPlaybackEpisodeUnavailable => '播放记录对应选集暂不可用';

  @override
  String get animeDetailInfoLoadFailedForDownload => '动漫信息加载失败，无法下载';

  @override
  String get animeDetailNoLineForDownload => '当前选集暂无可用线路，无法下载';

  @override
  String animeDetailDownloadTasksAdded(int count) {
    return '已添加 $count 个下载任务';
  }

  @override
  String get animeDetailCannotCollect => '当前动漫暂时无法收藏';

  @override
  String get animeDetailCollected => '已收藏';

  @override
  String get animeDetailCollectCancelled => '已取消收藏';

  @override
  String get animeDetailCollectFailed => '收藏状态修改失败';

  @override
  String animeDetailDownloadTaskCount(int count) {
    return '$count 个任务';
  }

  @override
  String get animeDetailNoIntroInfo => '暂无简介信息';

  @override
  String get animeDetailInfoTitle => '资料';

  @override
  String get animeDetailIntroLoadFailed => '简介加载失败，下拉重试';

  @override
  String get animeDetailIntroRefreshFailedCached => '简介刷新失败，当前显示缓存内容';

  @override
  String animeDetailSelectedEpisodes(int count) {
    return '已选 $count 集';
  }

  @override
  String get animeDetailSelectAllUndownloaded => '全选未下载';

  @override
  String get animeDetailDownloadSelected => '下载选中';

  @override
  String get animeDetailEpisodeLoadFailed => '选集加载失败，下拉重试';

  @override
  String get animeDetailNoEpisodes => '暂无选集';

  @override
  String get animeDetailEpisodeRefreshFailedCached => '选集刷新失败，当前显示上次结果';

  @override
  String get animeDetailBindToViewComments => '绑定弹弹play 后才可查看评论';

  @override
  String get animeDetailBindDanmaku => '绑定弹幕';

  @override
  String get animeDetailRebind => '重新绑定';

  @override
  String get animeDetailAlign => '对齐';

  @override
  String get animeDetailDownloadButton => '下载';

  @override
  String get animeDetailEpisodeLoadFailedShort => '选集加载失败';

  @override
  String get readerSettingsTitle => '阅读设置';

  @override
  String get readerScrollMode => '滚动';

  @override
  String get readerPageMode => '翻页';

  @override
  String get readerLeftToRight => '左到右';

  @override
  String get readerRightToLeft => '右到左';

  @override
  String get readerTopToBottom => '上到下';

  @override
  String get readerScrollSection => '滚动';

  @override
  String get readerImageGap => '图片间距';

  @override
  String get readerContinuousReading => '连续阅读';

  @override
  String get readerContinuousReadingDesc => '到末页后直接拼接下一话，不重新加载';

  @override
  String get readerAutoScroll => '自动滚动';

  @override
  String get readerAutoScrollDesc => '开启后在导航栏显示自动滚动按钮';

  @override
  String get readerAutoScrollDistance => '滚动幅度';

  @override
  String get readerAutoScrollPause => '停顿时长';

  @override
  String readerSeconds(String seconds) {
    return '$seconds 秒';
  }

  @override
  String get readerAutoResume => '自动恢复';

  @override
  String get readerAutoResumeDesc => '一段时间无动作后自动恢复滚动';

  @override
  String get readerAutoResumeDelay => '恢复延迟';

  @override
  String get readerPageSection => '翻页';

  @override
  String get readerVolumeKeyPageTurn => '音量键翻页';

  @override
  String get readerVolumeKeyPageTurnDesc => '音量+上一页，音量-下一页';

  @override
  String get readerInstantPageTurn => '无动画翻页';

  @override
  String get readerDisplaySection => '显示';

  @override
  String get readerDimming => '降低亮度';

  @override
  String get readerImageLoadingSection => '图片加载';

  @override
  String get readerTimeout => '超时时间';

  @override
  String get readerTimeoutDesc => '设置太小可能导致图片加载失败，太大可能导致长时间转圈';

  @override
  String get readerNoLoadStats => '暂无加载记录（阅读图片后此处显示平均耗时供参考）';

  @override
  String readerRecentLoadStats(int count, String seconds) {
    return '最近10分钟内加载了 $count 张，平均 $seconds s';
  }

  @override
  String get readerRetryCount => '重试次数';

  @override
  String get offButton => '关闭';

  @override
  String readerTimes(int count) {
    return '$count 次';
  }

  @override
  String get browseHistoryClearTitle => '清空浏览记录';

  @override
  String browseHistoryClearContent(String mode) {
    return '确定要清空所有$mode浏览记录吗？此操作不可撤销。';
  }

  @override
  String browseHistoryCleared(String mode) {
    return '已清空$mode浏览记录';
  }

  @override
  String browseHistoryClearFailed(String error) {
    return '清空失败：$error';
  }

  @override
  String get browseHistoryLoginExpiredContent => '浏览记录需要登录后才能继续查看，是否现在重新登录？';

  @override
  String get browseHistoryLoginToView => '登录后可继续查看浏览记录';

  @override
  String get browseHistoryLoginHintWithAnime => '浏览过的漫画和动漫会同步显示在这里';

  @override
  String get browseHistoryLoginHintComicOnly => '浏览过的漫画会同步显示在这里';

  @override
  String browseHistoryEmptyTitle(String mode) {
    return '还没有$mode浏览记录';
  }

  @override
  String browseHistoryEmptySubtitle(String mode) {
    return '去看几部$mode后，这里会显示最近浏览内容';
  }

  @override
  String browseHistoryTotal(int count, String mode) {
    return '共 $count 条$mode浏览记录';
  }

  @override
  String hundredMillionUnit(String value) {
    return '$value亿';
  }

  @override
  String tenThousandUnit(String value) {
    return '$value万';
  }

  @override
  String browseHistoryLatestChapter(String chapter) {
    return '最新 $chapter';
  }

  @override
  String browseHistoryLastSeen(String name) {
    return '上次看到 $name';
  }

  @override
  String get animePlayerLoginRequiredToPlay => '登录后才能播放该视频';

  @override
  String get animePlayerEmptyVideoUrl => '视频链接为空';

  @override
  String animePlayerRequestFailedStatus(int statusCode) {
    return '请求失败（$statusCode）';
  }

  @override
  String animePlayerRequestFailedStatusText(String statusCode) {
    return '请求失败（$statusCode）';
  }

  @override
  String get animePlayerMpvLogTitle => 'media_kit/mpv 日志:';

  @override
  String get animePlayerQuickDiagnosisTitle => '快速诊断:';

  @override
  String animePlayerDiagnosisManifestStatus(int statusCode) {
    return 'm3u8 状态: $statusCode';
  }

  @override
  String get animePlayerDiagnosisManifestHls => 'm3u8 内容: 已识别为 HLS 清单';

  @override
  String get animePlayerDiagnosisManifestNotHls =>
      'm3u8 内容: 返回 200，但内容不像标准 HLS 清单';

  @override
  String animePlayerDiagnosisManifestError(String error) {
    return 'm3u8 错误: $error';
  }

  @override
  String animePlayerDiagnosisFirstSegment(String url) {
    return '首个分片: $url';
  }

  @override
  String animePlayerDiagnosisSegmentStatus(int statusCode) {
    return '首个分片状态: $statusCode';
  }

  @override
  String animePlayerDiagnosisSegmentBytes(int bytes) {
    return '首个分片字节数: $bytes';
  }

  @override
  String animePlayerDiagnosisSegmentError(String error) {
    return '首个分片错误: $error';
  }

  @override
  String get animePlayerDiagnosisConclusionDecodeIssue =>
      '结论: m3u8 与首个分片都可访问，更像是播放器解析或解码兼容问题';

  @override
  String get animePlayerSourceForbidden => '视频源拒绝访问（403）';

  @override
  String get animePlayerSourceNotFound => '视频地址已失效（404）';

  @override
  String get animePlayerCertificateFailed => '视频证书校验失败';

  @override
  String get animePlayerConnectionTimeout => '视频连接超时';

  @override
  String get animePlayerCannotParseStream => '视频源可访问，但播放器无法解析该视频流';

  @override
  String get animePlayerEnableProxyToRetry => '视频加载失败，请开启代理后重试';

  @override
  String get animePlayerInvalidVideoUri => '视频地址不是合法 URI';

  @override
  String get animePlayerDiagnosisRequestFailed => '视频诊断请求失败';

  @override
  String get animePlayerSegmentDiagnosisRequestFailed => '视频分片诊断请求失败';

  @override
  String get animePlayerSegmentUrlNotResolved => '未解析出分片地址';

  @override
  String get animePlayerLoadingCannotSwitch => '视频加载中，请稍后再切换';

  @override
  String get animePlayerNoVideoUrlToCopy => '暂无可复制的视频链接';

  @override
  String get animePlayerVideoUrlCopied => '视频链接已复制到剪贴板';

  @override
  String get animePlayerNoVideoUrlToOpen => '暂无可打开的视频链接';

  @override
  String get animePlayerOpenVideoUrlFailed => '无法打开视频链接';

  @override
  String animePlayerSeekedTo(String position) {
    return '已跳转到 $position';
  }

  @override
  String get animePlayerSeekLastFailed => '无法跳转到上次进度';

  @override
  String animePlayerSearchFailed(String error) {
    return '搜索失败: $error';
  }

  @override
  String get animePlayerRefreshTooFrequent => '不要频繁刷新！';

  @override
  String animePlayerLoadDanmakuFailed(String error) {
    return '加载弹幕失败: $error';
  }

  @override
  String get animePlayerBuffering => '正在缓冲...';

  @override
  String get animePlayerProxySuggestion => '如果网络卡顿，建议开启代理访问';

  @override
  String get animePlayerPlay => '播放';

  @override
  String animePlayerFastForward(int seconds) {
    return '快进 $seconds秒';
  }

  @override
  String get animePlayerHideDanmaku => '隐藏弹幕';

  @override
  String get animePlayerChapterSelector => '选集';

  @override
  String animePlayerChapterSelectorWithCount(int count) {
    return '选集 ($count)';
  }

  @override
  String get animePlayerSetSkipSeconds => '设置跳转秒数';

  @override
  String get animePlayerExitFullscreen => '退出全屏';

  @override
  String get animePlayerFullscreen => '全屏';

  @override
  String get backButton => '返回';

  @override
  String cacheSelectedCards(int count) {
    return '已选 $count 个卡片';
  }

  @override
  String get cacheDeleteSelectedCardsTooltip => '删除选中卡片';

  @override
  String get cacheExitMultiSelectTooltip => '退出多选';

  @override
  String get cacheMultiSelectTooltip => '多选卡片';

  @override
  String cacheSummary(int localTotal, int imageCacheFiles, String size) {
    return '共 $localTotal 项本地数据 · $size';
  }

  @override
  String get cacheManagementSummaryDesc =>
      '按缓存、账号、设置、历史等分类显示；AI 配置 key 已隐藏；图片与播放组件可单独清理。';

  @override
  String get cacheImageCacheSection => '图片缓存';

  @override
  String get cacheDataCacheSection => '数据缓存';

  @override
  String get cacheNoLocalKeyValueData => '没有可显示的本地键值数据';

  @override
  String cacheEntryCountSize(int count, String size) {
    return '$count 项 · $size';
  }

  @override
  String get cacheHideSensitiveTooltip => '隐藏敏感内容';

  @override
  String get cacheShowSensitiveTooltip => '显示敏感内容';

  @override
  String get cacheEntryDataTitle => '缓存项数据';

  @override
  String get cacheDataCopiedToast => '缓存数据已复制';

  @override
  String cacheFileCountSize(int count, String size) {
    return '$count 个文件 · $size';
  }

  @override
  String get cacheDescriptionTitle => '说明';

  @override
  String get cacheKeyTitle => '缓存标识';

  @override
  String get cacheDirectoryTitle => '缓存目录';

  @override
  String get cacheCategoryPersistentCache => '业务缓存';

  @override
  String get cacheCategoryAccount => '账号数据';

  @override
  String get cacheCategoryAppSettings => '应用设置';

  @override
  String get cacheCategoryMangaHistory => '漫画阅读历史';

  @override
  String get cacheCategoryAnimeHistory => '动漫播放历史';

  @override
  String get cacheCategoryBindings => '弹幕绑定';

  @override
  String get cacheCategoryAiSummaryCache => 'AI 总结缓存';

  @override
  String get cacheCategoryOther => '其他数据';

  @override
  String get themeColorBlueGrey => '蓝灰';

  @override
  String get themeColorTeal => '青绿';

  @override
  String get themeColorIndigo => '靛蓝';

  @override
  String get themeColorGreen => '森绿';

  @override
  String get themeColorOrange => '橙金';

  @override
  String get themeColorPink => '粉色';

  @override
  String get themeColorBrightBlue => '亮蓝';

  @override
  String get themeColorViolet => '紫罗兰';

  @override
  String get themeColorOrchid => '兰紫';

  @override
  String get themeColorCyan => '湖青';

  @override
  String get themeColorEmerald => '翡翠';

  @override
  String get themeColorLime => '青柠';

  @override
  String get themeColorAmber => '琥珀';

  @override
  String get themeColorCoral => '珊瑚';

  @override
  String get themeColorCustom => '自定';

  @override
  String get themeVariantTonalSpot => '柔和';

  @override
  String get themeVariantTonalSpotDesc => 'Material 默认风格，低饱和、耐看。';

  @override
  String get themeVariantVibrant => '鲜明';

  @override
  String get themeVariantVibrantDesc => '提高主色饱和度，整体更醒目。';

  @override
  String get themeVariantExpressive => '表现';

  @override
  String get themeVariantExpressiveDesc => '会偏移主色相，风格更有个性。';

  @override
  String get themeVariantFidelity => '准确';

  @override
  String get themeVariantFidelityDesc => '尽量贴近所选主色的原始观感。';

  @override
  String get themeVariantContent => '内容';

  @override
  String get themeVariantContentDesc => '容器颜色更贴近主色，强调层次。';

  @override
  String get themeVariantNeutral => '中性';

  @override
  String get themeVariantNeutralDesc => '接近灰阶，适合更克制的界面。';

  @override
  String get themeVariantMonochrome => '黑白';

  @override
  String get themeVariantMonochromeDesc => '完全灰阶，只保留明暗关系。';

  @override
  String get themeVariantRainbow => '彩虹';

  @override
  String get themeVariantRainbowDesc => '跳脱主色限制，整体更活泼。';

  @override
  String get appLogEmpty => '暂无错误日志';

  @override
  String get appLogCopied => '日志已复制到剪贴板';

  @override
  String appLogCopyFailed(String error) {
    return '复制失败：$error';
  }

  @override
  String get appLogClearTitle => '清空错误日志';

  @override
  String get appLogClearContent => '确定要删除本地保存的错误日志吗？';

  @override
  String get appLogCleared => '错误日志已清空';

  @override
  String appLogClearFailed(String error) {
    return '清空失败：$error';
  }

  @override
  String get settingsTooltip => '设置';

  @override
  String get appLogSettingsTitle => '日志设置';

  @override
  String get appLogRecordLogs => '记录日志';

  @override
  String get appLogLevel => '日志级别';

  @override
  String get appLogLevelDebug => '调试';

  @override
  String get appLogLevelInfo => '信息';

  @override
  String get appLogLevelWarning => '警告';

  @override
  String get appLogLevelError => '错误';

  @override
  String get appLogSearchHint => '搜索日志（消息、来源、堆栈、上下文）';

  @override
  String get appLogClearLogsTooltip => '清空日志';

  @override
  String get appLogAllLevels => '全部';

  @override
  String get appLogCopyThisLogTooltip => '复制此日志';

  @override
  String get appLogContextTitle => '上下文';

  @override
  String get appLogStackTitle => '堆栈';

  @override
  String get relativeTimeJustNow => '刚刚';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    return '$minutes分钟前';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    return '$hours小时前';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    return '$days天前';
  }

  @override
  String relativeTimeMonthsAgo(int months) {
    return '$months个月前';
  }

  @override
  String relativeTimeYearsAgo(int years) {
    return '$years年前';
  }

  @override
  String get comicDetailCommentsUnavailable => '当前漫画暂时无法查看评论';

  @override
  String get comicDetailAuthorUnavailable => '当前作者暂时无法查看作品';

  @override
  String get comicDetailThemeUnavailable => '当前主题暂时无法查看作品';

  @override
  String get comicDetailSelectUndownloadedChapters => '请选择未下载的章节';

  @override
  String comicDetailAddedToDownloadQueue(int count) {
    return '已加入下载队列：$count 章（顺序下载）';
  }

  @override
  String get comicDetailSelectedAlreadyDownloadedOrQueued => '所选章节已下载或已在队列中';

  @override
  String comicDetailSelectedChapters(int count) {
    return '已选 $count 章';
  }

  @override
  String comicDetailSequentialDownloading(int count) {
    return '顺序下载中 $count 章';
  }

  @override
  String get downloadedStatus => '已下载';

  @override
  String comicDetailDownloadProgress(int completed, int total) {
    return '下载 $completed/$total';
  }

  @override
  String get comicDetailQueued => '排队中';

  @override
  String get processingStatus => '处理中';

  @override
  String comicDetailReadWithStatus(String status) {
    return '已读 · $status';
  }

  @override
  String get collectButton => '收藏';

  @override
  String get downloadQueueTab => '队列';

  @override
  String get downloadQueueEmpty => '下载队列为空';

  @override
  String get downloadQueueEmptyComicHint => '去漫画详情页添加下载任务';

  @override
  String get downloadQueueEmptyMixedHint => '去漫画或动漫详情页添加下载任务';

  @override
  String downloadProgressApproxBytes(String percent, String size) {
    return '$percent% · 约 $size';
  }

  @override
  String get downloadingStatus => '下载中';

  @override
  String get waitingStatus => '等待中';

  @override
  String get pausedStatus => '已暂停';

  @override
  String get downloadFailedStatus => '下载失败';

  @override
  String get animeDownloadConnectionTimeout => '连接超时';

  @override
  String get animeDownloadProxyRetrySuggestion => '建议开启代理后重试';

  @override
  String get animeDownloadUnknownError => '未知错误';

  @override
  String animeDownloadFailedMessage(String chapter, String error) {
    return '$chapter 下载失败：$error';
  }

  @override
  String get animeDownloadEmptyVideoUrl => '视频链接为空';

  @override
  String get pauseButton => '暂停';

  @override
  String get resumeButton => '继续';

  @override
  String downloadProgressCount(String percent, int completed, int total) {
    return '$percent% ($completed/$total)';
  }

  @override
  String get commentSettingsAiSummarySection => 'AI 总结';

  @override
  String get commentSettingsEnableAiSummary => '启用 AI 总结';

  @override
  String get commentSettingsAiSummaryEnabledDesc => '评论顶部显示 AI 总结按钮';

  @override
  String get commentSettingsAiSummaryDisabled => '未启用';

  @override
  String get commentSettingsConfigureAiFirst => '请先在「我的 → AI配置」中配置 API 密钥';

  @override
  String get commentSettingsCollapseAiComment => '折叠 AI 评论';

  @override
  String get commentSettingsCollapseAiCommentDesc => '开启后 AI 评论默认折叠，生成中也保持折叠';

  @override
  String get commentSettingsAutoAiSummary => '自动 AI 总结';

  @override
  String commentSettingsAutoAiSummaryDesc(int count) {
    return '评论数 ≥ $count 条时自动生成';
  }

  @override
  String get commentSettingsMinCommentCount => '最少评论数';

  @override
  String get commentSettingsTriggerTiming => '调用时机';

  @override
  String get commentSettingsTimingOnOpen => '打开评论区时';

  @override
  String get commentSettingsTimingAfterPreload => '预加载完成后';

  @override
  String get commentSettingsPreloadRequiredForTiming => '选择“预加载完成后”需要先开启预加载评论。';

  @override
  String get commentSettingsSpoilerAnalysis => '剧透分析';

  @override
  String get commentSettingsSpoilerAnalysisDesc => '开启后会在当前提示词后自动追加剧透分析要求';

  @override
  String get commentSettingsSpoilerWarn => '打开剧透评论弹出提醒';

  @override
  String get commentSettingsPromptPresets => '提示词预设';

  @override
  String get commentSettingsBlacklistSection => '黑名单';

  @override
  String get commentSettingsBlacklistDesc => '长按评论可选择「屏蔽用户」，被屏蔽的评论将不再显示。';

  @override
  String get commentSettingsClearBlacklist => '清空黑名单';

  @override
  String get commentSettingsAnonymousUser => '匿名用户';

  @override
  String get commentSettingsRemoveFromBlacklist => '移出黑名单';

  @override
  String get profileFallbackQuestionWife => '我的老婆叫什麼？';

  @override
  String get profileFallbackQuestionFriend => '我的基友叫啥？';

  @override
  String get profileFallbackQuestionBestFriendCount => '我的好麻吉有幾個？';

  @override
  String get profileFallbackQuestionParentName => '我的父親(母親)叫什麽？';

  @override
  String get animeDetailSubtitleChip => '字幕';

  @override
  String animeDetailLatestChapter(String chapter) {
    return '最新：$chapter';
  }

  @override
  String get animeDetailOnAirChip => '连载中';

  @override
  String get animeDetailRestrictedChip => '受限';

  @override
  String animeDetailDirector(String name) {
    return '导演：$name';
  }

  @override
  String get playerSettingsPlaybackTitle => '播放设置';

  @override
  String get playerSettingsSkipSeconds => '快进秒数';

  @override
  String get playerSettingsSkipSecondsDesc => '动漫片头一般约90秒';

  @override
  String get playerSettingsSecondsLabel => '秒数';

  @override
  String get readerSecondsSuffix => '秒';

  @override
  String get playerSettingsRecordProgress => '记录播放进度';

  @override
  String get playerSettingsRecordProgressDesc => '再次打开同一集时自动跳转到上次观看位置';

  @override
  String get playerSettingsDanmakuTitle => '弹幕设置';

  @override
  String get playerSettingsShowDanmaku => '显示弹幕';

  @override
  String get playerSettingsFontSize => '字体大小';

  @override
  String get playerSettingsDisplayArea => '显示区域';

  @override
  String get playerSettingsOpacity => '透明度';

  @override
  String get playerSettingsDanmakuType => '弹幕类型';

  @override
  String get playerSettingsScrollDanmaku => '滚动弹幕';

  @override
  String get playerSettingsTopDanmaku => '顶部弹幕';

  @override
  String get playerSettingsBottomDanmaku => '底部弹幕';

  @override
  String get playerSettingsBlocklist => '屏蔽词';

  @override
  String get playerSettingsBlocklistDesc => '包含屏蔽词的弹幕将被自动过滤';

  @override
  String get playerSettingsBlocklistHint => '输入屏蔽词';

  @override
  String get playerSettingsDanmakuFont => '弹幕字体';

  @override
  String get playerSettingsDanmakuFontSystem => '跟随系统';

  @override
  String get playerSettingsChineseConvertTooltip => '简繁转换';

  @override
  String get readerImageLinksRefreshed => '图片链接已刷新';

  @override
  String refreshFailedWithError(String error) {
    return '刷新失败：$error';
  }

  @override
  String get readerLocalChapterNoRefresh => '本地章节无需刷新';

  @override
  String readerAutoSummaryFailed(String error) {
    return '后台自动总结失败：$error';
  }

  @override
  String get readerNoPreviousChapter => '当前已无上一话';

  @override
  String get readerPreviousChapter => '上一章';

  @override
  String get readerPauseAutoScroll => '暂停自动滚动';

  @override
  String get readerAutoScrollWillResume => '自动滚动即将恢复';

  @override
  String get readerEnableAutoScroll => '开启自动滚动';

  @override
  String get readerLoadingNextChapter => '正在加载下一话…';

  @override
  String get readerContinueScrollLoadNext => '继续滚动加载下一话';

  @override
  String get readerAlreadyFirstChapter => '已经是第一章';

  @override
  String get readerContinuePageNextChapter => '继续翻页进入下一话';

  @override
  String get readerAlreadyLastChapter => '已经是最后一话';

  @override
  String get readerContinueScrollOrTapNextChapter => '继续下滑或点击按钮进入下一话';

  @override
  String get readerImagePathCopied => '图片路径已复制到剪贴板';

  @override
  String get readerImageUrlCopied => '图片链接已复制到剪贴板';

  @override
  String get readerLocalImageMissing => '本地图片损坏或缺失';

  @override
  String get readerCopyImagePath => '复制图片路径';

  @override
  String readerImageRetrying(int attempt, int total) {
    return '加载失败，正在重试 $attempt/$total';
  }

  @override
  String get readerReloadImage => '重新加载';

  @override
  String get readerCopyImageUrl => '复制图片链接';

  @override
  String get updateAlreadyLatest => '当前已是最新版本';

  @override
  String get updateCheckFailedRetryLater => '检查更新失败，请稍后重试';

  @override
  String get updateOpenDownloadFailed => '无法打开下载链接';

  @override
  String get updateNoReleaseNotes => '暂无更新说明';

  @override
  String get updateMirrorDownload => '镜像下载';

  @override
  String get updateLatestBadge => '最新';

  @override
  String get updateCollapseOtherVersions => '收起其他版本';

  @override
  String updateViewMoreVersions(int count) {
    return '查看更多版本 ($count)';
  }

  @override
  String get updateCiBuildUnstable => 'CI 自动构建版本，不保证稳定性。';

  @override
  String get updateOpenReleasePage => '打开发布页';

  @override
  String get updatePackagesBeta => '安装包（按版本号倒序）';

  @override
  String get updatePackages => '安装包';

  @override
  String get updateSkipVersion => '跳过此版本';

  @override
  String get updateDisableAutoCheck => '取消自动检查更新';

  @override
  String get updateInstallInApp => '应用内安装';

  @override
  String get updateInstallInAppMirror => '镜像应用内安装';

  @override
  String updateDownloading(int percent) {
    return '下载中 $percent%';
  }

  @override
  String get updateDownloadFailed => '下载失败，请稍后重试';

  @override
  String get updateInstallFailed => '无法启动安装，请改用浏览器下载';

  @override
  String get updateInstallPermissionNeeded => '需要「安装未知应用」权限才能安装更新';

  @override
  String get updateDownloadPreparing => '准备下载…';

  @override
  String get updateInstalling => '正在安装…';

  @override
  String get updateCardChecking => '正在检查更新…';

  @override
  String get updateCardLatest => '当前已是最新版本';

  @override
  String get updateCardFailed => '检查更新失败，点击重试';

  @override
  String get updateCardRetry => '重试';

  @override
  String get updateButtonUpdate => '更新';

  @override
  String get updateManualDownload => '手动下载';

  @override
  String get updateUseMirror => '使用镜像';

  @override
  String get totalRank => '总榜';

  @override
  String get maleAudience => '男生';

  @override
  String get femaleAudience => '女生';

  @override
  String get noticeRefreshFailed => '刷新通知失败，请稍后重试';

  @override
  String get noticeReadFailed => '读取通知失败';

  @override
  String get noticeAllMarkedRead => '所有通知已标记为已读';

  @override
  String get noticeMarkAllReadTooltip => '全部已读';

  @override
  String get noticeRefreshTooltip => '刷新通知';

  @override
  String get noticeEmptyTitle => '暂无通知';

  @override
  String get noticeExpiredTitle => '过期通知';

  @override
  String get noticePinnedNodeSemantics => '置顶通知节点';

  @override
  String get noticeNodeSemantics => '通知节点';

  @override
  String get noticeOpenLink => '打开链接';

  @override
  String get noticeUnreadSemantics => '未读通知';

  @override
  String get noticeExpiredBadge => '已过期';

  @override
  String get readerImageViewerSettingsTooltip => '查看器设置';

  @override
  String get resetButton => '重置';

  @override
  String get readerRotateLeft => '向左旋转';

  @override
  String get readerRotateRight => '向右旋转';

  @override
  String get readerImageViewerSettingsTitle => '图片查看器设置';

  @override
  String get readerAutoRotateLandscape => '横向图片自动旋转';

  @override
  String get readerAutoRotateLandscapeDesc => '打开宽图时自动旋转 90 度';

  @override
  String get readerRotationDirection => '旋转方向';

  @override
  String get readerRotateLeftShort => '向左';

  @override
  String get readerRotateRightShort => '向右';

  @override
  String get browseHistoryLastSeenLabel => '上次看到';

  @override
  String playerProgressAutoResumed(String progress) {
    return '$progress（已自动继续）';
  }

  @override
  String get playerSeekButton => '跳转';

  @override
  String get bangumiCommentsLoadFailed => '评论加载失败';

  @override
  String get bangumiCommentsRetryHint => '下拉或点按钮重试';

  @override
  String get bangumiCommentsEmptyTitle => '还没有评论';

  @override
  String get bangumiCommentsEmptySubtitle => '暂时没有可显示的 Bangumi 评论';

  @override
  String get bangumiCommentsLoadMoreFailed => '更多评论加载失败';

  @override
  String get bangumiCommentsRetryLoadMore => '重试加载更多';

  @override
  String get bangumiCommentsLoadMore => '加载更多';

  @override
  String get bangumiCommentsEmptyComment => '这条评论没有内容';

  @override
  String get danmakuSearchTitle => '弹幕搜索';

  @override
  String danmakuSearchTitleWithCount(int count) {
    return '弹幕搜索（$count）';
  }

  @override
  String danmakuLoadedTitle(int count) {
    return '已装载$count发弹幕';
  }

  @override
  String get danmakuSearchHint => '输入搜索关键词';

  @override
  String get forceRefreshTooltip => '强制刷新';

  @override
  String get danmakuSearchInstruction => '请选择分段或输入搜索词后点击搜索';

  @override
  String danmakuSearchResultCount(int count) {
    return '共找到 $count 条结果';
  }

  @override
  String get danmakuSearchNoResults => '未找到相关弹幕';

  @override
  String get danmakuSearchNoResultsHint =>
      '减少关键词，仅搜索作品名称\n如：「Re：从零开始的异世界生活第四季丧失篇」搜索「从零开始的异世界生活第四季」';

  @override
  String get danmakuLabel => '弹幕';

  @override
  String get dandanplayBindingSearchKeyword => '搜索关键词';

  @override
  String get dandanplayBindingClear => '清除绑定';

  @override
  String dandanplayBindingSearchFailed(String error) {
    return '搜索失败：$error';
  }

  @override
  String get dandanplayBindingNoResults => '未找到相关番剧';

  @override
  String get dandanplayBindingSearchInstruction => '输入关键词后点击搜索';

  @override
  String get dandanplayBindingCurrent => '当前绑定';

  @override
  String get dandanplayBindingBound => '已绑定';

  @override
  String get dandanplayBindingUnbound => '未绑定';

  @override
  String get dandanplayBindingBind => '绑定';

  @override
  String dandanplayBindingRating(String rating) {
    return '评分 $rating';
  }

  @override
  String get dandanplayAlignmentTitle => '对齐弹幕';

  @override
  String get dandanplayAlignmentVideoFirstEpisode => '视频第一集';

  @override
  String get dandanplayAlignmentDanmakuFirstEpisode => '弹幕第一集';

  @override
  String get dandanplayAlignmentClear => '清除对齐';

  @override
  String get spoilerWarningTitle => '剧透警告';

  @override
  String get spoilerWarningContent => '真的要打开吗？前方是地狱啊！';

  @override
  String get openButton => '打开';

  @override
  String get spoilerSuspectedComment => '这是一条高度剧透嫌疑的评论';

  @override
  String get spoilerTapToView => '含剧透，点击查看';

  @override
  String get mediaKitDownloadTitle => '需要下载播放组件';

  @override
  String mediaKitDownloadMessage(String size) {
    return '首次使用动漫播放功能需下载播放组件（$size）。下载后会保存在本地，软件更新无需重新下载。';
  }

  @override
  String get mediaKitDownloadSourceLabel => '下载来源';

  @override
  String get mediaKitDownloadSourceGithub => 'GitHub';

  @override
  String get mediaKitDownloadSourceGithubHint => '直连 GitHub 官方资源';

  @override
  String get mediaKitDownloadSourceMirror => '镜像下载';

  @override
  String mediaKitDownloadSourceMirrorHint(String mirror) {
    return '使用当前镜像：$mirror';
  }

  @override
  String get mediaKitDownloadConfirm => '开始下载';

  @override
  String get mediaKitDownloadingTitle => '正在下载播放组件';

  @override
  String get mediaKitDownloadFailedTitle => '下载失败';

  @override
  String mediaKitDownloadFailed(String error) {
    return '下载播放组件失败：$error';
  }

  @override
  String mediaKitInitFailed(String error) {
    return '播放器初始化失败：$error';
  }

  @override
  String get mediaKitDownloadStageConnect => '正在连接…';

  @override
  String mediaKitDownloadBytesProgress(String received, String total) {
    return '$received / $total';
  }

  @override
  String mediaKitDownloadBytesOnly(String received) {
    return '已下载 $received';
  }

  @override
  String get mediaKitDownloadTimeout => '连接或下载超时，请切换 GitHub/镜像后重试';

  @override
  String get mediaKitDownloadNetworkError => '网络连接失败，请检查网络或切换下载来源';

  @override
  String get mediaKitDownloadStagePrepare => '准备中…';

  @override
  String get mediaKitDownloadStageDownload => '正在下载…';

  @override
  String get mediaKitDownloadStageVerify => '校验文件…';

  @override
  String get mediaKitDownloadStageExtract => '解压组件…';

  @override
  String get mediaKitDownloadStageLoad => '加载组件…';

  @override
  String get mediaKitDownloadStageDone => '完成';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'Kira';

  @override
  String get comicTabLabel => '漫畫';

  @override
  String get animeTabLabel => '動漫';

  @override
  String get searchTabLabel => '搜尋';

  @override
  String get bookshelfTabLabel => '書架';

  @override
  String get profileTabLabel => '我的';

  @override
  String get disclaimerTitle => '免責聲明';

  @override
  String get disclaimerAgreeNote =>
      '繼續使用本應用，即表示您已閱讀、理解並同意上述說明；如您不同意，請立即停止使用並退出本應用。';

  @override
  String get disclaimerConfirmAgeAndTerms => '我已年滿 18 歲，並已仔細閱讀、充分理解且同意上述全部條款';

  @override
  String get disagreeAndExit => '不同意並退出';

  @override
  String get confirmButton => '確認';

  @override
  String get cancelButton => '取消';

  @override
  String get deleteButton => '刪除';

  @override
  String get loadingFailed => '載入失敗';

  @override
  String get retryButton => '重試';

  @override
  String get noContent => '暫無內容';

  @override
  String get hotRecommend => '熱門推薦';

  @override
  String get comicRanking => '漫畫排行';

  @override
  String get rankingAuthorWorks => '作者作品';

  @override
  String get rankingThemeWorks => '主題作品';

  @override
  String get rankingNoAuthorWorks => '暫無作者作品';

  @override
  String get rankingNoThemeWorks => '暫無主題作品';

  @override
  String get rankingNoComics => '暫無漫畫';

  @override
  String get moreButton => '更多';

  @override
  String get dayRank => '日榜';

  @override
  String get weekRank => '週榜';

  @override
  String get monthRank => '月榜';

  @override
  String get copyRecommend => '推薦';

  @override
  String get copyRanking => '排行榜';

  @override
  String get copyHotUpdate => '熱門更新';

  @override
  String get copyNewArrival => '全新上架';

  @override
  String get copyFinished => '已完結';

  @override
  String get switchToHotHome => '切換到 HOT 首頁';

  @override
  String get switchToCopyHome => '切換到 COPY 首頁';

  @override
  String get homeSourceHot => '熱辣';

  @override
  String get homeSourceCopy => '拷貝';

  @override
  String get localComicsTitle => '本地漫畫';

  @override
  String get noLocalComicsTitle => '還沒有本地漫畫';

  @override
  String get noLocalComicsSubtitle => '去漫畫詳情頁下載章節後，這裡會顯示離線內容';

  @override
  String get deleteLocalComicsTitle => '刪除本地漫畫';

  @override
  String deleteLocalComicsContent(int count) {
    return '確定刪除選中的 $count 部本地漫畫嗎？已下載章節和封面都會被刪除。';
  }

  @override
  String deletedLocalComicsCount(int count) {
    return '已刪除 $count 部本地漫畫';
  }

  @override
  String get localAnimeTitle => '本地動漫';

  @override
  String get noLocalAnimeTitle => '還沒有本地動漫';

  @override
  String get noLocalAnimeSubtitle => '去動漫詳情頁下載劇集後，這裡會顯示離線內容';

  @override
  String get deleteLocalAnimeTitle => '刪除本地動漫';

  @override
  String deleteLocalAnimeContent(int count) {
    return '確定刪除選中的 $count 部本地動漫嗎？已下載影片和封面都會被刪除。';
  }

  @override
  String deletedLocalAnimeCount(int count) {
    return '已刪除 $count 部本地動漫';
  }

  @override
  String selectedCount(int count, String unit) {
    return '已選 $count $unit';
  }

  @override
  String selectedItems(int count) {
    return '已選 $count 部';
  }

  @override
  String downloadedChapterCount(int count) {
    return '已下載 $count 章';
  }

  @override
  String downloadedEpisodeCount(int count) {
    return '已下載 $count 集';
  }

  @override
  String downloadedCountUnit(int count, String unit) {
    return '已下載 $count $unit';
  }

  @override
  String localChaptersTitle(int count) {
    return '本地章節 ($count)';
  }

  @override
  String localEpisodesTitle(int count) {
    return '本地劇集 ($count)';
  }

  @override
  String get deleteLocalChaptersTitle => '刪除本地章節';

  @override
  String deleteChaptersConfirm(int count) {
    return '確定刪除選中的 $count 個章節嗎？';
  }

  @override
  String deletedChaptersCount(int count) {
    return '已刪除 $count 個章節';
  }

  @override
  String get deleteLocalEpisodesTitle => '刪除本地劇集';

  @override
  String deleteEpisodesConfirm(int count) {
    return '確定刪除選中的 $count 個劇集嗎？';
  }

  @override
  String deletedEpisodesCount(int count) {
    return '已刪除 $count 個劇集';
  }

  @override
  String get viewOnlineDetail => '檢視線上詳情';

  @override
  String get manageChapters => '管理章節';

  @override
  String get manageEpisodes => '管理劇集';

  @override
  String get selectAll => '全選';

  @override
  String get sortReverse => '逆序（新→舊）';

  @override
  String get sortNormal => '正序（舊→新）';

  @override
  String get readMark => '已讀';

  @override
  String get videoFileNotFound => '影片檔案不存在';

  @override
  String get openDownloadFolder => '開啟下載位置';

  @override
  String get batchManage => '批量管理';

  @override
  String get comicLabel => '漫畫';

  @override
  String get animeLabel => '動漫';

  @override
  String comicWithCount(int count) {
    return '漫畫（$count）';
  }

  @override
  String animeWithCount(int count) {
    return '動漫（$count）';
  }

  @override
  String get hasUpdate => '有更新';

  @override
  String get updateBadge => '更新';

  @override
  String refreshedAt(String time) {
    return '重新整理於 $time';
  }

  @override
  String get sortByUpdate => '按更新';

  @override
  String get sortByFavorite => '按收藏';

  @override
  String get sortByRead => '按閱讀';

  @override
  String get sortLabel => '排序';

  @override
  String get sortMethod => '排序方式';

  @override
  String get sortByUpdateTime => '作品更新時間';

  @override
  String sortByUpdateTimeDesc(String type) {
    return '按$type最新章節的更新時間排序';
  }

  @override
  String get sortByFavoriteTime => '收藏時間';

  @override
  String get sortByFavoriteTimeDesc => '按加入書架的時間排序';

  @override
  String get sortByBrowseTime => '瀏覽時間';

  @override
  String get sortByBrowseTimeDesc => '按最近瀏覽的時間排序';

  @override
  String get bookshelfEmpty => '書架空空如也';

  @override
  String goFindSomething(String type) {
    return '去找點好看的$type吧';
  }

  @override
  String get refreshButton => '重新整理';

  @override
  String get noComicUpdates => '沒有漫畫更新';

  @override
  String get backToTop => '回到頂部';

  @override
  String get refreshSuccess => '重新整理成功';

  @override
  String get refreshFailed => '重新整理失敗';

  @override
  String get loginExpiredTitle => '登入已過期';

  @override
  String get loginExpiredBookshelfContent => '書架需要登入後才能繼續使用，是否現在重新登入？';

  @override
  String loginExpiredFeatureContent(String featureName) {
    return '$featureName需要登入後才能繼續使用，是否現在重新登入？';
  }

  @override
  String get laterButton => '稍後再說';

  @override
  String get goLoginButton => '去登入';

  @override
  String get autoLoginFailed => '自動登入失敗，請手動重新登入';

  @override
  String get loginToViewBookshelf => '登入後可繼續檢視書架';

  @override
  String totalEpisodes(int count) {
    return '共 $count 集';
  }

  @override
  String searchHint(String mode) {
    return '搜尋$mode...';
  }

  @override
  String get hotSearchTitle => '熱門搜尋';

  @override
  String get allTagsTitle => '全部標籤';

  @override
  String tagCount(int count) {
    return '$count 個';
  }

  @override
  String get popularOrder => '熱度';

  @override
  String get updateOrder => '更新';

  @override
  String searchResultSummary(String query, int total, String mode) {
    return '搜尋 \"$query\" 找到 $total 個$mode結果';
  }

  @override
  String openFolderFailed(String error) {
    return '開啟資料夾失敗：$error';
  }

  @override
  String get deleteToastPrefix => '已刪除 ';

  @override
  String get deleteToastSuffixComic => ' 部本地漫畫';

  @override
  String get deleteToastSuffixAnime => ' 部本地動漫';

  @override
  String get chapterUnit => '章';

  @override
  String get episodeUnit => '集';

  @override
  String get generalTitle => '通用';

  @override
  String get autoLoginTitle => '自動登入';

  @override
  String get autoLoginEnabledDesc => '登入過期時自動重新登入';

  @override
  String get autoLoginUnavailableDesc => '登入並儲存帳號密碼後可用';

  @override
  String get animeFeatureTitle => '動漫功能';

  @override
  String get animeFeatureDesc => '關閉後隱藏動漫相關功能';

  @override
  String get remoteNoticeTitle => '通知';

  @override
  String get remoteNoticeDesc => '開啟後應用啟動時自動檢查通知；關閉後僅在進入通知中心時獲取';

  @override
  String get noticeSettingsTooltip => '通知設定';

  @override
  String get bannerVisibleTitle => '顯示 Banner';

  @override
  String get bannerVisibleDesc => '關閉後漫畫和動漫首頁頂部 Banner 不顯示';

  @override
  String get languageTitle => '語言';

  @override
  String get languageSimplifiedSystem => '簡體中文（跟隨系統）';

  @override
  String get languageTraditional => '繁體中文';

  @override
  String get cacheManagementTitle => '快取管理';

  @override
  String get cacheManagementDesc => '檢視和刪除本地快取、歷史和帳號資料';

  @override
  String get exportSettingsTitle => '匯出設定';

  @override
  String get exportSettingsDesc => '複製設定到剪貼簿';

  @override
  String get importSettingsTitle => '匯入設定';

  @override
  String get importSettingsDesc => '貼上匯入設定';

  @override
  String get settingsCopiedWithSensitive => '設定已複製，包含敏感資訊';

  @override
  String get settingsCopiedWithoutSensitive => '設定已複製，未包含敏感資訊';

  @override
  String exportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String get noImportSettingsContent => '沒有可匯入的設定內容';

  @override
  String get settingsBackupEmptyClipboard => '剪貼簿裡沒有可匯入的設定';

  @override
  String get settingsBackupInvalidJson => '設定格式不是有效的 JSON';

  @override
  String get settingsBackupInvalidFormat => '設定格式不正確';

  @override
  String get settingsBackupWrongApp => '這不是 Kira 的設定備份';

  @override
  String get settingsBackupUnsupportedVersion => '備份版本不受支援';

  @override
  String get settingsBackupMissingContent => '設定內容缺失或格式不正確';

  @override
  String get settingsBackupUnsupportedField => '設定中包含不支援的欄位';

  @override
  String get settingsBackupInvalidFieldFormat => '設定欄位格式不正確';

  @override
  String get settingsBackupUnsupportedFieldType => '設定欄位類型不受支援';

  @override
  String importFailed(String error) {
    return '匯入失敗：$error';
  }

  @override
  String get overwriteImportTitle => '覆蓋匯入';

  @override
  String overwriteImportContent(int count, String backupTime) {
    return '將覆蓋目前 $count 項持久化設定，包含帳號、主題、閱讀器設定和本地閱讀記錄。$backupTime\n\n臨時快取不會匯入，目前設定會被取代。是否繼續？';
  }

  @override
  String backupTimeLine(String time) {
    return '\n\n備份時間：$time';
  }

  @override
  String get confirmImportButton => '確認匯入';

  @override
  String get settingsImportedToast => '設定已匯入並覆蓋本地設定';

  @override
  String get resetAppTitle => '重設應用';

  @override
  String get resetAppDesc => '清除本地設定、帳號、閱讀記錄和快取，不會刪除已下載的本地漫畫檔案';

  @override
  String get resettingApp => '正在重設...';

  @override
  String appResetToast(int count) {
    return '應用已重設，已清除 $count 項本地資料';
  }

  @override
  String resetFailed(String error) {
    return '重設失敗：$error';
  }

  @override
  String exportSettingsContent(int count) {
    return '將複製 $count 項持久化設定到剪貼簿，匯出內容為明文，請謹慎保管。';
  }

  @override
  String get includeSensitiveSettingsTitle => '包含密碼和 API 重要資訊';

  @override
  String get noSensitiveSettingsFound => '目前沒有偵測到已儲存的敏感項';

  @override
  String includeSensitiveSettingsDesc(int count) {
    return '將額外包含 $count 項權杖、密碼、API Key 或憑證資訊';
  }

  @override
  String get copyButton => '複製';

  @override
  String get pasteExportedSettingsHint => '貼上匯出的設定 JSON';

  @override
  String get continueButton => '繼續';

  @override
  String get confirmResetAppTitle => '確認重設應用';

  @override
  String get resetAppWarning => '此操作會清除應用本地儲存的設定、帳號、閱讀記錄和快取，且無法復原。';

  @override
  String resetAppInstruction(String text) {
    return '如需繼續，請在下方輸入框中輸入「$text」。';
  }

  @override
  String get confirmTextLabel => '確認文字';

  @override
  String get confirmResetButton => '確認重設';

  @override
  String get animeUnavailableToast => '目前動漫暫時無法開啟';

  @override
  String get animeEditorRecommend => '編輯推薦';

  @override
  String get animeRecentUpdate => '最近更新';

  @override
  String get animeClassicRecommend => '經典推薦';

  @override
  String get animeClassicAnimation => '經典動畫';

  @override
  String get animeHotAnime => '熱門動漫';

  @override
  String get loginRequiredTitle => '需要登入';

  @override
  String get playbackFailedTitle => '播放失敗';

  @override
  String get viewLogButton => '檢視日誌';

  @override
  String get errorLogTitle => '錯誤日誌';

  @override
  String get noLogInfo => '無日誌資訊';

  @override
  String get closeButton => '關閉';

  @override
  String get videoLinkTitle => '影片連結';

  @override
  String get videoLinkPending => '載入後顯示影片連結';

  @override
  String get copyVideoLinkButton => '複製影片連結';

  @override
  String get openInBrowserButton => '瀏覽器開啟';

  @override
  String get switchLineTooltip => '切換線路';

  @override
  String get profileCopyCredentialLabel => '拷貝';

  @override
  String get profileHotCredentialLabel => '熱辣';

  @override
  String get accountSwitchedToast => '帳號已切換';

  @override
  String get switchAccountTitle => '切換帳號';

  @override
  String get addAccountButton => '新增帳號';

  @override
  String get switchAccountFailedToast => '切換失敗，請重試';

  @override
  String get logoutTitle => '登出';

  @override
  String get logoutConfirmContent => '確定要登出嗎？';

  @override
  String get userInfoRefreshedToast => '使用者資訊已重新整理';

  @override
  String get userInfoRefreshFailedToast => '重新整理失敗，請重試';

  @override
  String get tokenUnavailableToast => '暫無可複製的權杖';

  @override
  String get tokenCopiedToast => '權杖已複製到剪貼簿';

  @override
  String get appearanceTitle => '外觀';

  @override
  String get appearanceLogoChanged => '桌面圖示已更換，可能需要重啟應用後生效';

  @override
  String get appearanceColorPickerHeading => '點擊色盤選擇一個自訂主題色';

  @override
  String get appearanceColorPickerSubheading => '拖動取色點，即時預覽主題色';

  @override
  String appearanceThemeColorUpdated(String color) {
    return '主題配色已更新為 $color';
  }

  @override
  String get appearanceBottomNavShowLabels => '底部導覽列顯示文字';

  @override
  String get appearanceBottomNavLabelMode => '底部導覽列文字';

  @override
  String get appearanceBottomNavLabelModeSelectedOnly => '選中時顯示';

  @override
  String get appearanceBottomNavLabelModeSelectedOnlyDesc => '膠囊導覽，僅選中項顯示文字';

  @override
  String get appearanceBottomNavLabelModeHidden => '不顯示文字';

  @override
  String get appearanceBottomNavLabelModeHiddenDesc => '膠囊導覽，只顯示圖示';

  @override
  String get appearanceBottomNavLabelModeAlways => '始終顯示文字';

  @override
  String get appearanceBottomNavLabelModeAlwaysDesc => '經典導覽，文字顯示在圖示下方';

  @override
  String get appearanceNavOrder => '導覽列順序';

  @override
  String get appearanceNavOrderDragHint => '長按可拖放排序';

  @override
  String get appearanceAppIcon => '應用圖示';

  @override
  String get appearanceAppIconRestartHint => '更換後重啟應用生效';

  @override
  String get appearanceRefreshRateTitle => '螢幕重新整理率';

  @override
  String get appearanceThemeMode => '主題模式';

  @override
  String get appearanceSystemMode => '系統';

  @override
  String get appearanceLightMode => '淺色';

  @override
  String get appearanceDarkMode => '深色';

  @override
  String get appearanceDarkCoverBrightness => '暗色模式封面亮度';

  @override
  String get appearanceDarkCoverBrightnessDesc => '暗色模式下降低各個介面的卡片封面亮度';

  @override
  String get appearanceThemeStyle => '主題風格';

  @override
  String appearanceCurrentStyle(String label, String description) {
    return '目前風格：$label · $description';
  }

  @override
  String get appearanceThemeColor => '主題配色';

  @override
  String get appearanceThemeColorDesc => '點擊色塊切換主題色，帶勾選的為目前配色。';

  @override
  String appearanceRefreshRateRequested(String rate) {
    return '已請求重新整理率 $rate';
  }

  @override
  String get appearanceRefreshRateSaved => '重新整理率偏好已儲存';

  @override
  String appearanceRefreshRateLoadFailed(String error) {
    return '獲取裝置重新整理率失敗：$error';
  }

  @override
  String get appearanceUnknownError => '未知錯誤';

  @override
  String get appearanceAutoSystem => '自動（跟隨系統）';

  @override
  String appearanceRefreshRateCurrent(int rate) {
    return '${rate}Hz（目前）';
  }

  @override
  String appearanceApplyingRefreshRate(String rate) {
    return '正在套用 $rate';
  }

  @override
  String get appearanceRefreshRateDesc => '實際生效取決於系統和螢幕，部分裝置可能需要重啟應用後完全生效。';

  @override
  String get appearanceDefaultFontRestored => '已恢復系統預設字型，重啟應用後完全生效';

  @override
  String appearanceFontChanged(String font) {
    return '字型已切換為 $font';
  }

  @override
  String appearanceFontLoadFailed(String error) {
    return '載入字型失敗：$error';
  }

  @override
  String get appearanceAppFont => '應用字型';

  @override
  String get appearanceSystemDefault => '系統預設';

  @override
  String get appearanceChooseFont => '選擇字型';

  @override
  String get appearanceSearchFont => '搜尋字型';

  @override
  String get appearanceFontDeleteTitle => '刪除字型';

  @override
  String appearanceFontDeleteContent(String fontId) {
    return '確定要刪除字型 $fontId 嗎？刪除後將恢復為系統預設字型。';
  }

  @override
  String get appearanceFontNeedDownload => '請先下載字型後再使用';

  @override
  String appearanceFontDownloaded(String fontId) {
    return '$fontId 下載完成';
  }

  @override
  String get appearanceFontDownloadFailed => '字型下載失敗';

  @override
  String get appearanceFontDownloadTooltip => '下載字型';

  @override
  String get appearanceFontNotDownloaded => '未下載';

  @override
  String get appearanceFontDownloadTitle => '下載字型';

  @override
  String appearanceFontDownloadPrompt(String fontName) {
    return '字型 $fontName 尚未下載，是否現在下載並套用？';
  }

  @override
  String get appearanceAddCustomFont => '新增自訂字型';

  @override
  String get appearanceCustomFontNameLabel => '字型名稱';

  @override
  String get appearanceCustomFontNameHint => '例如：Source Han Sans';

  @override
  String get appearanceCustomFontUrlLabel => '字型下載連結';

  @override
  String get appearanceCustomFontUrlHint => 'https://example.com/font.ttf';

  @override
  String get appearanceCustomFontInvalid => '請填寫有效的字型名稱與 HTTP(S) 下載連結';

  @override
  String appearanceCustomFontAdded(String fontName) {
    return '已新增字型 $fontName';
  }

  @override
  String get appearanceCustomFontBadge => '自訂';

  @override
  String get appearanceCustomFontRemoveTitle => '移除自訂字型';

  @override
  String appearanceCustomFontRemoveContent(String fontName) {
    return '確定要移除自訂字型 $fontName 嗎？本機檔案也會一併刪除。';
  }

  @override
  String get cacheFontSection => '字型快取';

  @override
  String get cacheFontLabel => '下載字型';

  @override
  String get cacheFontDesc => '已下載的字型的字型檔案，刪除後將恢復為系統預設字型。';

  @override
  String get cacheClearFontTitle => '清除字型快取';

  @override
  String cacheClearFontContent(int count, String size) {
    return '確定要刪除 $count 個字型檔案（$size）嗎？刪除後將恢復為系統預設字型。';
  }

  @override
  String get cacheFontClearedToast => '字型快取已清除';

  @override
  String cacheFontDataTarget(int count, String size) {
    return '$count 個字型檔案（$size）';
  }

  @override
  String get networkTitle => '網路';

  @override
  String get networkApiRouteTitle => 'API 線路';

  @override
  String get networkSelectionMode => '選擇模式';

  @override
  String get networkModeRoute => '線路';

  @override
  String get networkModeFixedNode => '固定節點';

  @override
  String get networkModeAutomatic => '自動選擇';

  @override
  String get networkAutomaticStatsTitle => '自動選擇狀態';

  @override
  String networkAutomaticBestNode(String node) {
    return '目前最佳：$node';
  }

  @override
  String get networkAutomaticLearning => '目前最佳：學習中';

  @override
  String get networkAutomaticCircuitOpen => '已熔斷';

  @override
  String get networkAutomaticWaiting => '等待資料';

  @override
  String networkAutomaticRequestCount(int count) {
    return '$count 次請求';
  }

  @override
  String get networkTestOtherLatency => '測試其他節點延遲';

  @override
  String get networkFixedNodeAutoSelected => '測速後已選擇延遲最低的節點';

  @override
  String networkRouteLabel(int index) {
    return '線路 $index';
  }

  @override
  String get networkTestLatency => '測試線路延遲';

  @override
  String get networkTestingNodes => '正在檢測各節點...';

  @override
  String get networkNotTested => '尚未進行檢測';

  @override
  String get networkHighLatencyProxySuggestion => '目前延遲較大，建議開啟代理';

  @override
  String get networkRateLimitMessage => '請求過於頻繁，已被限速，請稍後再試';

  @override
  String networkRequestFailedCode(String code) {
    return '請求失敗（code: $code）';
  }

  @override
  String get networkCopyLoginHost => '拷貝登入';

  @override
  String get networkHotLoginHost => '熱辣登入';

  @override
  String get networkFixedApiHost => '固定接口';

  @override
  String get networkSystemProxyNotDetected => '系統代理：未檢測到';

  @override
  String get networkManualProxyNotConfigured => '手動代理：未設定';

  @override
  String get networkOtherRouteGroup => '其他';

  @override
  String get networkCollapseTestResults => '收起測試結果';

  @override
  String get networkExpandTestResults => '展開測試結果';

  @override
  String get networkProxySettings => '代理設定';

  @override
  String get networkRefreshSystemProxy => '重新檢測系統代理';

  @override
  String get networkProxySystem => '系統';

  @override
  String get networkProxyManual => '手動';

  @override
  String get networkCurrentProxy => '目前代理';

  @override
  String get networkProxyAddress => '代理地址';

  @override
  String get networkProxyAddressHint =>
      '127.0.0.1:7890 或 http://127.0.0.1:7890';

  @override
  String get networkSaveAndEnableManualProxy => '儲存並啟用手動代理';

  @override
  String networkTestingGoogle(String proxy) {
    return '正在透過 $proxy 存取 Google ...';
  }

  @override
  String get networkGoogleConnectivity => 'Google 連通性';

  @override
  String get networkAdvancedSettings => '進階設定';

  @override
  String get networkCopyAppVersion => 'COPY 請求版本號';

  @override
  String get networkCopyAutoUpdate => '每天自動更新';

  @override
  String get networkCopyAutoUpdateNever => '尚未更新';

  @override
  String networkCopyAutoUpdateLast(String time) {
    return '上次更新：$time';
  }

  @override
  String get networkFill => '填入';

  @override
  String get networkAverageTesting => '平均：檢測中';

  @override
  String get networkAverageTimeout => '平均：逾時';

  @override
  String networkAverageLatency(int milliseconds) {
    return '平均：$milliseconds ms';
  }

  @override
  String networkNodeLabel(int index) {
    return '節點 $index';
  }

  @override
  String get networkTesting => '檢測中';

  @override
  String get networkTimeout => '逾時';

  @override
  String get networkNoSystemProxyDetected => '未檢測到系統代理';

  @override
  String networkSystemProxyDetected(String proxy) {
    return '已檢測到 $proxy';
  }

  @override
  String get networkCopyAdvancedSaved => '已儲存 COPY 進階設定';

  @override
  String get networkCopyAdvancedReset => '已重設 COPY 進階設定';

  @override
  String networkCopyAutoFilled(String apiHost, String version) {
    return '已自動填入 COPY API 地址：$apiHost，版本號：$version';
  }

  @override
  String networkAutoFillFailed(String error) {
    return '自動填入失敗：$error';
  }

  @override
  String get networkInvalidProxyAddress => '請輸入有效的代理地址，例如 127.0.0.1:7890';

  @override
  String networkProxyEnabled(String proxy) {
    return '已啟用 $proxy';
  }

  @override
  String networkConnectionSuccess(int statusCode, String proxyRule) {
    return '連接成功，HTTP $statusCode，$proxyRule';
  }

  @override
  String networkConnectionFailed(int statusCode, String proxyRule) {
    return '連接失敗，HTTP $statusCode，$proxyRule';
  }

  @override
  String networkConnectionTimeout(String proxyRule) {
    return '連接逾時，$proxyRule';
  }

  @override
  String networkProxyRuleError(String proxyRule, String error) {
    return '$proxyRule：$error';
  }

  @override
  String networkTestFailed(String proxyRule, String error) {
    return '測試失敗，$proxyRule：$error';
  }

  @override
  String get aiConfigTitle => 'AI 設定';

  @override
  String get aiConfigNewChat => '新對話';

  @override
  String get aiConfigProvidersTitle => 'AI 供應商';

  @override
  String get aiConfigAdd => '新增';

  @override
  String get aiConfigProvidersDescription =>
      '支援任何 OpenAI 相容介面；智譜清言作為內建預設保留，可為不同供應商分別儲存 Base URL、API Key、模型和介面格式。';

  @override
  String get aiConfigEnabled => '已啟用';

  @override
  String get aiConfigDisabled => '已停用';

  @override
  String aiConfigProviderSummary(
    String status,
    int count,
    String format,
    String baseUrl,
  ) {
    return '$status · $count 個模型 · $format\n$baseUrl';
  }

  @override
  String get aiConfigEdit => '編輯';

  @override
  String get aiConfigCustomProvider => '自訂供應商';

  @override
  String get aiConfigZhipuName => '智譜清言';

  @override
  String get aiConfigAddModel => '新增模型';

  @override
  String get aiConfigModelIdLabel => '模型 ID';

  @override
  String get aiConfigFillBaseUrlAndApiKey => '請先填寫 Base URL 和 API Key';

  @override
  String aiConfigFetchModelsFailed(String error) {
    return '獲取模型失敗：$error';
  }

  @override
  String get aiConfigNoAvailableModels => '未獲取到可用模型';

  @override
  String get aiConfigSelectModel => '選擇模型';

  @override
  String get aiConfigAddSelected => '新增所選';

  @override
  String get aiConfigAddProvider => '新增供應商';

  @override
  String get aiConfigEditProvider => '編輯供應商';

  @override
  String get aiConfigProviderNameLabel => '供應商名稱';

  @override
  String get aiConfigCustomNameLabel => '自訂名稱';

  @override
  String get aiConfigCustomNameHint => 'OpenAI / One API / 自訂';

  @override
  String get aiConfigApiFormatLabel => '介面格式';

  @override
  String get aiConfigDefaultModelLabel => '預設模型';

  @override
  String get aiConfigNoSelection => '未選擇';

  @override
  String get aiConfigFetch => '獲取';

  @override
  String get aiConfigClear => '清空';

  @override
  String get aiConfigGetZhipuApiKey => '獲取智譜 API 金鑰';

  @override
  String get aiConfigProviderSaved => '供應商已儲存';

  @override
  String get aiConfigConfigureBaseUrlAndApiKey => '請先設定 Base URL 和 API 金鑰';

  @override
  String get aiConfigModelReturnedEmpty => '(模型未返回內容)';

  @override
  String aiConfigRequestFailed(String error) {
    return '請求失敗：$error';
  }

  @override
  String aiConfigPartialResponseError(String content, String error) {
    return '$content\n\n[出錯：$error]';
  }

  @override
  String get aiConfigSessionHistory => '會話歷史';

  @override
  String get aiConfigNewSession => '新會話';

  @override
  String get aiConfigNoSessionHistory => '暫無歷史會話';

  @override
  String aiConfigMessageCount(int count) {
    return '$count 條訊息';
  }

  @override
  String get aiConfigDeleteSession => '刪除會話';

  @override
  String get aiConfigProviderConfig => '介面設定';

  @override
  String get aiConfigClearChat => '清空對話';

  @override
  String get aiConfigInputHint => '說點什麼…';

  @override
  String get aiConfigSend => '傳送';

  @override
  String get aiConfigReadyEmptyHint => '設定 AI 後可以在章節評論中用於總結評論和屏蔽劇透';

  @override
  String get aiConfigSetupEmptyHint => '先在右上角設定介面';

  @override
  String get aiLegacyDefaultPromptBasic =>
      '先梳理評論區的主流聲音、分歧點、大家吐槽/誇讚的核心內容；之後直抒胸臆，大膽表達你的立場，好壞直接點明，不中和、不打太極；絕對不要虛構漫畫劇情，所有內容都基於現有評論；語言幹練接地氣，用 Markdown 輸出一份犀利總結，類似下面的格式：\n### 大家在聊什麼 （不超過7項，取多數人討論的，每一項字數保持在25字以內）\n- 很多人都表示...\n- 有些人覺得...\n- 個別人認為...\n### 我的評論\n（發表你的評論，簡短10-20字左右，不要附和他人觀點，不是對其他人的看法，而是直接說你自己的看法或吐槽，表現得自然一點）';

  @override
  String get aiDefaultPromptBasic =>
      '先梳理評論區的主流聲音、分歧點、大家吐槽/誇讚的核心內容；之後直抒胸臆，大膽表達你的立場，好壞直接點明，不中和、不打太極；絕對不要虛構漫畫劇情，所有內容都基於現有評論；語言幹練接地氣，用 Markdown 輸出一份犀利總結，類似下面的格式：\n### 大家在聊什麼 （不超過7項，取多數人討論的，每一項字數保持在25字以內）\n- 角色A做了什麼...\n- 很多人吐槽...\n- xxxx...\n### 我的評論\n（發表你的評論，簡短10-20字左右，不要附和他人觀點，不是對其他人的看法，而是直接說你自己的看法或吐槽，表現得自然一點）';

  @override
  String get aiSpoilerAnalysisPromptAppendix =>
      '【劇透分析附加要求】\n使用者已開啟劇透分析。請在遵循上方提示詞的基礎上，額外滿足以下要求：\n- 正文總結中不要複述、描述、暗示或概括任何劇透內容；\n- 可以輸出 **劇透警告**，但僅當存在劇透評論時才輸出此段，且只能寫\"本章評論中有 N（這個N是劇透的數量） 處涉及劇透，已遮罩\"這一句，絕對不要描述、暗示或概括任何劇情/轉折/結局；如果沒有任何劇透評論則整段省略。\n\n【劇透的判定標準 · 非常重要】\n只有同時滿足以下全部條件的評論才應標記為劇透：\n- 明確透露（包含猜測，有些使用者會透過猜測進行劇透）了尚未在目前章節及之前出場過的劇情走向、角色命運（死亡、復活、背叛等）或結局結果；\n- 普通的感想（如\"太好看了\"\"畫風不錯\"）、角色喜愛（如\"XX好帥\"）、對已發生情節的正常討論、對後續的模糊期待（如\"期待下一話\"）【不算】劇透；\n【機讀輸出】使用者訊息中每條評論開頭都是它的數字 id（形如 \"81216. xxx: ...\"）。在整篇輸出的最末尾追加一個 fenced code block（用三個反引號包裹），裡面只放一個 JSON 數字陣列，列出【高度劇透嫌疑】的評論 id：\n```\n[81216, 81230]\n```\n如果沒有任何高度劇透的評論，依然必須輸出該程式碼區塊，陣列為空：\n```\n[]\n```\n硬性要求：\n1) 必須是整篇輸出的最後一段，下面不要再寫任何字；\n2) 必須用三個反引號包裹（語言標識寫不寫都行）；\n3) 中括號裡只能有數字和英文逗號，不要寫解釋、不要帶 id= 前綴；\n4) 哪怕沒有劇透也要寫空陣列 []，不能省略整個程式碼區塊；\n';

  @override
  String get aiPromptBasicName => '基礎提示詞';

  @override
  String get noticeCenterTitle => '通知中心';

  @override
  String get downloadCenterTitle => '下載中心';

  @override
  String get browseHistoryTitle => '瀏覽記錄';

  @override
  String get aboutTitle => '關於';

  @override
  String get notLoggedInTitle => '未登入';

  @override
  String get loginPromptSubtitle => '點擊登入以使用書架等功能';

  @override
  String get refreshUserButton => '重新整理使用者';

  @override
  String get switchAccountButton => '切換帳號';

  @override
  String get copyTokenButton => '複製權杖';

  @override
  String get appDisclaimerIntro => '請在使用本應用前仔細閱讀以下聲明：';

  @override
  String get appDisclaimerItem1 =>
      '本應用（以下簡稱\"本軟體\"）係獨立開發的非官方第三方用戶端，與任何內容平台、出版商或權利人均無隸屬、合作或代理關係。';

  @override
  String get appDisclaimerItem2 =>
      '本軟體不生產、上傳、儲存、編輯、修改、推薦或預先審查任何具體內容。所有內容均來源於第三方平台公開介面或可存取資源，其合法性、準確性、完整性及合規性由相應內容提供方獨立負責。';

  @override
  String get appDisclaimerItem3 =>
      '本軟體所展示的內容可能包含成人向、暴力、恐怖或其他不適宜未成年人瀏覽的資訊。您確認您已年滿 18 歲，且您所在地法律法規允許您存取此類內容。如您不符合前述條件，請立即停止使用並解除安裝本軟體。';

  @override
  String get appDisclaimerItem4 =>
      '您應自行判斷所瀏覽內容是否適合，並確保您的使用行為完全符合您所在地現行有效的法律法規。因您使用本軟體而產生的一切法律後果由您自行承擔。';

  @override
  String get appDisclaimerItem5 =>
      '如任何第三方內容涉嫌侵犯他人合法權益或違反法律法規，權利人可透過本軟體提供的聯絡方式向開發者傳送有效通知，開發者將在合理期限內核實並採取必要措施。';

  @override
  String get appDisclaimerItem6 =>
      '本軟體按\"現狀\"提供，開發者不對其功能性、可用性、準確性或可靠性作出任何明示或默示的保證。在任何情況下，開發者均不對因使用或無法使用本軟體而產生的任何直接、間接、附帶、特殊或後果性損害承擔責任。';

  @override
  String get appDisclaimerFooter =>
      '繼續使用本軟體，即表示您已仔細閱讀、充分理解並同意接受上述全部條款的約束。如您不同意任一條款，請立即停止使用並解除安裝本軟體。';

  @override
  String get profileCurrentSelectedCredential => '目前已選';

  @override
  String get profileRemoveAccountTooltip => '移除帳號';

  @override
  String profileAccountRemovedToast(String username) {
    return '已移除 $username';
  }

  @override
  String get profileRegisterSuccessLoginToast => '註冊成功，請登入';

  @override
  String get profileUsernamePasswordRequired => '請輸入使用者名稱和密碼';

  @override
  String get profileLoginFailed => '登入失敗';

  @override
  String get profileTokenRequired => '請輸入權杖';

  @override
  String get profileTokenInvalidOrExpired => '權杖無效或已過期';

  @override
  String get profileLoginTitle => '登入';

  @override
  String get profileAccountPasswordLoginMode => '帳號密碼';

  @override
  String get profileTokenLoginMode => '權杖';

  @override
  String get profileSavedAccountsTitle => '已儲存帳號';

  @override
  String get profileSavedAccountsHint => '點按快速填入帳號密碼，右側可移除';

  @override
  String get profileUsernameLabel => '使用者名稱';

  @override
  String get profilePasswordLabel => '密碼';

  @override
  String get profileTokenLabel => '權杖 (Token)';

  @override
  String get profileTokenHint => '貼上你的登入權杖';

  @override
  String get profileRememberAccountLabel => '記住帳號';

  @override
  String get profileRegisterHotMangaAccountButton => '註冊熱辣漫畫帳號';

  @override
  String get profileLoginButton => '登入';

  @override
  String get profileRegisterInfoRequired => '請填寫完整註冊資訊';

  @override
  String get profilePasswordMismatch => '兩次輸入的密碼不一致';

  @override
  String get profileSecurityQuestionRequired => '請選擇安全問題';

  @override
  String get profileRegisterFailed => '註冊失敗';

  @override
  String get profileOpenOfficialRegisterFailed => '無法開啟官網註冊頁';

  @override
  String get profileConfirmPasswordLabel => '確認密碼';

  @override
  String get profileSecurityQuestionLabel => '帳號安全問題';

  @override
  String get profileSecurityAnswerLabel => '安全問題答案';

  @override
  String get profileReloadSecurityQuestionsButton => '重新載入安全問題';

  @override
  String get profileRegisterButton => '註冊';

  @override
  String get profileOfficialRegisterPrompt => '去官網註冊';

  @override
  String get profileHotMangaLabel => '熱辣漫畫';

  @override
  String get profileCopyMangaLabel => '拷貝漫畫';

  @override
  String get aboutQqGroupTitle => 'QQ 交流群';

  @override
  String get aboutJoinGroupButton => '加入群聊';

  @override
  String get aboutGroupNumberCopiedToast => '已複製群號';

  @override
  String get aboutMirrorPrefixTitle => '設定鏡像源';

  @override
  String get aboutMirrorPrefixDesc => '用於更新與播放元件下載的鏡像連結，會拼接在 GitHub 下載地址前。';

  @override
  String get aboutMirrorPrefixLabel => '鏡像源地址';

  @override
  String get aboutMirrorPrefixHelper => '留空將恢復預設鏡像源';

  @override
  String get aboutInvalidMirrorPrefix => '請輸入有效的 http(s) 地址';

  @override
  String get aboutRestoreDefaultButton => '恢復預設';

  @override
  String get aboutSaveButton => '儲存';

  @override
  String get aboutMirrorPrefixSavedToast => '鏡像源已儲存';

  @override
  String get aboutStableChannelShort => '穩定版';

  @override
  String get aboutUpdateChannelTitle => '更新渠道';

  @override
  String get aboutStableChannelTitle => '穩定版 (Stable)';

  @override
  String get aboutStableChannelDesc => '僅檢查正式發布版本';

  @override
  String get aboutBetaChannelTitle => '預覽版（Beta）';

  @override
  String get aboutBetaChannelDesc => '從最新提交建置的版本，可能不穩定';

  @override
  String get aboutBetaChannelSwitchedTitle => '已切換到預覽版';

  @override
  String get aboutBetaChannelSwitchedContent => '預覽版一般用於測試新功能或修復問題，可能存在更多問題。';

  @override
  String get aboutGotItButton => '知道了';

  @override
  String get aboutRepositoryLabel => '倉庫';

  @override
  String get aboutFeedbackLabel => '回饋';

  @override
  String get aboutCommunityLabel => '交流';

  @override
  String get aboutCheckUpdateTitle => '檢查更新';

  @override
  String get aboutAutoCheckUpdateTitle => '啟動時檢查更新';

  @override
  String get aboutLogTitle => '日誌';

  @override
  String get aboutAcknowledgementTitle => '致謝';

  @override
  String get acknowledgementThanksTitle => '感謝以下服務與專案的支援';

  @override
  String get acknowledgementDandanplayTitle => '彈彈play';

  @override
  String get acknowledgementDandanplayDesc => '提供彈幕服務';

  @override
  String get acknowledgementZhconvertTitle => '繁化姬';

  @override
  String get acknowledgementZhconvertDesc => '提供簡體化服務';

  @override
  String get aboutLicenseTitle => '授權條款';

  @override
  String get licenseMitSummary => '本專案採用 MIT 開源授權條款';

  @override
  String get cacheDeleteEntryTitle => '刪除快取項';

  @override
  String cacheDeleteEntryContent(String key) {
    return '確定要刪除 $key 嗎？此操作無法復原。';
  }

  @override
  String cacheEntryDeletedToast(String key) {
    return '已刪除 $key';
  }

  @override
  String cacheDeleteFailedToast(String error) {
    return '刪除失敗：$error';
  }

  @override
  String cacheLocalDataTarget(int count) {
    return '$count 項本地資料';
  }

  @override
  String cacheImageDataTarget(int count, String size) {
    return '$count 個圖片快取（$size）';
  }

  @override
  String cacheMediaKitDataTarget(String size) {
    return '播放元件（$size）';
  }

  @override
  String get cacheDeleteSelectedTitle => '刪除選中快取';

  @override
  String cacheDeleteSelectedContent(String targets) {
    return '確定要刪除選中卡片中的 $targets 嗎？此操作無法復原。';
  }

  @override
  String get cacheSelectedDeletedToast => '已刪除選中快取';

  @override
  String get cacheNoImageCacheToClear => '暫無可清理的圖片快取';

  @override
  String get cacheClearImageCacheTitle => '清空圖片快取';

  @override
  String cacheClearImageCacheContent(String label, int fileCount, String size) {
    return '確定要清空 $label 嗎？將刪除 $fileCount 個檔案，釋放約 $size。';
  }

  @override
  String get cacheClearButton => '清空';

  @override
  String cacheClearDataSectionContent(String sectionLabel) {
    return '確定要清空 $sectionLabel 中的所有資料嗎？';
  }

  @override
  String cacheImageCacheClearedToast(String label) {
    return '已清空 $label';
  }

  @override
  String cacheCleanFailedToast(String error) {
    return '清理失敗：$error';
  }

  @override
  String get cacheReaderImageLabel => '圖片快取 / 漫畫閱讀器';

  @override
  String get cacheReaderImageDesc => '漫畫章節圖片快取。再次開啟讀過的章節時，圖片會優先從這裡讀取。';

  @override
  String get cacheDefaultImageLabel => '圖片快取 / 封面與頭像';

  @override
  String get cacheDefaultImageDesc => '封面、頭像等 CachedNetworkImage 預設使用的圖片快取。';

  @override
  String get cacheMediaKitLabel => '播放元件 / media_kit';

  @override
  String get cacheMediaKitDesc => '動漫播放器原生庫（libmpv 等）。首次播放時按需下載；刪除後下次播放會重新下載。';

  @override
  String get cacheMediaKitSection => '播放元件';

  @override
  String get cacheNoMediaKitToClear => '尚未下載播放元件';

  @override
  String get cacheClearMediaKitTitle => '刪除播放元件';

  @override
  String cacheClearMediaKitContent(int fileCount, String size) {
    return '確定刪除已下載的播放元件嗎？將刪除 $fileCount 個檔案，釋放約 $size。下次播放動漫時會重新下載。';
  }

  @override
  String get cacheMediaKitClearedToast => '已刪除播放元件';

  @override
  String get cacheMediaKitVersionLabel => '元件版本';

  @override
  String get commentSettingsEditBuiltInPromptTitle => '編輯內建提示詞';

  @override
  String get commentSettingsEditPromptTitle => '編輯提示詞';

  @override
  String get commentSettingsAddPromptTitle => '新增提示詞';

  @override
  String get commentSettingsNameLabel => '名稱';

  @override
  String get commentSettingsPromptLabel => '提示詞';

  @override
  String get commentSettingsResetButton => '重設';

  @override
  String get commentSettingsSaveButton => '儲存';

  @override
  String get commentSettingsAddButton => '新增';

  @override
  String get commentSettingsTitle => '評論區設定';

  @override
  String get commentSettingsLayoutSection => '版面配置';

  @override
  String get commentSettingsCompactLayout => '緊湊版面';

  @override
  String get commentSettingsListLayout => '列表版面';

  @override
  String get commentSettingsShowAvatar => '顯示頭像';

  @override
  String get commentSettingsShowUserName => '顯示使用者名稱';

  @override
  String get commentSettingsShowCommentTime => '顯示評論時間';

  @override
  String get commentSettingsPreloadTitle => '預載評論';

  @override
  String get commentSettingsPreloadDesc => '進入章節時提前載入評論並顯示數量';

  @override
  String get commentSettingsAutoLoadAllTitle => '自動載入全部評論';

  @override
  String get commentSettingsAutoLoadAllDesc => '開啟評論區時自動載入所有評論';

  @override
  String get commentSettingsFontSizeTitle => '評論內容字型大小';

  @override
  String get chapterCommentsNoSummaryComments => '目前沒有可總結的評論';

  @override
  String get chapterCommentsEnableAiSummaryFirst => '請先在評論區設定中啟用 AI 總結';

  @override
  String chapterCommentsPromptComicLine(String comicName) {
    return '漫畫：$comicName\n';
  }

  @override
  String chapterCommentsPromptUser(
    String comicLine,
    String chapterName,
    int count,
    String snippets,
  ) {
    return '$comicLine章節：$chapterName\n共 $count 條不同評論（相同內容已合併）。每條行首數字為該評論的 id：\n\n$snippets';
  }

  @override
  String chapterCommentsMergedSnippet(int id, int count, String text) {
    return '$id. [$count人] $text\n';
  }

  @override
  String chapterCommentsSingleSnippet(int id, String userName, String text) {
    return '$id. $userName: $text\n';
  }

  @override
  String chapterCommentsSnippetsTruncated(int count) {
    return '…（已截斷，共 $count 條不同評論）';
  }

  @override
  String get chapterCommentsDioException => 'Dio 異常';

  @override
  String get chapterCommentsCopyLog => '複製日誌';

  @override
  String get chapterCommentsLoginRequiredToPost => '請先登入後再發表評論';

  @override
  String get chapterCommentsLengthRange => '評論字數需在 3-200 之間';

  @override
  String get chapterCommentsPosted => '評論已發布';

  @override
  String get chapterCommentsPostTitle => '發表評論';

  @override
  String get chapterCommentsPostHint => '吐槽一下';

  @override
  String get chapterCommentsLengthHelper => '評論字數 3-200';

  @override
  String get chapterCommentsLogCopied => '日誌已複製';

  @override
  String get chapterCommentsPublish => '發布';

  @override
  String get chapterCommentsActionTitle => '評論操作';

  @override
  String get chapterCommentsPlusOneSubtitle => '傳送一條相同評論';

  @override
  String get chapterCommentsBlockUser => '封鎖使用者';

  @override
  String chapterCommentsHideUserComments(String userName) {
    return '隱藏 $userName 的評論';
  }

  @override
  String get chapterCommentsCopied => '已複製';

  @override
  String get chapterCommentsUserBlocked => '已封鎖該使用者';

  @override
  String get chapterCommentsBlockUnnamedConfirm => '確定封鎖該使用者嗎？封鎖後將不再顯示其評論。';

  @override
  String chapterCommentsBlockNamedConfirm(String name) {
    return '確定封鎖「$name」嗎？封鎖後將不再顯示其評論。\n可在評論區設定 → 黑名單中解除。';
  }

  @override
  String get chapterCommentsNoRemindAgain => '不再提醒';

  @override
  String get chapterCommentsBlock => '封鎖';

  @override
  String get chapterCommentsPlusOneLengthInvalid => '評論字數需在 3-200 之間，無法 +1';

  @override
  String get chapterCommentsPlusOneSent => '+1 已傳送';

  @override
  String get chapterCommentsPostFailed => '發表評論失敗';

  @override
  String get chapterCommentsTitle => '章節評論';

  @override
  String get chapterCommentsLoadAllTooltip => '載入全部評論';

  @override
  String get chapterCommentsAiSummaryTooltip => 'AI 總結評論';

  @override
  String get chapterCommentsRegenerateAiSummaryTooltip => '重新生成 AI 總結';

  @override
  String get chapterCommentsSwitchToListLayout => '切換為列表版面';

  @override
  String get chapterCommentsSwitchToCompactLayout => '切換為緊湊版面';

  @override
  String chapterCommentsTotalCount(int count) {
    return '$count 條';
  }

  @override
  String get chapterCommentsComment => '評論';

  @override
  String get chapterCommentsCatalog => '目錄';

  @override
  String get chapterCommentsNext => '下一話';

  @override
  String get chapterCommentsLoadFailed => '評論載入失敗';

  @override
  String get chapterCommentsEmptyTitle => '還沒有評論';

  @override
  String get chapterCommentsEmptySubtitle => '這個章節暫時沒人發言';

  @override
  String get chapterCommentsSwitchModel => '切換模型';

  @override
  String get chapterCommentsCannotSwitchModelGenerating => '生成中無法切換模型';

  @override
  String chapterCommentsModelSummary(String model) {
    return '$model 總結';
  }

  @override
  String chapterCommentsActiveModel(String provider, String model) {
    return '目前模型：$provider / $model';
  }

  @override
  String get chapterCommentsReasoning => '思考過程';

  @override
  String get chapterCommentsReasoningCollapsed => '思考過程（已摺疊）';

  @override
  String get chapterCommentsGenerating => '正在生成中…';

  @override
  String get chapterCommentsCollapse => '收起';

  @override
  String get chapterCommentsExpand => '展開';

  @override
  String chapterCommentsSummaryFailed(String error) {
    return '生成失敗：$error';
  }

  @override
  String get chapterCommentsStop => '停止';

  @override
  String get chapterCommentsRegenerate => '重新生成';

  @override
  String get chapterCommentsClearSummary => '清除總結';

  @override
  String get comicCommentTitle => '漫畫評論';

  @override
  String get comicCommentSettingsTooltip => '評論設定';

  @override
  String get comicCommentLoadFailed => '評論載入失敗';

  @override
  String get comicCommentEmptySubtitle => '這部漫畫暫時沒人發言';

  @override
  String get comicCommentCollapseReplies => '收起回覆';

  @override
  String comicCommentExpandReplies(int count) {
    return '展開 $count 條回覆';
  }

  @override
  String get comicCommentReplyLoadFailed => '回覆載入失敗';

  @override
  String get comicCommentEmptyReplies => '暫無可顯示的回覆';

  @override
  String get comicCommentRetryLoadMoreReplies => '重試載入更多回覆';

  @override
  String comicCommentLoadMoreReplies(int loaded, int total) {
    return '載入更多回覆 ($loaded/$total)';
  }

  @override
  String get comicCommentCopied => '評論已複製';

  @override
  String comicCommentBlockNamedConfirm(String name) {
    return '確定封鎖「$name」嗎？封鎖後將不再顯示其評論。\n可在黑名單中解除。';
  }

  @override
  String comicCommentReplyTitle(String userName) {
    return '回覆 $userName';
  }

  @override
  String comicCommentReplyHint(String userName) {
    return '回覆 $userName...';
  }

  @override
  String get comicCommentPostHint => '說點什麼...';

  @override
  String get comicCommentReplyPosted => '回覆已發布';

  @override
  String get comicCommentReplyButton => '回覆';

  @override
  String get comicCommentExpandFullText => '展開全文';

  @override
  String get animeDetailTitle => '動漫詳情';

  @override
  String get animeDetailIntroTab => '簡介';

  @override
  String animeDetailEpisodesTab(int count) {
    return '選集 ($count)';
  }

  @override
  String get animeDetailIntroRefreshFailed => '簡介重新整理失敗';

  @override
  String get animeDetailEpisodeRefreshFailed => '選集重新整理失敗';

  @override
  String get animeDetailDandanplayBindingCleared => '已清除彈彈play綁定';

  @override
  String animeDetailDandanplayBound(String title) {
    return '已綁定 $title';
  }

  @override
  String get animeDetailAlignmentCleared => '已清除對齊';

  @override
  String get animeDetailRealigned => '已重新對齊彈幕';

  @override
  String get animeDetailNoAvailableLine => '目前選集暫無可用線路';

  @override
  String get animeDetailPlaybackEpisodeUnavailable => '播放紀錄對應選集暫不可用';

  @override
  String get animeDetailInfoLoadFailedForDownload => '動漫資訊載入失敗，無法下載';

  @override
  String get animeDetailNoLineForDownload => '目前選集暫無可用線路，無法下載';

  @override
  String animeDetailDownloadTasksAdded(int count) {
    return '已新增 $count 個下載任務';
  }

  @override
  String get animeDetailCannotCollect => '目前動漫暫時無法收藏';

  @override
  String get animeDetailCollected => '已收藏';

  @override
  String get animeDetailCollectCancelled => '已取消收藏';

  @override
  String get animeDetailCollectFailed => '收藏狀態修改失敗';

  @override
  String animeDetailDownloadTaskCount(int count) {
    return '$count 個任務';
  }

  @override
  String get animeDetailNoIntroInfo => '暫無簡介資訊';

  @override
  String get animeDetailInfoTitle => '資料';

  @override
  String get animeDetailIntroLoadFailed => '簡介載入失敗，下拉重試';

  @override
  String get animeDetailIntroRefreshFailedCached => '簡介重新整理失敗，目前顯示快取內容';

  @override
  String animeDetailSelectedEpisodes(int count) {
    return '已選 $count 集';
  }

  @override
  String get animeDetailSelectAllUndownloaded => '全選未下載';

  @override
  String get animeDetailDownloadSelected => '下載選中';

  @override
  String get animeDetailEpisodeLoadFailed => '選集載入失敗，下拉重試';

  @override
  String get animeDetailNoEpisodes => '暫無選集';

  @override
  String get animeDetailEpisodeRefreshFailedCached => '選集重新整理失敗，目前顯示上次結果';

  @override
  String get animeDetailBindToViewComments => '綁定彈彈play 後才可查看評論';

  @override
  String get animeDetailBindDanmaku => '綁定彈幕';

  @override
  String get animeDetailRebind => '重新綁定';

  @override
  String get animeDetailAlign => '對齊';

  @override
  String get animeDetailDownloadButton => '下載';

  @override
  String get animeDetailEpisodeLoadFailedShort => '選集載入失敗';

  @override
  String get readerSettingsTitle => '閱讀設定';

  @override
  String get readerScrollMode => '捲動';

  @override
  String get readerPageMode => '翻頁';

  @override
  String get readerLeftToRight => '左到右';

  @override
  String get readerRightToLeft => '右到左';

  @override
  String get readerTopToBottom => '上到下';

  @override
  String get readerScrollSection => '捲動';

  @override
  String get readerImageGap => '圖片間距';

  @override
  String get readerContinuousReading => '連續閱讀';

  @override
  String get readerContinuousReadingDesc => '到末頁後直接拼接下一話，不重新載入';

  @override
  String get readerAutoScroll => '自動捲動';

  @override
  String get readerAutoScrollDesc => '開啟後在導覽列顯示自動捲動按鈕';

  @override
  String get readerAutoScrollDistance => '捲動幅度';

  @override
  String get readerAutoScrollPause => '停頓時長';

  @override
  String readerSeconds(String seconds) {
    return '$seconds 秒';
  }

  @override
  String get readerAutoResume => '自動恢復';

  @override
  String get readerAutoResumeDesc => '一段時間無動作後自動恢復捲動';

  @override
  String get readerAutoResumeDelay => '恢復延遲';

  @override
  String get readerPageSection => '翻頁';

  @override
  String get readerVolumeKeyPageTurn => '音量鍵翻頁';

  @override
  String get readerVolumeKeyPageTurnDesc => '音量+上一頁，音量-下一頁';

  @override
  String get readerInstantPageTurn => '無動畫翻頁';

  @override
  String get readerDisplaySection => '顯示';

  @override
  String get readerDimming => '降低亮度';

  @override
  String get readerImageLoadingSection => '圖片載入';

  @override
  String get readerTimeout => '逾時時間';

  @override
  String get readerTimeoutDesc => '設定太小可能導致圖片載入失敗，太大可能導致長時間轉圈';

  @override
  String get readerNoLoadStats => '暫無載入紀錄（閱讀圖片後此處顯示平均耗時供參考）';

  @override
  String readerRecentLoadStats(int count, String seconds) {
    return '最近10分鐘內載入了 $count 張，平均 $seconds s';
  }

  @override
  String get readerRetryCount => '重試次數';

  @override
  String get offButton => '關閉';

  @override
  String readerTimes(int count) {
    return '$count 次';
  }

  @override
  String get browseHistoryClearTitle => '清空瀏覽紀錄';

  @override
  String browseHistoryClearContent(String mode) {
    return '確定要清空所有$mode瀏覽紀錄嗎？此操作不可復原。';
  }

  @override
  String browseHistoryCleared(String mode) {
    return '已清空$mode瀏覽紀錄';
  }

  @override
  String browseHistoryClearFailed(String error) {
    return '清空失敗：$error';
  }

  @override
  String get browseHistoryLoginExpiredContent => '瀏覽紀錄需要登入後才能繼續查看，是否現在重新登入？';

  @override
  String get browseHistoryLoginToView => '登入後可繼續查看瀏覽紀錄';

  @override
  String get browseHistoryLoginHintWithAnime => '瀏覽過的漫畫和動漫會同步顯示在這裡';

  @override
  String get browseHistoryLoginHintComicOnly => '瀏覽過的漫畫會同步顯示在這裡';

  @override
  String browseHistoryEmptyTitle(String mode) {
    return '還沒有$mode瀏覽紀錄';
  }

  @override
  String browseHistoryEmptySubtitle(String mode) {
    return '去看幾部$mode後，這裡會顯示最近瀏覽內容';
  }

  @override
  String browseHistoryTotal(int count, String mode) {
    return '共 $count 條$mode瀏覽紀錄';
  }

  @override
  String hundredMillionUnit(String value) {
    return '$value億';
  }

  @override
  String tenThousandUnit(String value) {
    return '$value萬';
  }

  @override
  String browseHistoryLatestChapter(String chapter) {
    return '最新 $chapter';
  }

  @override
  String browseHistoryLastSeen(String name) {
    return '上次看到 $name';
  }

  @override
  String get animePlayerLoginRequiredToPlay => '登入後才能播放該影片';

  @override
  String get animePlayerEmptyVideoUrl => '影片連結為空';

  @override
  String animePlayerRequestFailedStatus(int statusCode) {
    return '請求失敗（$statusCode）';
  }

  @override
  String animePlayerRequestFailedStatusText(String statusCode) {
    return '請求失敗（$statusCode）';
  }

  @override
  String get animePlayerMpvLogTitle => 'media_kit/mpv 日誌:';

  @override
  String get animePlayerQuickDiagnosisTitle => '快速診斷:';

  @override
  String animePlayerDiagnosisManifestStatus(int statusCode) {
    return 'm3u8 狀態: $statusCode';
  }

  @override
  String get animePlayerDiagnosisManifestHls => 'm3u8 內容: 已識別為 HLS 清單';

  @override
  String get animePlayerDiagnosisManifestNotHls =>
      'm3u8 內容: 返回 200，但內容不像標準 HLS 清單';

  @override
  String animePlayerDiagnosisManifestError(String error) {
    return 'm3u8 錯誤: $error';
  }

  @override
  String animePlayerDiagnosisFirstSegment(String url) {
    return '首個分片: $url';
  }

  @override
  String animePlayerDiagnosisSegmentStatus(int statusCode) {
    return '首個分片狀態: $statusCode';
  }

  @override
  String animePlayerDiagnosisSegmentBytes(int bytes) {
    return '首個分片位元組數: $bytes';
  }

  @override
  String animePlayerDiagnosisSegmentError(String error) {
    return '首個分片錯誤: $error';
  }

  @override
  String get animePlayerDiagnosisConclusionDecodeIssue =>
      '結論: m3u8 與首個分片都可存取，更像是播放器解析或解碼相容問題';

  @override
  String get animePlayerSourceForbidden => '影片來源拒絕存取（403）';

  @override
  String get animePlayerSourceNotFound => '影片地址已失效（404）';

  @override
  String get animePlayerCertificateFailed => '影片憑證校驗失敗';

  @override
  String get animePlayerConnectionTimeout => '影片連線逾時';

  @override
  String get animePlayerCannotParseStream => '影片來源可存取，但播放器無法解析該影片串流';

  @override
  String get animePlayerEnableProxyToRetry => '影片載入失敗，請開啟代理後重試';

  @override
  String get animePlayerInvalidVideoUri => '影片地址不是合法 URI';

  @override
  String get animePlayerDiagnosisRequestFailed => '影片診斷請求失敗';

  @override
  String get animePlayerSegmentDiagnosisRequestFailed => '影片分片診斷請求失敗';

  @override
  String get animePlayerSegmentUrlNotResolved => '未解析出分片地址';

  @override
  String get animePlayerLoadingCannotSwitch => '影片載入中，請稍後再切換';

  @override
  String get animePlayerNoVideoUrlToCopy => '暫無可複製的影片連結';

  @override
  String get animePlayerVideoUrlCopied => '影片連結已複製到剪貼簿';

  @override
  String get animePlayerNoVideoUrlToOpen => '暫無可開啟的影片連結';

  @override
  String get animePlayerOpenVideoUrlFailed => '無法開啟影片連結';

  @override
  String animePlayerSeekedTo(String position) {
    return '已跳轉到 $position';
  }

  @override
  String get animePlayerSeekLastFailed => '無法跳轉到上次進度';

  @override
  String animePlayerSearchFailed(String error) {
    return '搜尋失敗: $error';
  }

  @override
  String get animePlayerRefreshTooFrequent => '不要頻繁重新整理！';

  @override
  String animePlayerLoadDanmakuFailed(String error) {
    return '載入彈幕失敗: $error';
  }

  @override
  String get animePlayerBuffering => '正在緩衝...';

  @override
  String get animePlayerProxySuggestion => '如果網路卡頓，建議開啟代理存取';

  @override
  String get animePlayerPlay => '播放';

  @override
  String animePlayerFastForward(int seconds) {
    return '快進 $seconds秒';
  }

  @override
  String get animePlayerHideDanmaku => '隱藏彈幕';

  @override
  String get animePlayerChapterSelector => '選集';

  @override
  String animePlayerChapterSelectorWithCount(int count) {
    return '選集 ($count)';
  }

  @override
  String get animePlayerSetSkipSeconds => '設定跳轉秒數';

  @override
  String get animePlayerExitFullscreen => '退出全螢幕';

  @override
  String get animePlayerFullscreen => '全螢幕';

  @override
  String get backButton => '返回';

  @override
  String cacheSelectedCards(int count) {
    return '已選 $count 個卡片';
  }

  @override
  String get cacheDeleteSelectedCardsTooltip => '刪除選中卡片';

  @override
  String get cacheExitMultiSelectTooltip => '退出多選';

  @override
  String get cacheMultiSelectTooltip => '多選卡片';

  @override
  String cacheSummary(int localTotal, int imageCacheFiles, String size) {
    return '共 $localTotal 項本地資料 · $size';
  }

  @override
  String get cacheManagementSummaryDesc =>
      '按快取、帳號、設定、歷史等分類顯示；AI 配置 key 已隱藏；圖片與播放元件可單獨清理。';

  @override
  String get cacheImageCacheSection => '圖片快取';

  @override
  String get cacheDataCacheSection => '資料快取';

  @override
  String get cacheNoLocalKeyValueData => '沒有可顯示的本地鍵值資料';

  @override
  String cacheEntryCountSize(int count, String size) {
    return '$count 項 · $size';
  }

  @override
  String get cacheHideSensitiveTooltip => '隱藏敏感內容';

  @override
  String get cacheShowSensitiveTooltip => '顯示敏感內容';

  @override
  String get cacheEntryDataTitle => '快取項資料';

  @override
  String get cacheDataCopiedToast => '快取資料已複製';

  @override
  String cacheFileCountSize(int count, String size) {
    return '$count 個檔案 · $size';
  }

  @override
  String get cacheDescriptionTitle => '說明';

  @override
  String get cacheKeyTitle => '快取標識';

  @override
  String get cacheDirectoryTitle => '快取目錄';

  @override
  String get cacheCategoryPersistentCache => '業務快取';

  @override
  String get cacheCategoryAccount => '帳號資料';

  @override
  String get cacheCategoryAppSettings => '應用設定';

  @override
  String get cacheCategoryMangaHistory => '漫畫閱讀歷史';

  @override
  String get cacheCategoryAnimeHistory => '動漫播放歷史';

  @override
  String get cacheCategoryBindings => '彈幕綁定';

  @override
  String get cacheCategoryAiSummaryCache => 'AI 總結快取';

  @override
  String get cacheCategoryOther => '其他資料';

  @override
  String get themeColorBlueGrey => '藍灰';

  @override
  String get themeColorTeal => '青綠';

  @override
  String get themeColorIndigo => '靛藍';

  @override
  String get themeColorGreen => '森綠';

  @override
  String get themeColorOrange => '橙金';

  @override
  String get themeColorPink => '粉色';

  @override
  String get themeColorBrightBlue => '亮藍';

  @override
  String get themeColorViolet => '紫羅蘭';

  @override
  String get themeColorOrchid => '蘭紫';

  @override
  String get themeColorCyan => '湖青';

  @override
  String get themeColorEmerald => '翡翠';

  @override
  String get themeColorLime => '青檸';

  @override
  String get themeColorAmber => '琥珀';

  @override
  String get themeColorCoral => '珊瑚';

  @override
  String get themeColorCustom => '自定';

  @override
  String get themeVariantTonalSpot => '柔和';

  @override
  String get themeVariantTonalSpotDesc => 'Material 預設風格，低飽和、耐看。';

  @override
  String get themeVariantVibrant => '鮮明';

  @override
  String get themeVariantVibrantDesc => '提高主色飽和度，整體更醒目。';

  @override
  String get themeVariantExpressive => '表現';

  @override
  String get themeVariantExpressiveDesc => '會偏移主色相，風格更有個性。';

  @override
  String get themeVariantFidelity => '準確';

  @override
  String get themeVariantFidelityDesc => '盡量貼近所選主色的原始觀感。';

  @override
  String get themeVariantContent => '內容';

  @override
  String get themeVariantContentDesc => '容器顏色更貼近主色，強調層次。';

  @override
  String get themeVariantNeutral => '中性';

  @override
  String get themeVariantNeutralDesc => '接近灰階，適合更克制的介面。';

  @override
  String get themeVariantMonochrome => '黑白';

  @override
  String get themeVariantMonochromeDesc => '完全灰階，只保留明暗關係。';

  @override
  String get themeVariantRainbow => '彩虹';

  @override
  String get themeVariantRainbowDesc => '跳脫主色限制，整體更活潑。';

  @override
  String get appLogEmpty => '暫無錯誤日誌';

  @override
  String get appLogCopied => '日誌已複製到剪貼簿';

  @override
  String appLogCopyFailed(String error) {
    return '複製失敗：$error';
  }

  @override
  String get appLogClearTitle => '清空錯誤日誌';

  @override
  String get appLogClearContent => '確定要刪除本地保存的錯誤日誌嗎？';

  @override
  String get appLogCleared => '錯誤日誌已清空';

  @override
  String appLogClearFailed(String error) {
    return '清空失敗：$error';
  }

  @override
  String get settingsTooltip => '設定';

  @override
  String get appLogSettingsTitle => '日誌設定';

  @override
  String get appLogRecordLogs => '記錄日誌';

  @override
  String get appLogLevel => '日誌級別';

  @override
  String get appLogLevelDebug => '調試';

  @override
  String get appLogLevelInfo => '資訊';

  @override
  String get appLogLevelWarning => '警告';

  @override
  String get appLogLevelError => '錯誤';

  @override
  String get appLogSearchHint => '搜尋日誌（訊息、來源、堆疊、上下文）';

  @override
  String get appLogClearLogsTooltip => '清空日誌';

  @override
  String get appLogAllLevels => '全部';

  @override
  String get appLogCopyThisLogTooltip => '複製此日誌';

  @override
  String get appLogContextTitle => '上下文';

  @override
  String get appLogStackTitle => '堆疊';

  @override
  String get relativeTimeJustNow => '剛剛';

  @override
  String relativeTimeMinutesAgo(int minutes) {
    return '$minutes分鐘前';
  }

  @override
  String relativeTimeHoursAgo(int hours) {
    return '$hours小時前';
  }

  @override
  String relativeTimeDaysAgo(int days) {
    return '$days天前';
  }

  @override
  String relativeTimeMonthsAgo(int months) {
    return '$months個月前';
  }

  @override
  String relativeTimeYearsAgo(int years) {
    return '$years年前';
  }

  @override
  String get comicDetailCommentsUnavailable => '目前漫畫暫時無法查看評論';

  @override
  String get comicDetailAuthorUnavailable => '目前作者暫時無法查看作品';

  @override
  String get comicDetailThemeUnavailable => '目前主題暫時無法查看作品';

  @override
  String get comicDetailSelectUndownloadedChapters => '請選擇未下載的章節';

  @override
  String comicDetailAddedToDownloadQueue(int count) {
    return '已加入下載佇列：$count 章（順序下載）';
  }

  @override
  String get comicDetailSelectedAlreadyDownloadedOrQueued => '所選章節已下載或已在佇列中';

  @override
  String comicDetailSelectedChapters(int count) {
    return '已選 $count 章';
  }

  @override
  String comicDetailSequentialDownloading(int count) {
    return '順序下載中 $count 章';
  }

  @override
  String get downloadedStatus => '已下載';

  @override
  String comicDetailDownloadProgress(int completed, int total) {
    return '下載 $completed/$total';
  }

  @override
  String get comicDetailQueued => '排隊中';

  @override
  String get processingStatus => '處理中';

  @override
  String comicDetailReadWithStatus(String status) {
    return '已讀 · $status';
  }

  @override
  String get collectButton => '收藏';

  @override
  String get downloadQueueTab => '佇列';

  @override
  String get downloadQueueEmpty => '下載佇列為空';

  @override
  String get downloadQueueEmptyComicHint => '去漫畫詳情頁新增下載任務';

  @override
  String get downloadQueueEmptyMixedHint => '去漫畫或動漫詳情頁新增下載任務';

  @override
  String downloadProgressApproxBytes(String percent, String size) {
    return '$percent% · 約 $size';
  }

  @override
  String get downloadingStatus => '下載中';

  @override
  String get waitingStatus => '等待中';

  @override
  String get pausedStatus => '已暫停';

  @override
  String get downloadFailedStatus => '下載失敗';

  @override
  String get animeDownloadConnectionTimeout => '連線逾時';

  @override
  String get animeDownloadProxyRetrySuggestion => '建議開啟代理後重試';

  @override
  String get animeDownloadUnknownError => '未知錯誤';

  @override
  String animeDownloadFailedMessage(String chapter, String error) {
    return '$chapter 下載失敗：$error';
  }

  @override
  String get animeDownloadEmptyVideoUrl => '影片連結為空';

  @override
  String get pauseButton => '暫停';

  @override
  String get resumeButton => '繼續';

  @override
  String downloadProgressCount(String percent, int completed, int total) {
    return '$percent% ($completed/$total)';
  }

  @override
  String get commentSettingsAiSummarySection => 'AI 總結';

  @override
  String get commentSettingsEnableAiSummary => '啟用 AI 總結';

  @override
  String get commentSettingsAiSummaryEnabledDesc => '評論頂部顯示 AI 總結按鈕';

  @override
  String get commentSettingsAiSummaryDisabled => '未啟用';

  @override
  String get commentSettingsConfigureAiFirst => '請先在「我的 → AI配置」中配置 API 密鑰';

  @override
  String get commentSettingsCollapseAiComment => '折疊 AI 評論';

  @override
  String get commentSettingsCollapseAiCommentDesc => '開啟後 AI 評論預設折疊，生成中也保持折疊';

  @override
  String get commentSettingsAutoAiSummary => '自動 AI 總結';

  @override
  String commentSettingsAutoAiSummaryDesc(int count) {
    return '評論數 ≥ $count 條時自動生成';
  }

  @override
  String get commentSettingsMinCommentCount => '最少評論數';

  @override
  String get commentSettingsTriggerTiming => '呼叫時機';

  @override
  String get commentSettingsTimingOnOpen => '打開評論區時';

  @override
  String get commentSettingsTimingAfterPreload => '預載完成後';

  @override
  String get commentSettingsPreloadRequiredForTiming => '選擇「預載完成後」需要先開啟預載評論。';

  @override
  String get commentSettingsSpoilerAnalysis => '劇透分析';

  @override
  String get commentSettingsSpoilerAnalysisDesc => '開啟後會在目前提示詞後自動追加劇透分析要求';

  @override
  String get commentSettingsSpoilerWarn => '打開劇透評論彈出提醒';

  @override
  String get commentSettingsPromptPresets => '提示詞預設';

  @override
  String get commentSettingsBlacklistSection => '黑名單';

  @override
  String get commentSettingsBlacklistDesc => '長按評論可選擇「屏蔽用戶」，被屏蔽的評論將不再顯示。';

  @override
  String get commentSettingsClearBlacklist => '清空黑名單';

  @override
  String get commentSettingsAnonymousUser => '匿名用戶';

  @override
  String get commentSettingsRemoveFromBlacklist => '移出黑名單';

  @override
  String get profileFallbackQuestionWife => '我的老婆叫什麼？';

  @override
  String get profileFallbackQuestionFriend => '我的基友叫啥？';

  @override
  String get profileFallbackQuestionBestFriendCount => '我的好麻吉有幾個？';

  @override
  String get profileFallbackQuestionParentName => '我的父親(母親)叫什麽？';

  @override
  String get animeDetailSubtitleChip => '字幕';

  @override
  String animeDetailLatestChapter(String chapter) {
    return '最新：$chapter';
  }

  @override
  String get animeDetailOnAirChip => '連載中';

  @override
  String get animeDetailRestrictedChip => '受限';

  @override
  String animeDetailDirector(String name) {
    return '導演：$name';
  }

  @override
  String get playerSettingsPlaybackTitle => '播放設定';

  @override
  String get playerSettingsSkipSeconds => '快進秒數';

  @override
  String get playerSettingsSkipSecondsDesc => '動漫片頭一般約90秒';

  @override
  String get playerSettingsSecondsLabel => '秒數';

  @override
  String get readerSecondsSuffix => '秒';

  @override
  String get playerSettingsRecordProgress => '記錄播放進度';

  @override
  String get playerSettingsRecordProgressDesc => '再次打開同一集時自動跳轉到上次觀看位置';

  @override
  String get playerSettingsDanmakuTitle => '彈幕設定';

  @override
  String get playerSettingsShowDanmaku => '顯示彈幕';

  @override
  String get playerSettingsFontSize => '字體大小';

  @override
  String get playerSettingsDisplayArea => '顯示區域';

  @override
  String get playerSettingsOpacity => '透明度';

  @override
  String get playerSettingsDanmakuType => '彈幕類型';

  @override
  String get playerSettingsScrollDanmaku => '滾動彈幕';

  @override
  String get playerSettingsTopDanmaku => '頂部彈幕';

  @override
  String get playerSettingsBottomDanmaku => '底部彈幕';

  @override
  String get playerSettingsBlocklist => '屏蔽詞';

  @override
  String get playerSettingsBlocklistDesc => '包含屏蔽詞的彈幕將被自動過濾';

  @override
  String get playerSettingsBlocklistHint => '輸入屏蔽詞';

  @override
  String get playerSettingsDanmakuFont => '彈幕字體';

  @override
  String get playerSettingsDanmakuFontSystem => '跟隨系統';

  @override
  String get playerSettingsChineseConvertTooltip => '簡繁轉換';

  @override
  String get readerImageLinksRefreshed => '圖片連結已重新整理';

  @override
  String refreshFailedWithError(String error) {
    return '重新整理失敗：$error';
  }

  @override
  String get readerLocalChapterNoRefresh => '本地章節無需重新整理';

  @override
  String readerAutoSummaryFailed(String error) {
    return '背景自動總結失敗：$error';
  }

  @override
  String get readerNoPreviousChapter => '目前已無上一話';

  @override
  String get readerPreviousChapter => '上一章';

  @override
  String get readerPauseAutoScroll => '暫停自動滾動';

  @override
  String get readerAutoScrollWillResume => '自動滾動即將恢復';

  @override
  String get readerEnableAutoScroll => '開啟自動滾動';

  @override
  String get readerLoadingNextChapter => '正在載入下一話…';

  @override
  String get readerContinueScrollLoadNext => '繼續滾動載入下一話';

  @override
  String get readerAlreadyFirstChapter => '已經是第一章';

  @override
  String get readerContinuePageNextChapter => '繼續翻頁進入下一話';

  @override
  String get readerAlreadyLastChapter => '已經是最後一話';

  @override
  String get readerContinueScrollOrTapNextChapter => '繼續下滑或點擊按鈕進入下一話';

  @override
  String get readerImagePathCopied => '圖片路徑已複製到剪貼簿';

  @override
  String get readerImageUrlCopied => '圖片連結已複製到剪貼簿';

  @override
  String get readerLocalImageMissing => '本地圖片損壞或缺失';

  @override
  String get readerCopyImagePath => '複製圖片路徑';

  @override
  String readerImageRetrying(int attempt, int total) {
    return '載入失敗，正在重試 $attempt/$total';
  }

  @override
  String get readerReloadImage => '重新載入';

  @override
  String get readerCopyImageUrl => '複製圖片連結';

  @override
  String get updateAlreadyLatest => '目前已是最新版本';

  @override
  String get updateCheckFailedRetryLater => '檢查更新失敗，請稍後重試';

  @override
  String get updateOpenDownloadFailed => '無法開啟下載連結';

  @override
  String get updateNoReleaseNotes => '暫無更新說明';

  @override
  String get updateMirrorDownload => '鏡像下載';

  @override
  String get updateLatestBadge => '最新';

  @override
  String get updateCollapseOtherVersions => '收起其他版本';

  @override
  String updateViewMoreVersions(int count) {
    return '查看更多版本 ($count)';
  }

  @override
  String get updateCiBuildUnstable => 'CI 自動構建版本，不保證穩定性。';

  @override
  String get updateOpenReleasePage => '開啟發布頁';

  @override
  String get updatePackagesBeta => '安裝包（按版本號倒序）';

  @override
  String get updatePackages => '安裝包';

  @override
  String get updateSkipVersion => '跳過此版本';

  @override
  String get updateDisableAutoCheck => '取消自動檢查更新';

  @override
  String get updateInstallInApp => '應用內安裝';

  @override
  String get updateInstallInAppMirror => '鏡像應用內安裝';

  @override
  String updateDownloading(int percent) {
    return '下載中 $percent%';
  }

  @override
  String get updateDownloadFailed => '下載失敗，請稍後重試';

  @override
  String get updateInstallFailed => '無法啟動安裝，請改用瀏覽器下載';

  @override
  String get updateInstallPermissionNeeded => '需要「安裝未知應用」權限才能安裝更新';

  @override
  String get updateDownloadPreparing => '準備下載…';

  @override
  String get updateInstalling => '正在安裝…';

  @override
  String get updateCardChecking => '正在檢查更新…';

  @override
  String get updateCardLatest => '目前已是最新版本';

  @override
  String get updateCardFailed => '檢查更新失敗，點擊重試';

  @override
  String get updateCardRetry => '重試';

  @override
  String get updateButtonUpdate => '更新';

  @override
  String get updateManualDownload => '手動下載';

  @override
  String get updateUseMirror => '使用鏡像';

  @override
  String get totalRank => '總榜';

  @override
  String get maleAudience => '男生';

  @override
  String get femaleAudience => '女生';

  @override
  String get noticeRefreshFailed => '重新整理通知失敗，請稍後重試';

  @override
  String get noticeReadFailed => '讀取通知失敗';

  @override
  String get noticeAllMarkedRead => '所有通知已標記為已讀';

  @override
  String get noticeMarkAllReadTooltip => '全部已讀';

  @override
  String get noticeRefreshTooltip => '重新整理通知';

  @override
  String get noticeEmptyTitle => '暫無通知';

  @override
  String get noticeExpiredTitle => '過期通知';

  @override
  String get noticePinnedNodeSemantics => '置頂通知節點';

  @override
  String get noticeNodeSemantics => '通知節點';

  @override
  String get noticeOpenLink => '開啟連結';

  @override
  String get noticeUnreadSemantics => '未讀通知';

  @override
  String get noticeExpiredBadge => '已過期';

  @override
  String get readerImageViewerSettingsTooltip => '檢視器設定';

  @override
  String get resetButton => '重置';

  @override
  String get readerRotateLeft => '向左旋轉';

  @override
  String get readerRotateRight => '向右旋轉';

  @override
  String get readerImageViewerSettingsTitle => '圖片檢視器設定';

  @override
  String get readerAutoRotateLandscape => '橫向圖片自動旋轉';

  @override
  String get readerAutoRotateLandscapeDesc => '打開寬圖時自動旋轉 90 度';

  @override
  String get readerRotationDirection => '旋轉方向';

  @override
  String get readerRotateLeftShort => '向左';

  @override
  String get readerRotateRightShort => '向右';

  @override
  String get browseHistoryLastSeenLabel => '上次看到';

  @override
  String playerProgressAutoResumed(String progress) {
    return '$progress（已自動繼續）';
  }

  @override
  String get playerSeekButton => '跳轉';

  @override
  String get bangumiCommentsLoadFailed => '評論載入失敗';

  @override
  String get bangumiCommentsRetryHint => '下拉或點按按鈕重試';

  @override
  String get bangumiCommentsEmptyTitle => '還沒有評論';

  @override
  String get bangumiCommentsEmptySubtitle => '暫時沒有可顯示的 Bangumi 評論';

  @override
  String get bangumiCommentsLoadMoreFailed => '更多評論載入失敗';

  @override
  String get bangumiCommentsRetryLoadMore => '重試載入更多';

  @override
  String get bangumiCommentsLoadMore => '載入更多';

  @override
  String get bangumiCommentsEmptyComment => '這條評論沒有內容';

  @override
  String get danmakuSearchTitle => '彈幕搜尋';

  @override
  String danmakuSearchTitleWithCount(int count) {
    return '彈幕搜尋（$count）';
  }

  @override
  String danmakuLoadedTitle(int count) {
    return '已裝載$count發彈幕';
  }

  @override
  String get danmakuSearchHint => '輸入搜尋關鍵詞';

  @override
  String get forceRefreshTooltip => '強制重新整理';

  @override
  String get danmakuSearchInstruction => '請選擇分段或輸入搜尋詞後點擊搜尋';

  @override
  String danmakuSearchResultCount(int count) {
    return '共找到 $count 條結果';
  }

  @override
  String get danmakuSearchNoResults => '未找到相關彈幕';

  @override
  String get danmakuSearchNoResultsHint =>
      '減少關鍵詞，僅搜尋作品名稱\n如：「Re：從零開始的異世界生活第四季喪失篇」搜尋「從零開始的異世界生活第四季」';

  @override
  String get danmakuLabel => '彈幕';

  @override
  String get dandanplayBindingSearchKeyword => '搜尋關鍵詞';

  @override
  String get dandanplayBindingClear => '清除綁定';

  @override
  String dandanplayBindingSearchFailed(String error) {
    return '搜尋失敗：$error';
  }

  @override
  String get dandanplayBindingNoResults => '未找到相關番劇';

  @override
  String get dandanplayBindingSearchInstruction => '輸入關鍵詞後點擊搜尋';

  @override
  String get dandanplayBindingCurrent => '目前綁定';

  @override
  String get dandanplayBindingBound => '已綁定';

  @override
  String get dandanplayBindingUnbound => '未綁定';

  @override
  String get dandanplayBindingBind => '綁定';

  @override
  String dandanplayBindingRating(String rating) {
    return '評分 $rating';
  }

  @override
  String get dandanplayAlignmentTitle => '對齊彈幕';

  @override
  String get dandanplayAlignmentVideoFirstEpisode => '影片第一集';

  @override
  String get dandanplayAlignmentDanmakuFirstEpisode => '彈幕第一集';

  @override
  String get dandanplayAlignmentClear => '清除對齊';

  @override
  String get spoilerWarningTitle => '劇透警告';

  @override
  String get spoilerWarningContent => '真的要打開嗎？前方是地獄啊！';

  @override
  String get openButton => '打開';

  @override
  String get spoilerSuspectedComment => '這是一條高度劇透嫌疑的評論';

  @override
  String get spoilerTapToView => '含劇透，點擊查看';

  @override
  String get mediaKitDownloadTitle => '需要下載播放元件';

  @override
  String mediaKitDownloadMessage(String size) {
    return '首次使用動漫播放功能需下載播放元件（$size）。下載後會保存在本地，軟體更新無需重新下載。';
  }

  @override
  String get mediaKitDownloadSourceLabel => '下載來源';

  @override
  String get mediaKitDownloadSourceGithub => 'GitHub';

  @override
  String get mediaKitDownloadSourceGithubHint => '直連 GitHub 官方資源';

  @override
  String get mediaKitDownloadSourceMirror => '鏡像下載';

  @override
  String mediaKitDownloadSourceMirrorHint(String mirror) {
    return '使用目前鏡像：$mirror';
  }

  @override
  String get mediaKitDownloadConfirm => '開始下載';

  @override
  String get mediaKitDownloadingTitle => '正在下載播放元件';

  @override
  String get mediaKitDownloadFailedTitle => '下載失敗';

  @override
  String mediaKitDownloadFailed(String error) {
    return '下載播放元件失敗：$error';
  }

  @override
  String mediaKitInitFailed(String error) {
    return '播放器初始化失敗：$error';
  }

  @override
  String get mediaKitDownloadStageConnect => '正在連線…';

  @override
  String mediaKitDownloadBytesProgress(String received, String total) {
    return '$received / $total';
  }

  @override
  String mediaKitDownloadBytesOnly(String received) {
    return '已下載 $received';
  }

  @override
  String get mediaKitDownloadTimeout => '連線或下載逾時，請切換 GitHub/鏡像後重試';

  @override
  String get mediaKitDownloadNetworkError => '網路連線失敗，請檢查網路或切換下載來源';

  @override
  String get mediaKitDownloadStagePrepare => '準備中…';

  @override
  String get mediaKitDownloadStageDownload => '正在下載…';

  @override
  String get mediaKitDownloadStageVerify => '校驗檔案…';

  @override
  String get mediaKitDownloadStageExtract => '解壓元件…';

  @override
  String get mediaKitDownloadStageLoad => '載入元件…';

  @override
  String get mediaKitDownloadStageDone => '完成';
}
