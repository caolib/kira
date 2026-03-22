import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/chapter.dart';
import '../utils/reading_history.dart';
import 'reader_page.dart';

class ComicDetailPage extends StatefulWidget {
  final String pathWord;
  final String? lastBrowseId;
  final String? lastBrowseName;
  const ComicDetailPage({
    super.key,
    required this.pathWord,
    this.lastBrowseId,
    this.lastBrowseName,
  });

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  final _api = ApiClient();
  Comic? _comic;
  List<Chapter> _chapters = [];
  String _selectedGroup = 'default';
  bool _loadingComic = true;
  bool _loadingChapters = false;
  int _chapterTotal = 0;
  int _chapterPage = 0; // 当前页码（0-based）
  static const _pageSize = 100;
  bool _briefExpanded = false;
  bool _reversed = true;
  bool _isCollected = false;
  // 本地阅读记录（优先级高于书架传入的记录）
  String? _lastBrowseId;
  String? _lastBrowseName;
  int _lastBrowsePage = 1;

  @override
  void initState() {
    super.initState();
    _lastBrowseId = widget.lastBrowseId;
    _lastBrowseName = widget.lastBrowseName;
    _loadLocalHistory();
    _loadComic();
  }

  Future<void> _loadLocalHistory() async {
    final record = await ReadingHistory.get(widget.pathWord);
    if (record != null && mounted) {
      setState(() {
        _lastBrowseId = record.chapterUuid;
        _lastBrowseName = record.chapterName;
        _lastBrowsePage = record.page;
      });
    }
  }

  Future<void> _loadComic() async {
    try {
      final comic = await _api.getComicDetail(widget.pathWord);
      if (!mounted) return;
      setState(() {
        _comic = comic;
        _loadingComic = false;
        if (comic.groups != null && comic.groups!.isNotEmpty) {
          _selectedGroup = comic.groups!.keys.first;
        }
      });
      _loadChapterPage(0);
      // 查询收藏状态（不阻塞）
      _api.getComicQuery(widget.pathWord).then((query) {
        if (mounted) setState(() => _isCollected = query['collect'] != null);
      }).catchError((_) {});
    } catch (_) {
      if (mounted) setState(() => _loadingComic = false);
    }
  }

  Future<void> _loadChapterPage(int page) async {
    if (_loadingChapters) return;
    setState(() => _loadingChapters = true);
    try {
      final result = await _api.getChapterList(
        widget.pathWord,
        group: _selectedGroup,
        limit: _pageSize,
        offset: page * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _chapters = result.list;
        _chapterTotal = result.total;
        _chapterPage = page;
        _loadingChapters = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingChapters = false);
    }
  }

  int get _totalPages => (_chapterTotal / _pageSize).ceil();

  Future<void> _toggleCollect() async {
    final newState = !_isCollected;
    setState(() => _isCollected = newState);
    try {
      await _api.toggleCollect(_comic!.uuid!, collect: newState);
    } catch (_) {
      setState(() => _isCollected = !newState);
    }
  }

