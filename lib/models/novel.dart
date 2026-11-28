import '../utils/json_helpers.dart';

List<T> _models<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parse,
) => [
  for (final value in jsonList(json, key))
    if (value is Map) parse(jsonMap({'value': value}, 'value')!),
];

String? _optionalString(Map<String, dynamic> json, String key) =>
    jsonString(json, key).nullIfEmpty();

class NovelTag {
  final String name;
  final String pathWord;
  final int count;

  const NovelTag({required this.name, required this.pathWord, this.count = 0});

  factory NovelTag.fromJson(Map<String, dynamic> json) => NovelTag(
    name: jsonString(json, 'name'),
    pathWord: jsonString(json, 'path_word'),
    count: jsonInt(json, 'count'),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'path_word': pathWord,
    'count': count,
  };
}

/// Book identity is a path_word for URLs, and a UUID for member actions.
class NovelBook {
  final String pathWord;
  final String uuid;
  final String name;
  final String cover;
  final String brief;
  final List<NovelTag> authors;
  final List<NovelTag> themes;
  final List<NovelTag> parodies;
  final int status;
  final String statusDisplay;
  final int region;
  final String regionDisplay;
  final int popular;
  final String datetimeUpdated;
  final bool closeComment;
  final bool closeRoast;
  final bool display;
  final String? lastChapterId;
  final String? lastChapterName;

  const NovelBook({
    required this.pathWord,
    required this.name,
    this.uuid = '',
    this.cover = '',
    this.brief = '',
    this.authors = const [],
    this.themes = const [],
    this.parodies = const [],
    this.status = 0,
    this.statusDisplay = '',
    this.region = 0,
    this.regionDisplay = '',
    this.popular = 0,
    this.datetimeUpdated = '',
    this.closeComment = false,
    this.closeRoast = false,
    this.display = true,
    this.lastChapterId,
    this.lastChapterName,
  });

  List<String> get themeNames => themes
      .map((theme) => theme.name.trim())
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList(growable: false);

  factory NovelBook.fromJson(Map<String, dynamic> json) {
    final status = jsonMap(json, 'status');
    final region = jsonMap(json, 'region');
    final lastChapter = jsonMap(json, 'last_chapter');
    return NovelBook(
      pathWord: jsonString(json, 'path_word'),
      uuid: jsonString(json, 'uuid'),
      name: jsonString(json, 'name'),
      cover: jsonString(json, 'cover'),
      brief: jsonString(json, 'brief'),
      authors: _models(json, 'author', NovelTag.fromJson),
      themes: _models(json, 'theme', NovelTag.fromJson),
      parodies: _models(json, 'parodies', NovelTag.fromJson),
      status: status == null
          ? jsonInt(json, 'status')
          : jsonInt(status, 'value'),
      statusDisplay: jsonString(status, 'display'),
      region: region == null
          ? jsonInt(json, 'region')
          : jsonInt(region, 'value'),
      regionDisplay: jsonString(region, 'display'),
      popular: jsonInt(json, 'popular'),
      datetimeUpdated: jsonString(json, 'datetime_updated'),
      closeComment: jsonBool(json, 'close_comment'),
      closeRoast: jsonBool(json, 'close_roast'),
      display: jsonBool(json, 'b_display', fallback: true),
      lastChapterId: lastChapter == null
          ? _optionalString(json, 'last_chapter_id')
          : _optionalString(lastChapter, 'id'),
      lastChapterName: lastChapter == null
          ? _optionalString(json, 'last_chapter_name')
          : _optionalString(lastChapter, 'name'),
    );
  }

  Map<String, dynamic> toJson() => {
    'path_word': pathWord,
    'uuid': uuid,
    'name': name,
    'cover': cover,
    'brief': brief,
    'author': authors.map((e) => e.toJson()).toList(),
    'theme': themes.map((e) => e.toJson()).toList(),
    'parodies': parodies.map((e) => e.toJson()).toList(),
    'status': {'value': status, 'display': statusDisplay},
    'region': {'value': region, 'display': regionDisplay},
    'popular': popular,
    'datetime_updated': datetimeUpdated,
    'close_comment': closeComment,
    'close_roast': closeRoast,
    'b_display': display,
    'last_chapter': {'id': lastChapterId, 'name': lastChapterName},
  };
}

