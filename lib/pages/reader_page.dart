import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../models/chapter.dart';

class ReaderPage extends StatefulWidget {
  final String pathWord;
  final String chapterUuid;
  final String chapterName;

  const ReaderPage({
    super.key,
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _api = ApiClient();
  final _scrollController = ScrollController();
  ChapterDetail? _detail;
  bool _loading = true;
  bool _showToolbar = false;
  late String _currentUuid;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _currentUuid = widget.chapterUuid;
    _loadChapter();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadChapter() async {
    setState(() => _loading = true);
    try {
      final detail =
          await _api.getChapterDetail(widget.pathWord, _currentUuid);
      setState(() {
        _detail = detail;
        _loading = false;
        _currentPage = 1;
      });
      _scrollController.jumpTo(0);
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _goChapter(String? uuid) {
    if (uuid == null) return;
    _currentUuid = uuid;
    _loadChapter();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_detail != null)
            GestureDetector(
              onTap: () => setState(() => _showToolbar = !_showToolbar),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (_detail != null &&
                      n.metrics.pixels > 0 &&
                      n.metrics.maxScrollExtent > 0) {
                    final page = (_detail!.contents.length *
                            n.metrics.pixels /
                            n.metrics.maxScrollExtent)
                        .ceil()
                        .clamp(1, _detail!.contents.length);
                    if (page != _currentPage) {
                      setState(() => _currentPage = page);
                    }
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _detail!.contents.length,
                  itemBuilder: (_, i) {
                    return CachedNetworkImage(
                      imageUrl: _detail!.contents[i],
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      placeholder: (_, _) => Container(
                        height: 400,
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        height: 400,
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image,
                                  color: cs.onSurfaceVariant, size: 48),
                              const SizedBox(height: 8),
                              Text('加载失败',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // 顶部栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showToolbar ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          _detail?.name ?? widget.chapterName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 底部栏
          if (_detail != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _showToolbar ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: _detail!.prev != null
                              ? () => _goChapter(_detail!.prev)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('上一章'),
                          style: TextButton.styleFrom(
                            foregroundColor: _detail!.prev != null
                                ? Colors.white
                                : Colors.white38,
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '$_currentPage / ${_detail!.contents.length}',
                                style: TextStyle(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _detail!.next != null
                              ? () => _goChapter(_detail!.next)
                              : null,
                          icon: const Text('下一章'),
                          label: const Icon(Icons.chevron_right),
                          style: TextButton.styleFrom(
                            foregroundColor: _detail!.next != null
                                ? Colors.white
                                : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
