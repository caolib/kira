part of '../home_page.dart';

// ── Banner ──

class _MangaBannerItem {
  final String cover;
  final String title;
  final String brief;
  final Comic? comic;

  const _MangaBannerItem({
    required this.cover,
    required this.title,
    required this.brief,
    this.comic,
  });

  factory _MangaBannerItem.fromBanner(MangaBanner banner) {
    final comic = banner.comic;
    final title = comic != null && comic.name.isNotEmpty
        ? comic.name
        : banner.brief;
    return _MangaBannerItem(
      cover: banner.cover.isNotEmpty ? banner.cover : (comic?.cover ?? ''),
      title: title,
      brief: banner.brief,
      comic: comic,
    );
  }
}

class _MangaBannerCarousel extends StatefulWidget {
  final List<_MangaBannerItem> items;
  final double hp;
  final ValueChanged<Comic> onTap;

  const _MangaBannerCarousel({
    required this.items,
    required this.hp,
    required this.onTap,
  });

  @override
  State<_MangaBannerCarousel> createState() => _MangaBannerCarouselState();
}

class _MangaBannerCarouselState extends State<_MangaBannerCarousel> {
  late final PageController _controller;
  Timer? _timer;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = _initialPage(widget.items.length);
    _controller = PageController(initialPage: _page);
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _MangaBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _page = _initialPage(widget.items.length);
      if (_controller.hasClients) {
        _controller.jumpToPage(_page);
      }
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.items.length <= 1) return;
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _nextPage(restartTimer: false),
    );
  }

  int _initialPage(int count) {
    return count > 1 ? count * 1000 : 0;
  }

  void _nextPage({bool restartTimer = true}) {
    if (!mounted || widget.items.length <= 1) return;
    if (!_controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _nextPage(restartTimer: restartTimer),
      );
      return;
    }
    _animateToPage(_page + 1, restartTimer: restartTimer);
  }

  void _animateToPage(int page, {bool restartTimer = true}) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    if (restartTimer) {
      _restartTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // banner 卡片严格按 16:9 固定比例：宽度 = 可用宽 − 两侧 padding，
        // 高度随之联动，保证任何窗口宽度下都不会被拉扁或压窄。
        final bannerWidth = math.max(1.0, constraints.maxWidth - widget.hp * 2);
        final bannerHeight = (bannerWidth / (16 / 9)).clamp(140.0, 240.0);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.hp),
          child: Column(
            children: [
              SizedBox(
                height: bannerHeight + 8,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _controller,
                      physics: const PageScrollPhysics(),
                      itemCount: widget.items.length > 1
                          ? null
                          : widget.items.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (_, i) {
                        final item = widget.items[i % widget.items.length];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _MangaBannerCard(
                              item: item,
                              onTap: item.comic == null
                                  ? null
                                  : () => widget.onTap(item.comic!),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (widget.items.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == _page % widget.items.length ? 16 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == _page % widget.items.length
                                ? cs.primary
                                : cs.onSurfaceVariant.withValues(alpha: 0.35),
                            borderRadius: AppRadius.fullR,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MangaBannerCard extends StatelessWidget {
  final _MangaBannerItem item;
  final VoidCallback? onTap;

  const _MangaBannerCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ComicCardSurface(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CoverBrightnessFilter(
              child: CachedNetworkImage(
                imageUrl: item.cover,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (_, _) =>
                    const _ImagePlaceholder(icon: Icons.book),
                errorWidget: (_, _, _) =>
                    const _ImagePlaceholder(icon: Icons.broken_image),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.title.isNotEmpty)
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (item.brief.isNotEmpty && item.brief != item.title) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.brief,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