class NovelPage<T> {
  final List<T> list;
  final int total;
  final int limit;
  final int offset;

  const NovelPage({
    required this.list,
    required this.total,
    required this.limit,
    required this.offset,
  });

  bool get hasMore => list.isNotEmpty && offset + list.length < total;

  factory NovelPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) => NovelPage(
    list: _models(json, 'list', parse),
    total: jsonInt(json, 'total'),
    limit: jsonInt(json, 'limit'),
    offset: jsonInt(json, 'offset'),
  );
}

/// An aggregation of documented book-list orderings, not a home/rank API.
class NovelHome {
  final List<NovelBook> popular;
  final List<NovelBook> latest;

  const NovelHome({required this.popular, required this.latest});

  factory NovelHome.fromJson(Map<String, dynamic> json) => NovelHome(
    popular: _models(json, 'popular', NovelBook.fromJson),
    latest: _models(json, 'latest', NovelBook.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'popular': popular.map((e) => e.toJson()).toList(),
    'latest': latest.map((e) => e.toJson()).toList(),
  };
}

/// Keep server access flags separate: !isVip does NOT mean locked.
class NovelAccess {
  final bool isLocked;
  final bool isLoggedIn;
  final bool isMobileBound;
  final bool isVip;

  const NovelAccess({
    this.isLocked = false,
    this.isLoggedIn = false,
    this.isMobileBound = false,
    this.isVip = false,
  });

  Map<String, dynamic> accessJson() => {
    'is_lock': isLocked,
    'is_login': isLoggedIn,
    'is_mobile_bind': isMobileBound,
    'is_vip': isVip,
  };
}

class NovelDetail extends NovelAccess {
  final NovelBook book;

  const NovelDetail({
    required this.book,
    super.isLocked,
    super.isLoggedIn,
    super.isMobileBound,
    super.isVip,
  });

  factory NovelDetail.fromJson(Map<String, dynamic> json) => NovelDetail(
    book: NovelBook.fromJson(jsonMap(json, 'book') ?? {}),
    isLocked: jsonBool(json, 'is_lock'),
    isLoggedIn: jsonBool(json, 'is_login'),
    isMobileBound: jsonBool(json, 'is_mobile_bind'),
    isVip: jsonBool(json, 'is_vip'),
  );

  Map<String, dynamic> toJson() => {...accessJson(), 'book': book.toJson()};
}

class NovelBrowse {
  final String bookId;
  final String pathWord;
  final String chapterId;
  final String chapterName;

  const NovelBrowse({
    required this.bookId,
    required this.pathWord,
    required this.chapterId,
    required this.chapterName,
  });

  factory NovelBrowse.fromJson(Map<String, dynamic> json) => NovelBrowse(
    bookId: jsonString(json, 'book_id'),
    pathWord: jsonString(json, 'path_word'),
    chapterId: jsonString(json, 'chapter_id'),
    chapterName: jsonString(json, 'chapter_name'),
  );

  Map<String, dynamic> toJson() => {
    'book_id': bookId,
    'path_word': pathWord,
    'chapter_id': chapterId,
    'chapter_name': chapterName,
  };
}

class NovelQuery extends NovelAccess {
  final NovelBrowse? browse;

  /// Opaque server collect value (nullable); not a collection count.
  final int? collect;

  const NovelQuery({
    this.browse,
    this.collect,
    super.isLocked,
    super.isLoggedIn,
    super.isMobileBound,
    super.isVip,
  });

  factory NovelQuery.fromJson(Map<String, dynamic> json) {
    final browse = jsonMap(json, 'browse');
    return NovelQuery(
      browse: browse == null ? null : NovelBrowse.fromJson(browse),
      collect: int.tryParse(jsonString(json, 'collect')),
      isLocked: jsonBool(json, 'is_lock'),
      isLoggedIn: jsonBool(json, 'is_login'),
      isMobileBound: jsonBool(json, 'is_mobile_bind'),
      isVip: jsonBool(json, 'is_vip'),
    );
  }

