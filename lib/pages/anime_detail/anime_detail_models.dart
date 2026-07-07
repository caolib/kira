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

const _bangumiEpisodeCountKey = '话数';
const _bangumiAirStartKey = '放送开始';
const _bangumiOriginalWorkKey = '原作';
const _bangumiDirectorKey = '导演';
const _bangumiAirWeekdayKey = '放送星期';
const _bangumiOriginalIntroMarker = '[简介原文]';

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

  factory _AnimeIntroViewData.fromAnime(
    Anime anime,
    AppLocalizations l10n,
  ) => _AnimeIntroViewData(
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
      if (anime.bSubtitle) l10n.animeDetailSubtitleChip,
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
        : l10n.animeDetailLatestChapter(anime.lastChapter!['name'].toString()),
    primaryStat: (
      icon: Icons.local_fire_department,
      text: ComicCoverCard.formatPopular(anime.popular, l10n),
    ),
    secondaryStat: anime.count > 0
        ? (
            icon: Icons.video_collection_outlined,
            text: l10n.totalEpisodes(anime.count),
          )
        : null,
  );

  factory _AnimeIntroViewData.fromDandanplay(
    DandanplayBangumi bangumi, {
    required AppLocalizations l10n,
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
    if (bangumi.isOnAir) addChip(l10n.animeDetailOnAirChip);
    if (bangumi.isRestricted) addChip(l10n.animeDetailRestrictedChip);
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
    final episodeCountLabel = _formatEpisodeCountLabel(
      metadataMap[_bangumiEpisodeCountKey] ?? '',
      l10n,
    );

    return _AnimeIntroViewData(
      title: title,
      cover: cover,
      summary: summary,
      chips: chips,
      metaLine:
          [
            if ((metadataMap[_bangumiAirStartKey] ?? '').isNotEmpty)
              metadataMap[_bangumiAirStartKey]!,
            if ((metadataMap[_bangumiOriginalWorkKey] ?? '').isNotEmpty)
              metadataMap[_bangumiOriginalWorkKey]!,
          ].join(' · ').trim().isEmpty
          ? null
          : [
              if ((metadataMap[_bangumiAirStartKey] ?? '').isNotEmpty)
                metadataMap[_bangumiAirStartKey]!,
              if ((metadataMap[_bangumiOriginalWorkKey] ?? '').isNotEmpty)
                metadataMap[_bangumiOriginalWorkKey]!,
            ].join(' · '),
      subMetaLine: (metadataMap[_bangumiDirectorKey] ?? '').isNotEmpty
          ? l10n.animeDetailDirector(metadataMap[_bangumiDirectorKey]!)
          : null,
      extraInfoLines: extraLines,
      primaryStat: bangumi.rating > 0
          ? (icon: Icons.star_rounded, text: bangumi.rating.toStringAsFixed(1))
          : (fallbackAnime != null
                ? (
                    icon: Icons.local_fire_department,
                    text: ComicCoverCard.formatPopular(
                      fallbackAnime.popular,
                      l10n,
                    ),
                  )
                : null),
      secondaryStat: episodeCountLabel != null
          ? (icon: Icons.video_collection_outlined, text: episodeCountLabel)
          : ((metadataMap[_bangumiEpisodeCountKey] ?? '').isNotEmpty
                ? null
                : (bangumi.episodes.isNotEmpty
                      ? (
                          icon: Icons.video_collection_outlined,
                          text: l10n.totalEpisodes(bangumi.episodes.length),
                        )
                      : (fallbackAnime != null && fallbackAnime.count > 0
                            ? (
                                icon: Icons.video_collection_outlined,
                                text: l10n.totalEpisodes(fallbackAnime.count),
                              )
                            : null))),
      headerMetadata: [
        if ((metadataMap[_bangumiAirWeekdayKey] ?? '').isNotEmpty)
          (
            icon: Icons.calendar_today_outlined,
            text: metadataMap[_bangumiAirWeekdayKey]!,
          ),
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
      item.startsWith('$_bangumiEpisodeCountKey:') ||
      item.startsWith('$_bangumiAirWeekdayKey:');

  static String? _formatEpisodeCountLabel(String raw, AppLocalizations l10n) {
    final value = raw.trim();
    if (value.isEmpty || value == '*') return null;
    final matched = RegExp(r'\d+').firstMatch(value)?.group(0);
    if (matched != null && matched.isNotEmpty) {
      return l10n.totalEpisodes(int.parse(matched));
    }
    return null;
  }

  static String _cleanBangumiSummary(String? summary, String? intro) {
    final raw = (summary ?? '').trim();
    if (raw.isEmpty) return (intro ?? '').trim();
    final markerIndex = raw.indexOf(_bangumiOriginalIntroMarker);
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
