import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/api_ordering.dart';
import '../models/comic.dart' as m;
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../repositories/search_init_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/app_logger.dart';
import '../utils/screen_layout.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/section_header.dart';
import 'home_page.dart' show ComicCard;

part 'search/discover_tab.dart';
part 'search/search_tab.dart';
part 'search/search_widgets.dart';

/// 搜索页容器：顶部两个标签页——「搜索」与「发现」。
///
/// 两者职责刻意分开，因为服务端能力不同：
/// - **搜索**：只有关键字，固定走 HOT 源的 `/api/v3/search/comic`；
/// - **发现**：没有搜索框，靠题材 tag / 大分类筛选，可在 HOT / COPY 两个源之间切换。
///
/// 这个接口差异是硬约束——`/api/v3/search/comic` 不认 `theme` / `top`，
/// 而 `/api/v3/comics` 不认关键字，所以两者无法合并成一个界面。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  final _user = UserManager();
  late final TabController _tabController = TabController(
    length: 2,
    // 冷启动回到上次停留的标签（「发现」页用得多的用户不必每次手动切）。
    initialIndex: _user.searchTabIndex,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// 只在滑动/切换真正停下时落盘，避免 [TabController] 动画期间频繁写入。
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    unawaited(_user.setSearchTabIndex(_tabController.index));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Column(
        children: [
          // 标签栏固定在顶部不参与滚动：两个 tab 的滚动区域各自独立。
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.searchTabLabel),
                Tab(text: l10n.discoverTabLabel),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_SearchTab(), _DiscoverTab()],
            ),
          ),
        ],
      ),
    );
  }
}