  Map<String, dynamic> toJson() => {
    ...accessJson(),
    'browse': browse?.toJson(),
    'collect': collect,
  };
}

class NovelContentEntry {
  final String name;
  final int contentType;
  final String? content;
  final int startLines;
  final int endLines;

  const NovelContentEntry({
    required this.name,
    required this.contentType,
    this.content,
    this.startLines = 0,
    this.endLines = 0,
  });

  bool get isText => contentType == 1;
  bool get isImage => contentType == 2;

  factory NovelContentEntry.fromJson(Map<String, dynamic> json) =>
      NovelContentEntry(
        name: jsonString(json, 'name'),
        contentType: jsonInt(json, 'content_type'),
        content: _optionalString(json, 'content'),
        // Missing text ranges must not silently become an empty chapter.
        startLines: jsonInt(json, 'start_lines', fallback: -1),
        endLines: jsonInt(json, 'end_lines', fallback: -1),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'content_type': contentType,
    'content': content,
    'start_lines': startLines,
    'end_lines': endLines,
  };
}

class NovelVolume {
  final String id;
  final int index;
  final int sort;
  final int count;
  final String name;
  final String bookId;
  final String bookPathWord;
  final String? prev;
  final String? next;
  final String txtAddr;
  final String txtEncoding;
  final List<NovelContentEntry> contents;

  const NovelVolume({
    required this.id,
    required this.name,
    this.index = 0,
    this.sort = 0,
    this.count = 0,
    this.bookId = '',
    this.bookPathWord = '',
    this.prev,
    this.next,
    this.txtAddr = '',
    this.txtEncoding = '',
    this.contents = const [],
  });

  factory NovelVolume.fromJson(Map<String, dynamic> json) => NovelVolume(
    id: jsonString(json, 'id'),
    index: jsonInt(json, 'index'),
    sort: jsonInt(json, 'sort'),
    count: jsonInt(json, 'count'),
    name: jsonString(json, 'name'),
    bookId: jsonString(json, 'book_id'),
    bookPathWord: jsonString(json, 'book_path_word'),
    prev: _optionalString(json, 'prev'),
    next: _optionalString(json, 'next'),
    txtAddr: jsonString(json, 'txt_addr'),
    txtEncoding: jsonString(json, 'txt_encoding'),
    // Keep even unknown/malformed entries so subsequent progress indices do not shift.
    contents: [
      for (final value in jsonList(json, 'contents'))
        NovelContentEntry.fromJson(jsonMap({'entry': value}, 'entry') ?? {}),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'sort': sort,
    'count': count,
    'name': name,
    'book_id': bookId,
    'book_path_word': bookPathWord,
    'prev': prev,
    'next': next,
    'txt_addr': txtAddr,
    'txt_encoding': txtEncoding,
    'contents': contents.map((e) => e.toJson()).toList(),
  };
}

class NovelVolumeDetail extends NovelAccess {
  final NovelBook book;
  final NovelVolume volume;

  const NovelVolumeDetail({
    required this.book,
    required this.volume,
    super.isLocked,
    super.isLoggedIn,
    super.isMobileBound,
    super.isVip,
  });

  bool get hasText => volume.txtAddr.isNotEmpty && volume.contents.isNotEmpty;

  factory NovelVolumeDetail.fromJson(Map<String, dynamic> json) =>
      NovelVolumeDetail(
        book: NovelBook.fromJson(jsonMap(json, 'book') ?? {}),
        volume: NovelVolume.fromJson(jsonMap(json, 'volume') ?? {}),
        isLocked: jsonBool(json, 'is_lock'),
        isLoggedIn: jsonBool(json, 'is_login'),
        isMobileBound: jsonBool(json, 'is_mobile_bind'),
        isVip: jsonBool(json, 'is_vip'),
      );

  Map<String, dynamic> toJson() => {
    ...accessJson(),
    'book': book.toJson(),
    'volume': volume.toJson(),
  };
}

class NovelReaderEntry {
  /// Position in the original contents, including standalone illustrations.
  final int entryIndex;
  final NovelContentEntry entry;

  /// Original text lines, including whitespace and empty lines; never trimmed.
  final List<String> paragraphs;

  const NovelReaderEntry({
    required this.entryIndex,
    required this.entry,
    this.paragraphs = const [],
  });

