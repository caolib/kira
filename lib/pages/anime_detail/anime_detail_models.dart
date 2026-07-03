part of '../anime_detail_page.dart';

class _DandanplayBindingDialogResult {
  final DandanplayBindingRecord? record;
  final bool clear;

  const _DandanplayBindingDialogResult._({this.record, this.clear = false});

  const _DandanplayBindingDialogResult.bind(DandanplayBindingRecord record)
    : this._(record: record);

  const _DandanplayBindingDialogResult.clear() : this._(clear: true);
}

class _DandanplayAlignmentResult {
  final int? chapterIndex;
  final int? episodeIndex;
  final bool clear;

  const _DandanplayAlignmentResult.align({
    required int this.chapterIndex,
    required int this.episodeIndex,
  }) : clear = false;

  const _DandanplayAlignmentResult.clear()
    : chapterIndex = null,
      episodeIndex = null,
      clear = true;
}

class _AnimeIntroViewData {
  final String title;
  final String cover;
  final String summary;
  final List<String> chips;
  final String? metaLine;
  final String? subMetaLine;
  final List<String> extraInfoLines;
  final ({IconData icon, String text})? primaryStat;
  final ({IconData icon, String text})? secondaryStat;
  final List<({IconData icon, String text})> headerMetadata;

  const _AnimeIntroViewData({
    required this.title,
    required this.cover,
    required this.summary,
    this.chips = const [],
    this.metaLine,
    this.subMetaLine,
    this.extraInfoLines = const [],
    this.primaryStat,
    this.secondaryStat,
    this.headerMetadata = const [],
  });

  factory _AnimeIntroViewData.fromAnime(Anime anime) => _AnimeIntroViewData(
    title: anime.name,
    cover: anime.cover,
    summary: anime.brief?.trim() ?? '',
    chips: [
      if (anime.category?['display'] != null)
        anime.category!['display'].toString(),
      if (anime.cartoonType?['display'] != null)
        anime.cartoonType!['display'].toString(),
      if (anime.grade?['display'] != null) anime.grade!['display'].toString(),
      if (anime.freeType?['display'] != null)
        anime.freeType!['display'].toString(),
      if (anime.bSubtitle) '字幕',
      ...anime.themes
          .map((e) => e.name)
          .where((item) => item.trim().isNotEmpty),
    ],
    metaLine:
        [
          if (anime.company != null) anime.company!.name,
          if (anime.years != null) anime.years!,
        ].where((item) => item.trim().isNotEmpty).join(' · ').trim().isEmpty
        ? null
        : [
            if (anime.company != null) anime.company!.name,
            if (anime.years != null) anime.years!,
          ].where((item) => item.trim().isNotEmpty).join(' · '),
    subMetaLine: anime.lastChapter?['name'] == null
        ? null
        : '最新：${anime.lastChapter!['name']}',
    primaryStat: (
      icon: Icons.local_fire_department,
      text: ComicCoverCard.formatPopular(anime.popular),
    ),
    secondaryStat: anime.count > 0
        ? (icon: Icons.video_collection_outlined, text: '共 ${anime.count} 集')
        : null,
  );

  factory _AnimeIntroViewData.fromDandanplay(
    DandanplayBangumi bangumi, {
    Anime? fallbackAnime,
  }) {
    final metadataMap = _bangumiMetadataMap(bangumi.metadata);
    final summary = _cleanBangumiSummary(bangumi.summary, bangumi.intro);
    final title = bangumi.animeTitle.trim().isNotEmpty
        ? bangumi.animeTitle.trim()
        : fallbackAnime?.name ?? '';
    final cover = bangumi.imageUrl?.trim().isNotEmpty == true
        ? bangumi.imageUrl!.trim()
        : fallbackAnime?.cover ?? '';
    final chips = <String>[];
    void addChip(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || chips.contains(trimmed)) return;
      chips.add(trimmed);
    }

