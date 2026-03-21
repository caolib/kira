import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/chapter.dart';
import 'reader_page.dart';

class ComicDetailPage extends StatefulWidget {
  final String pathWord;
  const ComicDetailPage({super.key, required this.pathWord});

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  final _api = ApiClient();
  Comic? _comic;
  List<Chapter> _chapters = [];
  String _selectedGroup = 'default';
  bool _loading = true;
  int _chapterOffset = 0;
  int _chapterTotal = 0;
  bool _loadingChapters = false;
  bool _briefExpanded = false;
  bool _reversed = true; // 默认逆序（新章在前）
  bool _isCollected = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final comic = await _api.getComicDetail(widget.pathWord);
      final query = await _api.getComicQuery(widget.pathWord);
      setState(() {
        _comic = comic;
        _isCollected = query['collect'] != null;
        if (comic.groups != null && comic.groups!.isNotEmpty) {
          _selectedGroup = comic.groups!.keys.first;
        }
      });
      await _loadChapters();
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadChapters({bool reset = true}) async {
    if (_loadingChapters) return;
    _loadingChapters = true;
    if (reset) {
      _chapterOffset = 0;
      _chapters = [];
    }
    try {
      final result = await _api.getChapterList(
        widget.pathWord,
        group: _selectedGroup,
        offset: _chapterOffset,
      );
      setState(() {
        if (reset) {
          _chapters = result.list;
        } else {
          _chapters.addAll(result.list);
        }
        _chapterTotal = result.total;
        _chapterOffset = _chapters.length;
      });
    } catch (_) {}
    _loadingChapters = false;
  }

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

    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final comic = _comic!;
    return Scaffold(
      appBar: AppBar(
        title: Text(comic.name),
        actions: [
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
      body: CustomScrollView(
        slivers: [
          // ── 漫画信息卡片：封面 + 右侧详情 ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
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
                  // 右侧信息
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
                                  comic.authors
                                      .map((a) => a.name)
                                      .join(' / '),
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
                    overflow:
                        _briefExpanded ? null : TextOverflow.ellipsis,
                    style:
                        tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          // ── 分组切换 ──
          if (comic.groups != null && comic.groups!.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<String>(
                  segments: comic.groups!.entries
                      .map((e) => ButtonSegment(
                            value: e.key,
                            label: Text('${e.value.name}(${e.value.count})'),
                          ))
                      .toList(),
                  selected: {_selectedGroup},
                  onSelectionChanged: (v) {
                    setState(() => _selectedGroup = v.first);
                    _loadChapters();
                  },
                ),
              ),
            ),
          // ── 章节标题 + 排序 ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.list, size: 20, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '章节 ($_chapterTotal)',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _reversed ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 20,
                    ),
                    tooltip: _reversed ? '逆序（新→旧）' : '正序（旧→新）',
                    onPressed: () =>
                        setState(() => _reversed = !_reversed),
                  ),
                  if (_chapterOffset < _chapterTotal)
                    TextButton(
                      onPressed: () => _loadChapters(reset: false),
                      child: const Text('加载更多'),
                    ),
                ],
              ),
            ),
          ),
          // ── 章节网格 ──
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
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${ch.size}P',
                              style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: _displayChapters.length,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisExtent: 52,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
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