  String get name => entry.name;
  bool get isText => entry.isText;
  bool get isImage => entry.isImage;
  String? get imageUrl => isImage ? entry.content : null;
}

class NovelVolumeContent {
  final NovelVolumeDetail detail;
  final List<NovelReaderEntry> entries;

  const NovelVolumeContent({required this.detail, required this.entries});
}

class NovelShelfEntry {
  final int uuid;
  final NovelBook book;
  final String? lastBrowseId;
  final String? lastBrowseName;

  const NovelShelfEntry({
    required this.uuid,
    required this.book,
    this.lastBrowseId,
    this.lastBrowseName,
  });

  /// 漫画书架同款语义：浏览停在旧卷而最新卷已更新。
  bool get hasUpdate =>
      lastBrowseId != null &&
      book.lastChapterId != null &&
      lastBrowseId != book.lastChapterId;

  factory NovelShelfEntry.fromJson(Map<String, dynamic> json) {
    final browse = jsonMap(json, 'last_browse');
    return NovelShelfEntry(
      uuid: jsonInt(json, 'uuid'),
      book: NovelBook.fromJson(jsonMap(json, 'book') ?? {}),
      lastBrowseId: browse == null
          ? null
          : _optionalString(browse, 'last_browse_id'),
      lastBrowseName: browse == null
          ? null
          : _optionalString(browse, 'last_browse_name'),
    );
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'book': book.toJson(),
    'last_browse': lastBrowseId == null
        ? null
        : {'last_browse_id': lastBrowseId, 'last_browse_name': lastBrowseName},
  };
}

/// 在线浏览记录条目。顶层 `last_chapter_*` 是用户停留的章节，
/// `book.last_chapter_*` 是书籍最新章节，二者必须分开保存；
/// 该接口不返回记录自身的 id/uuid，账号级删除为整表清空。
class NovelBrowseEntry {
  final NovelBook book;
  final String? lastChapterId;
  final String? lastChapterName;

  const NovelBrowseEntry({
    required this.book,
    this.lastChapterId,
    this.lastChapterName,
  });

  /// 停留章节与最新章节不一致即视为有更新；任一侧缺失时不判定。
  bool get hasUpdate =>
      lastChapterId != null &&
      book.lastChapterId != null &&
      lastChapterId != book.lastChapterId;

  factory NovelBrowseEntry.fromJson(Map<String, dynamic> json) =>
      NovelBrowseEntry(
        book: NovelBook.fromJson(jsonMap(json, 'book') ?? {}),
        lastChapterId: _optionalString(json, 'last_chapter_id'),
        lastChapterName: _optionalString(json, 'last_chapter_name'),
      );

  Map<String, dynamic> toJson() => {
    'last_chapter_id': lastChapterId,
    'last_chapter_name': lastChapterName,
    'book': book.toJson(),
  };
}

class NovelComment {
  final String id;
  final String createAt;
  final String userId;
  final String userName;
  final String userAvatar;
  final String comment;
  final int count;
  final String? parentId;
  final String? parentUserId;
  final String? parentUserName;

  const NovelComment({
    required this.id,
    required this.comment,
    this.createAt = '',
    this.userId = '',
    this.userName = '',
    this.userAvatar = '',
    this.count = 0,
    this.parentId,
    this.parentUserId,
    this.parentUserName,
  });

  factory NovelComment.fromJson(Map<String, dynamic> json) => NovelComment(
    id: jsonString(json, 'id'),
    createAt: jsonString(json, 'create_at'),
    userId: jsonString(json, 'user_id'),
    userName: jsonString(json, 'user_name'),
    userAvatar: jsonString(json, 'user_avatar'),
    comment: jsonString(json, 'comment'),
    count: jsonInt(json, 'count'),
    parentId: _optionalString(json, 'parent_id'),
    parentUserId: _optionalString(json, 'parent_user_id'),
    parentUserName: _optionalString(json, 'parent_user_name'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'create_at': createAt,
    'user_id': userId,
    'user_name': userName,
    'user_avatar': userAvatar,
    'comment': comment,
    'count': count,
    'parent_id': parentId,
    'parent_user_id': parentUserId,
    'parent_user_name': parentUserName,
  };
}