    if ((bangumi.typeDescription ?? '').trim().isNotEmpty) {
      addChip(bangumi.typeDescription!);
    }
    if (bangumi.isOnAir) addChip('连载中');
    if (bangumi.isRestricted) addChip('受限');
    for (final item
        in bangumi.metadata.where((item) => item.contains(':')).take(6)) {
      addChip(item.split(':').first);
    }
    final extraLines = <String>[
      if ((bangumi.intro ?? '').trim().isNotEmpty) bangumi.intro!.trim(),
      ...bangumi.metadata.where(
        (item) =>
            !_isHeaderMetadata(item) &&
            item.trim().isNotEmpty &&
            item.trim() != (bangumi.intro ?? '').trim(),
      ),
    ];
    final episodeCountLabel = _formatEpisodeCountLabel(metadataMap['话数'] ?? '');

    return _AnimeIntroViewData(
      title: title,
      cover: cover,
      summary: summary,
      chips: chips,
      metaLine:
          [
            if ((metadataMap['放送开始'] ?? '').isNotEmpty) metadataMap['放送开始']!,
            if ((metadataMap['原作'] ?? '').isNotEmpty) metadataMap['原作']!,
          ].join(' · ').trim().isEmpty
          ? null
          : [
              if ((metadataMap['放送开始'] ?? '').isNotEmpty) metadataMap['放送开始']!,
              if ((metadataMap['原作'] ?? '').isNotEmpty) metadataMap['原作']!,
            ].join(' · '),
      subMetaLine: (metadataMap['导演'] ?? '').isNotEmpty
          ? '导演：${metadataMap['导演']}'
          : null,
      extraInfoLines: extraLines,
      primaryStat: bangumi.rating > 0
          ? (icon: Icons.star_rounded, text: bangumi.rating.toStringAsFixed(1))
          : (fallbackAnime != null
                ? (
                    icon: Icons.local_fire_department,
                    text: ComicCoverCard.formatPopular(fallbackAnime.popular),
                  )
                : null),
      secondaryStat: episodeCountLabel != null
          ? (icon: Icons.video_collection_outlined, text: episodeCountLabel)
          : ((metadataMap['话数'] ?? '').isNotEmpty
                ? null
                : (bangumi.episodes.isNotEmpty
                      ? (
                          icon: Icons.video_collection_outlined,
                          text: '共 ${bangumi.episodes.length} 集',
                        )
                      : (fallbackAnime != null && fallbackAnime.count > 0
                            ? (
                                icon: Icons.video_collection_outlined,
                                text: '共 ${fallbackAnime.count} 集',
                              )
                            : null))),
      headerMetadata: [
        if ((metadataMap['放送星期'] ?? '').isNotEmpty)
          (icon: Icons.calendar_today_outlined, text: metadataMap['放送星期']!),
      ],
    );
  }

  static Map<String, String> _bangumiMetadataMap(List<String> metadata) {
    final result = <String, String>{};
    for (final item in metadata) {
      final index = item.indexOf(':');
      if (index <= 0 || index >= item.length - 1) continue;
      final key = item.substring(0, index).trim();
      final value = item.substring(index + 1).trim();
      if (key.isEmpty || value.isEmpty || result.containsKey(key)) continue;
      result[key] = value;
    }
    return result;
  }

  static bool _isHeaderMetadata(String item) =>
      item.startsWith('话数:') || item.startsWith('放送星期:');

  static String? _formatEpisodeCountLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '*') return null;
    final matched = RegExp(r'\d+').firstMatch(value)?.group(0);
    if (matched != null && matched.isNotEmpty) {
      return '共 ${int.parse(matched)} 集';
    }
    return null;
  }

  static String _cleanBangumiSummary(String? summary, String? intro) {
    final raw = (summary ?? '').trim();
    if (raw.isEmpty) return (intro ?? '').trim();
    final markerIndex = raw.indexOf('[简介原文]');
    final cleaned = markerIndex >= 0 ? raw.substring(0, markerIndex) : raw;
    final normalized = cleaned
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n\n');
    return normalized.isNotEmpty ? normalized : (intro ?? '').trim();
  }
}

String _formatDandanplayEpisodeLabel(DandanplayBangumiEpisode episode) {
  final number = episode.episodeNumber.trim();
  final title = episode.episodeTitle.trim();
  if (title.isNotEmpty) return title;
  if (number.isNotEmpty) return number;
  return '#${episode.episodeId}';
}