  List<Chapter> get _displayChapters =>
      _reversed ? _chapters.reversed.toList() : _chapters;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_comic?.name ?? ''),
        actions: [
          if (_comic != null)
            IconButton(
              icon: Icon(
                _isCollected ? Icons.bookmark : Icons.bookmark_border,
                color: _isCollected ? cs.primary : null,
              ),
              onPressed: _toggleCollect,
              tooltip: _isCollected ? '取消收藏' : '收藏',
            ),
        ],
      ),
      body: _loadingComic
          ? const Center(child: CircularProgressIndicator())
          : _comic == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      const Text('加载失败'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                          onPressed: _loadComic, child: const Text('重试')),
                    ],
                  ),
                )
              : _buildBody(cs, tt),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    final comic = _comic!;
    return CustomScrollView(
      slivers: [
        // ── 漫画信息卡片 ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: comic.cover,
                    width: 120,
                    height: 160,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 120,
                      height: 160,
                      color: cs.surfaceContainerHighest,
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 120,
                      height: 160,
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.broken_image,
                          color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (comic.authors.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                comic.authors.map((a) => a.name).join(' / '),
                                style: tt.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (comic.status != null)
                            _InfoChip(
                              icon: Icons.timelapse,
                              label: comic.status!['display'] ?? '',
                              color: cs.primaryContainer,
                              textColor: cs.onPrimaryContainer,
                            ),
                          if (comic.region != null)
                            _InfoChip(
                              icon: Icons.public,
                              label: comic.region!['display'] ?? '',
                              color: cs.secondaryContainer,
                              textColor: cs.onSecondaryContainer,
                            ),
                          ...comic.themes.map((t) => _InfoChip(
                                icon: Icons.label_outline,
                                label: t.name,
                                color: cs.tertiaryContainer,
                                textColor: cs.onTertiaryContainer,
                              )),
                        ],
                      ),
                      if (comic.popular > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.local_fire_department,
                                size: 16, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              _formatPopular(comic.popular),
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                      if (comic.datetimeUpdated != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.update,
                                size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              '更新于 ${comic.datetimeUpdated}',
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── 简介 ──
        if (comic.brief != null && comic.brief!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () =>
                    setState(() => _briefExpanded = !_briefExpanded),
                child: Text(
                  comic.brief!,
                  maxLines: _briefExpanded ? null : 3,
                  overflow: _briefExpanded ? null : TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        // ── 继续阅读 + 分组切换（响应式同行） ──
        if (_lastBrowseId != null ||
            (comic.groups != null && comic.groups!.length > 1))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_lastBrowseId != null)
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReaderPage(
                            pathWord: widget.pathWord,
                            chapterUuid: _lastBrowseId!,
                            chapterName: _lastBrowseName ?? '',
                            initialPage: _lastBrowsePage,
                          ),
                        ),
                      ).then((_) => _loadLocalHistory()),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text('继续  ${_lastBrowseName ?? ''}',
                          style: const TextStyle(fontSize: 13)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  if (comic.groups != null && comic.groups!.length > 1)
                    IntrinsicWidth(
                      child: SegmentedButton<String>(
                        segments: comic.groups!.entries
                            .map((e) => ButtonSegment(
                                  value: e.key,
                                  label:
                                      Text('${e.value.name}(${e.value.count})',
                                          style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        selected: {_selectedGroup},
                        onSelectionChanged: (v) {
                          setState(() => _selectedGroup = v.first);
                          _loadChapterPage(0);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // ── 章节标题 + 排序 + 分页 ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Icon(Icons.list, size: 20, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  '章节 ($_chapterTotal)',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_totalPages > 1) ...[
                  ...List.generate(_totalPages, (i) {
                    final isSelected = i == _chapterPage;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: isSelected
                          ? FilledButton.tonal(
                              onPressed: null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(36, 36),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('${i + 1}'),
                            )
                          : OutlinedButton(
                              onPressed: () => _loadChapterPage(i),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(36, 36),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text('${i + 1}'),
                            ),
                    );
                  }),
                ],
                IconButton(
                  icon: Icon(
                    _reversed ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 20,
                  ),
                  tooltip: _reversed ? '逆序（新→旧）' : '正序（旧→新）',
                  onPressed: () => setState(() => _reversed = !_reversed),
                ),
              ],
            ),
          ),
        ),
        // ── 章节网格 ──
        if (_loadingChapters)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final ch = _displayChapters[i];
                  return Material(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReaderPage(
                            pathWord: widget.pathWord,
                            chapterUuid: ch.uuid,
                            chapterName: ch.name,
                          ),
                        ),
                      ).then((_) => _loadLocalHistory()),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ch.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: tt.bodySmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ch.size}P',
                                textAlign: TextAlign.center,
                                style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: _displayChapters.length,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                mainAxisExtent: 52,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  static String _formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
