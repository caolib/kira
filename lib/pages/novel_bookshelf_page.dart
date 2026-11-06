import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/novel/novel_api.dart';
import '../l10n/app_localizations.dart';
import '../models/api_ordering.dart';
import '../models/novel.dart';
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../providers/novel_providers.dart';
import '../repositories/novel_bookshelf_repository.dart';
import '../routing/app_router.dart';
import '../routing/branch_activation.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';
import '../utils/app_logger.dart';
import '../utils/network_error.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/app_sheet.dart';
import '../widgets/back_to_top_button.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/login_expired_dialog.dart';
import '../widgets/novel_hero_tags.dart';
import '../widgets/novel_widgets.dart';
import '../widgets/ordering_tile.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/update_badge.dart';

/// 与漫画书架同款：封面网格 + 30 分钟缓存 + tab 激活/回前台时静默刷新。
class NovelBookshelfPage extends ConsumerStatefulWidget {
  const NovelBookshelfPage({
    super.key,
    this.active = false,
    this.onTotalChanged,
  });

  final bool active;
  final ValueChanged<int>? onTotalChanged;

  @override
  ConsumerState<NovelBookshelfPage> createState() => _NovelBookshelfPageState();
}

class _NovelBookshelfPageState extends ConsumerState<NovelBookshelfPage>
    with WidgetsBindingObserver, BranchDeferredInit {
  static const _showUpdateOnlyKey = 'local_novel_bookshelf_show_update_only';

  late final UserManager _user = ref.read(userManagerProvider);
  late final NovelBookshelfRepository _repo = ref.read(novelShelfRepoProvider);
  NovelApi get _api => ref.read(novelApiProvider);
  final _scrollController = ScrollController();
  Timer? _cacheTimeTimer;
  List<NovelShelfEntry> _items = [];
  int _offset = 0;
  int _total = 0;
  DateTime? _cacheTime;
  bool _loading = true;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _forceLoading = false;
  bool _failed = false;
  String? _loadError;
  bool _moreFailed = false;
  String? _moreError;
  bool _unauthorized = false;
  bool _showingLoginPrompt = false;
  bool _showBackToTop = false;
  bool _showUpdateOnly = false;
  String _ordering = ApiOrdering.datetimeModifier;
  final Set<String> _removing = {};
  late String _scope;
  int _generation = 0;
  int _accountGeneration = 0;
  Future<void>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _scope = _api.cacheScope;
    WidgetsBinding.instance.addObserver(this);
    _user.addListener(_onAccountChanged);
    _repo.addListener(_onShelfInvalidated);
    _cacheTimeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    deferInitialLoadToBranchActivation();
  }

  @override
  void onBranchFirstActivated() {
    unawaited(_loadShowUpdateOnly());
    if (_user.isCopyLoggedIn) {
      unawaited(_load());
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cacheTimeTimer?.cancel();
    _scrollController.dispose();
    _user.removeListener(_onAccountChanged);
    _repo.removeListener(_onShelfInvalidated);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      _ensureFresh();
    }
  }

  @override
  void didUpdateWidget(covariant NovelBookshelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _ensureFresh();
    }
    if (oldWidget.onTotalChanged != widget.onTotalChanged) {
      _notifyTotalChanged();
    }
  }

  void _notifyTotalChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTotalChanged?.call(_total);
    });
  }

  void _ensureFresh() {
    if (!_user.isCopyLoggedIn || _unauthorized || _refreshing || _loading) {
      return;
    }
    final cacheTime = _cacheTime;
    if (cacheTime != null &&
        DateTime.now().difference(cacheTime) <
            NovelBookshelfRepository.cacheTtl) {
      return;
    }
    unawaited(_load(force: true));
  }

  Future<void> _loadShowUpdateOnly() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_showUpdateOnlyKey);
    if (!mounted || value == null) return;
    setState(() => _showUpdateOnly = value);
  }

  void _setShowUpdateOnly(bool value) {
    if (_showUpdateOnly == value) return;
    setState(() => _showUpdateOnly = value);
    unawaited(_saveShowUpdateOnly(value));
  }

  Future<void> _saveShowUpdateOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showUpdateOnlyKey, value);
  }

  bool _isCurrent(int generation, String scope) =>
      mounted &&
      generation == _generation &&
      scope == _scope &&
      scope == _api.cacheScope;

  /// Retire every old first-page, refresh and pagination callback together.
  void _clearList() {
    ++_generation;
    _items = [];
    _offset = _total = 0;
    _cacheTime = null;
    _loading = _user.isCopyLoggedIn && !_unauthorized;
    _loadingMore = _refreshing = _forceLoading = false;
    _failed = _moreFailed = _showBackToTop = false;
    _loadFuture = null;
    _notifyTotalChanged();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    final scope = _api.cacheScope;
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      ++_accountGeneration;
      _unauthorized = false;
      _removing.clear();
      _clearList();
    });
    if (_user.isCopyLoggedIn) {
      unawaited(_load());
    }
  }

  void _onShelfInvalidated() {
    if (!mounted || _repo.invalidatedScope != _scope || _unauthorized) {
      return;
    }
    setState(_clearList);
    if (_user.isCopyLoggedIn) unawaited(_load(force: true));
  }

  Future<void> _load({bool silent = true, bool force = false}) {
    if (!_user.isCopyLoggedIn || _unauthorized) return Future.value();
    if (_refreshing && (!force || _forceLoading)) {
      return _loadFuture ?? Future.value();
    }
    final generation = ++_generation;
    final scope = _scope;
    final ordering = _ordering;
    setState(() {
      _refreshing = true;
      _forceLoading = force;
      _loading = _items.isEmpty;
      _loadingMore = _failed = _moreFailed = false;
      _moreError = null;
    });
    return _loadFuture = _performLoad(
      generation,
      scope,
      ordering,
      silent,
      force,
    );
  }

  Future<void> _performLoad(
    int generation,
    String scope,
    String ordering,
    bool silent,
    bool force,
  ) async {
    try {
      final data = force
          ? await _repo.forceRefreshApi(ordering: ordering)
          : await _repo.load(ordering: ordering);
      if (!_isCurrent(generation, scope)) {
        return;
      }
      setState(() {
        _items = _unique(data.items);
        _total = data.total;
        _offset = data.nextOffset;
        _cacheTime = data.cacheTime;
        _loadError = null;
      });
      _notifyTotalChanged();
      if (!silent && mounted) {
        showToast(context, AppLocalizations.of(context)!.refreshSuccess);
      }
    } catch (error, stack) {
      if (!_isCurrent(generation, scope)) {
        return;
      }
      _log(error, stack, 'load');
      if (_isUnauthorized(error)) {
        await _handleUnauthorized();
      } else {
        setState(() {
          _failed = true;
          _loadError = NetworkError.message(error);
        });
        if (!silent && mounted) {
          final l10n = AppLocalizations.of(context)!;
          showToast(
            context,
            l10n.refreshFailedDetail(NetworkError.message(error, l10n: l10n)),
            isError: true,
          );
        }
      }
    } finally {
      if (_isCurrent(generation, scope)) {
        setState(() {
          _loading = _refreshing = _forceLoading = false;
          _loadFuture = null;
        });
      }
    }
  }

  List<NovelShelfEntry> _unique(Iterable<NovelShelfEntry> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(
          item.book.uuid.isNotEmpty ? item.book.uuid : item.book.pathWord,
        ))
          item,
    ];
  }

  Future<void> _loadMore({bool retry = false}) async {
    if (_loading ||
        _loadingMore ||
        _refreshing ||
        _unauthorized ||
        (_moreFailed && !retry) ||
        _offset >= _total) {
      return;
    }
    final generation = _generation;
    final scope = _scope;
    final offset = _offset;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
      _moreError = null;
    });
    try {
      final page = await _repo.loadPage(offset: offset, ordering: _ordering);
      if (!_isCurrent(generation, scope)) {
        return;
      }
      setState(() {
        _items = _unique([..._items, ...page.list]);
        _total = page.total;
        final next = page.offset + page.list.length;
        _offset = next > offset ? next : _total;
      });
      _notifyTotalChanged();
    } catch (error, stack) {
      if (!_isCurrent(generation, scope)) {
        return;
      }
      _log(error, stack, 'load_more');
      if (_isUnauthorized(error)) {
        await _handleUnauthorized();
      } else {
        setState(() {
          _moreFailed = true;
          _moreError = NetworkError.message(error);
        });
      }
    } finally {
      if (_isCurrent(generation, scope)) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _log(Object error, StackTrace stack, String operation) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'novel_bookshelf.$operation',
      ),
    );
  }

  bool _isUnauthorized(Object error) =>
      (error is NovelApiException && error.isUnauthorized) ||
      (error is DioException && error.response?.statusCode == 401);

  Future<void> _handleUnauthorized() async {
    if (!mounted) return;
    final account = _accountGeneration;
    setState(() {
      _unauthorized = true;
      _clearList();
    });
    // COPY expiry must not log out the independent HOT account. Clear the
    // actionable list even when an earlier account's prompt is still open.
    try {
      await _repo.invalidateCache();
    } catch (error, stack) {
      _log(error, stack, 'expire_cache');
    }
    if (!mounted || account != _accountGeneration || _showingLoginPrompt) {
      return;
    }
    _showingLoginPrompt = true;
    final login = await showLoginExpiredDialog(
      context,
      content: AppLocalizations.of(context)!.loginExpiredBookshelfContent,
    );
    _showingLoginPrompt = false;
    if (mounted && account == _accountGeneration && login) await _login();
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _login() async {
    await context.pushNamed(
      AppRoutes.login,
      queryParameters: {'copyOnly': 'true'},
    );
    if (mounted && _user.isCopyLoggedIn) {
      setState(() => _unauthorized = false);
      await _load(force: true);
    }
  }

  Future<void> _openBook(NovelBook book, String? heroTagBase) async {
    final generation = _generation;
    await context.pushNamed(
      AppRoutes.novelDetail,
      pathParameters: {'pathWord': book.pathWord},
      extra: NovelDetailExtra(initialBook: book, heroTagBase: heroTagBase),
    );
    // Also update browse ordering / update badges after returning from reading.
    // Collection notifications already started their own refresh, even empty.
    if (mounted && generation == _generation) await _load(force: true);
  }

  Future<void> _uncollect(NovelBook book) async {
    if (!_user.isCopyLoggedIn ||
        _unauthorized ||
        book.uuid.isEmpty ||
        !_removing.add(book.pathWord)) {
      return;
    }
    final account = _accountGeneration;
    final scope = _scope;
    setState(() {});
    try {
      await _repo.setCollected(bookUuid: book.uuid, collected: false);
    } catch (error, stack) {
      if (!mounted ||
          account != _accountGeneration ||
          scope != _api.cacheScope) {
        return;
      }
      _log(error, stack, 'uncollect');
      if (_isUnauthorized(error)) {
        await _handleUnauthorized();
      } else {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          l10n.novelCollectFailedDetail(novelErrorMessage(error)),
          isError: true,
        );
      }
    } finally {
      if (mounted && account == _accountGeneration) {
        setState(() => _removing.remove(book.pathWord));
      }
    }
  }

  Future<void> _confirmUncollect(NovelBook book) async {
    final account = _accountGeneration;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showAppSheet<bool>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              Icons.favorite_border,
              color: AppStatusColors.danger(cs),
            ),
            title: Text(l10n.novelUncollect),
            subtitle: Text(
              book.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
    if (mounted && account == _accountGeneration && confirmed == true) {
      await _uncollect(book);
    }
  }

  String _orderingLabel(AppLocalizations l10n) => switch (_ordering) {
    ApiOrdering.datetimeUpdated => l10n.sortByUpdate,
    ApiOrdering.datetimeBrowse => l10n.sortByRead,
    _ => l10n.sortByFavorite,
  };

  void _setOrdering(String ordering) {
    Navigator.pop(context);
    if (_ordering == ordering) return;
    setState(() {
      _ordering = ordering;
      _clearList();
    });
    unawaited(_load());
  }

  void _showOrderingSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showAppSheet<void>(
      context,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                l10n.sortMethod,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OrderingTile(
              icon: Icons.update,
              title: l10n.sortByUpdateTime,
              subtitle: l10n.sortByUpdateTimeDesc(l10n.novelTitle),
              selected: _ordering == ApiOrdering.datetimeUpdated,
              onTap: () => _setOrdering(ApiOrdering.datetimeUpdated),
            ),
            OrderingTile(
              icon: Icons.favorite_border,
              title: l10n.sortByFavoriteTime,
              subtitle: l10n.sortByFavoriteTimeDesc,
              selected: _ordering == ApiOrdering.datetimeModifier,
              onTap: () => _setOrdering(ApiOrdering.datetimeModifier),
            ),
            OrderingTile(
              icon: Icons.history,
              title: l10n.sortByBrowseTime,
              subtitle: l10n.sortByBrowseTimeDesc,
              selected: _ordering == ApiOrdering.datetimeBrowse,
              onTap: () => _setOrdering(ApiOrdering.datetimeBrowse),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  String get _cacheTimeLabel {
    final cacheTime = _cacheTime;
    if (cacheTime == null) return '';
    final l10n = AppLocalizations.of(context)!;
    return l10n.refreshedAt(TimeFormat.relative(cacheTime, l10n));
  }

  Widget _buildToolbar(BuildContext context, double hp) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, AppSpacing.xs, hp, AppSpacing.sm),
      child: Row(
        children: [
          FilterChip(
            label: Text(l10n.hasUpdate),
            selected: _showUpdateOnly,
            onSelected: _setShowUpdateOnly,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _cacheTimeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.sort, size: AppIconSize.md),
            label: Text(_orderingLabel(l10n)),
            onPressed: () => _showOrderingSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {bool noUpdates = false}) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            noUpdates ? Icons.check_circle_outline : Icons.favorite_border,
            size: noUpdates ? AppIconSize.empty : AppIconSize.display,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            noUpdates ? l10n.noNovelUpdates : l10n.novelEmptyShelf,
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (!noUpdates) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.goFindSomething(l10n.novelTitle),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: _refreshing
                ? null
                : () => unawaited(_load(silent: false, force: true)),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.refreshButton),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfGrid(double hp, double cardExtent) {
    final filtered = _showUpdateOnly
        ? _items.where((entry) => entry.hasUpdate).toList()
        : _items;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          final entry = filtered[i];
          final heroTagBase = NovelHeroTags.base(
            scope: 'novel-bookshelf',
            pathWord: entry.book.pathWord,
            index: i,
          );
          return Stack(
            children: [
              NovelBookCard(
                book: entry.book,
                heroTagBase: heroTagBase,
                onTap: () => _openBook(entry.book, heroTagBase),
                subtitle: entry.lastBrowseName,
                onLongPress: _removing.contains(entry.book.pathWord)
                    ? null
                    : () => unawaited(_confirmUncollect(entry.book)),
              ),
              if (entry.hasUpdate) const UpdateBadge(),
            ],
          );
        }, childCount: filtered.length),
        gridDelegate: _gridDelegate(cardExtent),
      ),
    );
  }

  SliverGridDelegate _gridDelegate(double extent) =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: extent,
        childAspectRatio: 0.55,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);
    return Scaffold(
      floatingActionButton: _showBackToTop
          ? BackToTopButton(onPressed: _scrollToTop)
          : null,
      body: !_user.isCopyLoggedIn || _unauthorized
          ? SafeArea(
              child: NovelEmptyView(
                message: l10n.novelCopyLoginRequired,
                icon: Icons.person_outline,
                action: FilledButton(
                  onPressed: _login,
                  child: Text(l10n.novelCopyLogin),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(silent: false, force: true),
              edgeOffset: MediaQuery.paddingOf(context).top,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis == Axis.vertical) {
                    final show = notification.metrics.pixels > 400;
                    if (show != _showBackToTop) {
                      setState(() => _showBackToTop = show);
                    }
                    if (notification.metrics.pixels > 0 &&
                        notification.metrics.pixels >
                            notification.metrics.maxScrollExtent - 300) {
                      unawaited(_loadMore());
                    }
                  }
                  return false;
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverAppBar(
                      floating: true,
                      snap: true,
                      automaticallyImplyLeading: false,
                      toolbarHeight: 0,
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(60),
                        child: _buildToolbar(context, hp),
                      ),
                    ),
                    if (_refreshing && !_loading)
                      const SliverToBoxAdapter(
                        child: LinearProgressIndicator(),
                      ),
                    if (_failed && _items.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: hp),
                        sliver: SliverToBoxAdapter(
                          child: InlineRetryNotice(
                            message: _loadError ?? l10n.refreshFailed,
                            onRetry: () => unawaited(_load(force: true)),
                          ),
                        ),
                      ),
                    if (_loading)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: hp),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (_, _) =>
                                const ShimmerShell(child: ComicCardSkeleton()),
                            childCount: 12,
                          ),
                          gridDelegate: _gridDelegate(cardExtent),
                        ),
                      )
                    else if (_failed && _items.isEmpty)
                      SliverErrorRetryView(
                        message: _loadError,
                        onRetry: () => unawaited(_load(force: true)),
                      )
                    else if (_items.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(context),
                      )
                    else if (_showUpdateOnly &&
                        _items.every((entry) => !entry.hasUpdate))
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(context, noUpdates: true),
                      )
                    else
                      _buildShelfGrid(hp, cardExtent),
                    if (!_loading && _offset < _total)
                      SliverToBoxAdapter(
                        child: LoadMoreFooter(
                          loading: _loadingMore,
                          onPressed: () => unawaited(_loadMore(retry: true)),
                          label: _moreFailed
                              ? l10n.retryButton
                              : l10n.loadMoreProgress(_offset, _total),
                          detail: _moreFailed ? _moreError : null,
                          horizontalPadding: hp,
                        ),
                      ),
                    const SliverPadding(
                      padding: EdgeInsets.only(bottom: AppSpacing.xl),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
