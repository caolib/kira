# 缓存与持久化存储指南

> 本文件说明 kira 的数据存储（内存缓存 / 持久化业务缓存 / 用户偏好 / 敏感凭据）。
> 做存储/缓存相关改动前先读此文件，避免选错后端或破坏键名约定。

## 总览：后端矩阵

| 层 | 后端 | 隔离方式 | 清理方式 |
| ---- | ---------- | ---------- | ---------- |
| 内存缓存 | 进程内 `Map` | 各自类持有 | 进程重启即失；部分带 TTL/FIFO 淘汰 |
| 持久化业务缓存 | **SharedPreferences**（JSON 字符串） | `cache_` 键前缀 | `AppStorage.cache.clear*` / 缓存管理页 |
| 用户偏好 | **SharedPreferences** | 无统一前缀，按域命名 | 不应被缓存清理误删；备份按显式白名单筛选 |
| 敏感凭据 | **应用私有 SharedPreferences（明文）**，经 `SecureCredentialStore` | 正式键沿用 `secure_mirror_` 前缀，兼容旧裸键 | 不随普通缓存清理或普通设置备份导出；全量凭据删除用 `SecureCredentialStore.deleteAll()` |
| 文件级 | `path_provider` 目录 | 目录路径 | 缓存管理页分类清理 |

**关键事实**：业务缓存、用户设置与凭据共用 SharedPreferences；`cache_` 和 `secure_mirror_` 只用于逻辑分类，后者不代表加密或独立安全后端。缓存清理需保护凭据，备份需按 `BackupSchema` 白名单筛选，不能把「不是 `cache_`」等同于「可导出」。

> `AppStorage.sharedPreferences()` 直接委托 `SharedPreferences.getInstance()`，**不要在外面再缓存这个 Future**：测试用 `setMockInitialValues` 替换平台实现时会清掉插件自己的 completer，被缓存下来的旧 Future 会解析到过期 store，甚至永远不完成（曾导致测试里书架请求数为 0 且挂到 10 分钟超时）。

## 1. 内存缓存（in-memory）

进程级、非持久化。重启即失。

### 1.1 `AppMemoryCache`（`lib/utils/app_storage.dart:25`）
通用 `Map` + TTL（懒删除）。入口 `AppStorage.memory`。**当前为死代码**，无业务调用——新增内存缓存可考虑用它，但需先确认是否真的需要内存层（多数场景直接用 `AppStorage.cache` 持久化即可）。

### 1.2 Reader 页面 State 持有的 Map（`lib/pages/reader_page.dart`）
- `_imageNaturalSizes`：图片原始尺寸，手写 FIFO 淘汰，上限 120 项。
- `_commentCache` / `_commentTotalCache`：按 chapterUuid 缓存评论，章节裁剪时主动清理。
- `_chain`：连续阅读章节链，按"前 1 后 1"窗口裁剪。

这些属于页面私有缓存，**不要跨页面共享**。

### 1.3 单例持有的内存副本
- `UserManager`（`lib/models/user_manager.dart:82`）：单例，`init()` 时从 prefs 一次性加载 60+ 字段的内存副本。
- `Services`（`lib/utils/services.dart`）：自建 service locator，缓存所有领域 singleton。
- `DownloadManager._manifest`：下载清单内存副本，启动时由 `manifest.json` 加载。
- `ApiTransport._hostWeights` / `_cookies`：host 测速权重与 cookie，**内存级、不持久化**，进程重启丢失。

### 1.4 Riverpod providers
`lib/providers/` 下均为普通 `Provider<>`（未用 `autoDispose`/`keepAlive`），因持有 factory singleton，等价进程级常驻。

## 2. 持久化业务缓存（非用户偏好）

### 2.1 核心入口：`AppStorage.cache`（`lib/utils/app_storage.dart:95`）

后端是 **SharedPreferences**，数据以 JSON 字符串存在 `cache_<key>` 键里。TTL 通过包一层 `{__cache_data__, __cache_expires_at__}` 实现，读取时自动检查并删除过期项。

```dart
// 写
await AppStorage.cache.put('my_key', data, ttl: Duration(hours: 1));
// 读（过期返回 null 并清理）
final raw = await AppStorage.cache.get('my_key');
// 清理
await AppStorage.cache.clearExpired();
await AppStorage.cache.clear();
```

`DataCache`（`lib/utils/data_cache.dart`）是兼容 facade，方法直接转发到 `AppStorage.cache`。`ApiClient` 注入的是 `DataCache()`，但 **`ApiTransport.cache` 字段当前未被使用**（死字段）。

### 2.2 `CachedRepository`（cache-then-API，`lib/models/cached_repository.dart:44`）

标准缓存模式，后端固定为 `AppStorage.cache`。子类指定 `cacheKey` / `ttl` / `serialize` / `deserialize` / `skipApiIfCacheFresh`。

```dart
Future<T> load() async {
  if (skipApiIfCacheFresh) {
    final cached = await loadFromCache();
    if (cached != null) return cached;
  }
  final data = await fetchFromApi();
  await saveToCache(data);
  return data;
}
```

- `load()`：cache-first（仅当 `skipApiIfCacheFresh` 时跳过 API）。
- `loadFromCache()`：纯缓存。
- `invalidateCache()`：删除缓存条目，强制下次走 API。
- `DualCachedRepository<A,B>`：A/B 两路独立缓存（用于 manga home 同页 HOT + COPY）。

### 2.3 `lib/repositories/` 现有 cacheKey 清单

| Repository | cacheKey | TTL | skipApiIfCacheFresh | 实际存储键 |
| ---- | ---------- | ---- | ---- | ---------- |
| MangaHomeRepository (HOT) | `manga_home_v1` | 1h | 否 | `cache_manga_home_v1` |
| MangaHomeRepository (COPY) | `manga_home_copy_v1` | 1h | 否 | `cache_manga_home_copy_v1` |
| CopyTopicRepository（专题列表） | `copy_topics_v1_<limit>_<offset>` | 1d | 是 | `cache_copy_topics_v1_*` |
| CopyTopicRepository（专题介绍） | `copy_topic_info_v1_<pathWord>` | 7d | 是 | `cache_copy_topic_info_v1_*` |
| CopyTopicRepository（专题漫画） | `copy_topic_comics_v1_<pathWord>_<limit>_<offset>` | 3d | 是 | `cache_copy_topic_comics_v1_*` |
| AnimeHomeRepository | `anime_home_v1` | **无** | 否 | `cache_anime_home_v1` |
| ComicBookshelfRepository | `bookshelf_comic` | 30min | 是 | `cache_bookshelf_comic` |
| NovelBookshelfRepository | `bookshelf_novel_v2_<scope>_<ordering>` | 30min | 是 | `cache_bookshelf_novel_v2_*` |
| AnimeBookshelfRepository | `bookshelf_anime` | 30min | 是 | `cache_bookshelf_anime` |
| ComicDetailRepository | `comic_detail_$pathWord` | **无** | 否 | `cache_comic_detail_<pathWord>` |
| SearchInitRepository | `search_init_v2` | 1h | 否 | `cache_search_init_v2` |

### cacheKey 命名约定（新增 repository 必须遵守）
- 业务类 cacheKey **不带 `cache_` 前缀**（`AppPersistentCache.fullKey` 自动加）。
- 版本化用 `_v1` / `_v2` 后缀；结构变更时 bump 版本，旧 key 自动失效。
- 按实体区分用 `_$identifier` 后缀（如 `comic_detail_$pathWord`）。
- **明确设 TTL**，否则永久缓存只能靠 `invalidateCache()` 或手动清理（如 `AnimeHomeRepository` / `ComicDetailRepository` 当前是无 TTL 的，新增不要沿用此模式）。

### 2.4 直接写 SharedPreferences 的业务数据（不走 `AppPersistentCache`）

这些键**不带 `cache_` 前缀**，但不因此自动进入备份；仅 `BackupSchema` 明确登记的记录（如阅读历史、阅读统计）可由 `SettingsBackupService` 按分类导出，其余默认排除：

| 模块 | 前缀/键 | 文件 |
| ---- | ---------- | ---- |
| 漫画阅读历史 | `reading_history_$pathWord` / `..._group_$g` | `lib/utils/reading_history.dart:6` |
| 阅读统计 | `reading_stats_v1` / `reader_reading_stats_enabled` | `lib/utils/reading_stats.dart` |
| 动漫播放历史 | `anime_playback_history_${pathWord}_${chapterUuid}` | `lib/utils/anime_playback_history.dart:7` |
| dandanplay 绑定 | `dandanplay_binding_$pathWord` | `lib/utils/dandanplay_binding_store.dart:102` |
| AI 章节总结 | `zhipu_chapter_summary_$chapterUuid` | `lib/utils/chapter_summary_cache.dart:64` |
| 远程公告已读 | `remote_notice_seen_keys_v2` | `lib/utils/remote_notice_service.dart:32` |
| 分享链接已处理标记 | `shared_link_last_handled` | `lib/utils/kira_links.dart` |

新增此类"按实体 ID 索引的历史/记录"时，沿用对应前缀，并确保 `cache_management_page._categoryOf` 能识别分类。

## 3. 用户偏好（持久化）

### 后端与基类
- 统一后端：**SharedPreferences**（`shared_preferences: 2.5.5`）。
- `PrefsStore`（`lib/models/prefs_store.dart:11`）：所有领域子 store 的基类，`extends ChangeNotifier`，提供 lazy 缓存的 `SharedPreferences` 实例（`prefs` getter + `syncPrefs` 锁定实例）。
- `UserManager`（`lib/models/user_manager.dart:82`）：facade，单例，**不继承 `PrefsStore`**，直接读写 prefs。`init()`（line 459-655）加载全部字段，并调用各子 store 的 `initFromPrefs(prefs)` 把同一实例传下去。

### 子 store（均 `extends PrefsStore`，独立 singleton）
| 子 store | 文件 | 前缀示例 |
| ---- | ---- | ---- |
| ReaderSettings | `lib/models/reader_settings.dart` | `reader_*`、`image_viewer_*` |
| DanmakuSettings | `lib/models/danmaku_settings.dart` | `danmaku_*` |
| CommentSettings | `lib/models/comment_settings.dart` | `comment_*` |
| ThemeSettings | `lib/models/theme_settings.dart` | `theme_*`、`dark_mode_*`、`bottom_nav_*`、`*_font_*` |
| NetworkSettings | `lib/models/network_settings.dart` | `api_route`、`network_*` |

`AiSettings`（`lib/api/ai_api.dart`）独立，键名混用 `zhipu_` / `ai_` 前缀；API key 与连接配置仍以明文存在 prefs，未纳入 `SecureCredentialStore`，备份归入需显式选择的敏感「AI 连接」分类。

### 键名前缀族（缓存管理页 `_looksLikeSettingKey` 用以区分设置 vs 缓存）
`theme_` `custom_theme_` `dark_mode_` `bottom_nav_` `nav_` `last_nav_` `desktop_font_` `bookshelf_` `reader_` `image_` `comment_` `auto_check_` `skipped_update_` `update_mirror_` `use_update_mirror` `disclaimer_` `api_route` `anime_feature_` `banner_` `anime_home_` `anime_skip_` `anime_playback_progress_` `download_` `danmaku_` `local_bookshelf_`（见 `cache_management_page.dart` 的 `_looksLikeSettingKey`）。

新增用户偏好 key 时，归入上述某一前缀族，否则可能被缓存清理误判或备份遗漏。

### 新增用户偏好 setXxx 的标准做法
1. 在对应子 store 定义 `static const _keyXxx = '<prefix>_xxx';`。
2. 写 getter（`await prefs` → `getBool/getInt/...`）和 setter（`setBool/...` + `notifyListeners()`）。
3. 若通过 `UserManager` 暴露，在 facade 加转发方法。

## 4. 敏感凭据存储

### 正式后端与兼容命名

`SecureCredentialStore`（`lib/models/secure_credential_store.dart`）统一通过 `AppStorage.sharedPreferences()` 读写**应用私有 SharedPreferences 明文记录**。不再依赖 `flutter_secure_storage`，不调用 Keystore/Keychain，也没有双写、自愈镜像或单次安全插件调用超时。

- `SecureCredentialStore` 类名和 `preferencePrefix = 'secure_mirror_'` 是历史兼容名称，**不表示加密**。旧版镜像键现在就是正式存储，不需要另换前缀或再复制一份。普通值仍为字符串；命中 Android prefs 保留前缀的字符串使用单元素 `StringList` 无损保存，读取同时兼容两种表示。
- 逻辑键包括 `user_token`、`saved_username`、`saved_password`、`saved_credentials`、`credentials_migrated_to_secure`、`copy_account_v1`、`backup_webdav_credentials_v1`、`backup_password_v1`、`backup_rollback_key_v1`。例如 token 的正式键是 `secure_mirror_user_token`。
- `logicalKeyForPreference(key)` 识别上述正式键与旧无前缀别名，返回逻辑键；它不是普通备份白名单，未知键返回 `null`。
- 旧安装若只有加密存储中的凭据、没有可读的 prefs 记录，升级后可能需要重新登录一次；**登录成功并保存后，多次冷启动必须继续恢复会话，不能每次启动都要求登录**。这里不承诺绕过服务端令牌过期、用户主动退出或清除应用数据。

主要接口保持不变：

```dart
Future<String?> readToken();      Future<void> writeToken(String? v);
Future<String?> readUsername();   Future<void> writeUsername(String? v);
Future<String?> readPassword();   Future<void> writePassword(String? v);
Future<List<SavedCredential>> readCredentials();  Future<void> writeCredentials(List<SavedCredential> v);
Future<bool> hasCredentialsRecord();  Future<bool> credentialsMigrated();
Future<String?> readCopyAccountRecord();
Future<void> writeCopyAccountRecord(String v);
Future<void> deleteAll();
```

### 只读加载与退出标记

- `read*` **只读、不迁移、不回写**：先读取正式记录，仅在缺失时读取同名旧裸键。正式记录里的空 token、空字符串、`[]` 和 COPY 清空记录仍是有效状态，不得用旧值覆盖。
- `writeToken(null)` 写入空字符串作为退出标记，区别于「从未保存」；`writeCredentials([])` 持久化空数组，`hasCredentialsRecord()` 区分显式清空与旧单账号缺少列表，只有后者可从记住的用户名/密码合成账号。COPY 退出/清空通过记录内的 `cleared`、`migrationHandled` 等状态表达，不能直接删键后让旧会话复活。
- 迁移标记 `credentials_migrated_to_secure == 'true'` 只阻止三个已清空保存字段（`saved_username`、`saved_password`、`saved_credentials`）重新读到旧值；不能据此屏蔽 token、COPY 或备份凭据的旧裸键。
- `UserManager.init(persistMigrations: false)` 用于备份恢复后的只读重载：读取现有有效状态，不补写凭据、不移动旧键。COPY 初始化同样受 `persistMigrations` 控制。

### 显式迁移与写入失败

正常启动由 `UserManager.init()` 调用 `migrateFromSharedPreferences(prefsMap, removePref)`，只迁移旧明文记录，不读取历史加密存储：

1. 保留已存在的正式值，包括退出/清空记录；只复制缺失且未被清空标记抑制的旧值。
2. 直接复制原始字符串/JSON，保留本版本不认识的字段，不把解析后的列表重新序列化为迁移数据。
3. 正式值及迁移标记成功落盘后，才删除旧别名；写入失败保留旧值以便重试。一次迁移失败不能遮蔽已经保存的正式会话。
4. 生产迁移在串行队列内重新读取当前 prefs，避免调用方旧快照复活刚删除的账号；内存测试替身才使用传入的 `prefsMap`。

写入/删除串行执行。SharedPreferences 返回 `false` 也视为失败：尝试补偿写回该键原值，再 `reload()`，最后向调用方抛错。原生 prefs 也可能先改内存再写磁盘，因此不能只靠 reload 回滚，重试删除也不能因缓存中缺键就跳过提交。删除凭据时先删旧裸键，再删正式键；`deleteAll()` 清除两种键名的凭据，但保留迁移标记。登录事务必须继续处理写入失败与回滚，不可吞错假报成功。

### 备份、缓存与测试边界

- 新凭据仍统一接入 `SecureCredentialStore`，不要散落到普通设置键；正式凭据和旧别名均应排除普通缓存清理，账号项默认整值脱敏。
- Android 保留 `allowBackup="false"`，避免私有明文凭据随系统自动备份导出。应用自己的备份按白名单与分类选择导出（见 §7），备份文件加密能力不变。
- 测试不再用 `FLUTTER_TEST=true` 让凭据操作静默返回空值。隔离用例显式注入 `InMemorySecureCredentialStore`，其 `legacyPreferencesEnabled == false`，不会读取、迁移或删除 prefs。
- 持久化回归必须另用**默认 prefs 后端**与 Mock SharedPreferences/假平台通道，覆盖保存后重建单例、连续冷启动恢复、退出不复活旧值，以及平台写入返回 `false`/抛错。只测内存替身不足以证明不会重复掉登录。

## 5. 网络层缓存

- 主 `dio`（`api_client.dart:32`）：经 `AppDio.create` 构造，拦截器注入 token/cookie/UA，`onError` 处理 401 自动登录。**无 Dio 磁盘缓存拦截器、无 `pretty_dio_logger`**。
- `commentDio`：显式 `cache-control: no-cache` / `pragma: no-cache`（禁用 HTTP 缓存）。
- host rotation：`ApiTransport.nextHost()`（`api_transport.dart:187`）按 `_hostWeights` 加权选优；`_hostWeights` 内存级、不持久化。
- cookie：`ApiTransport._cookies` 内存级、不持久化，重启丢失。

## 6. 文件级缓存

| 项 | 路径/键 | 管理 |
| ---- | ---------- | ---- |
| 阅读器图片 | `CacheManager(Config('readerImageCache', ...))`（`reader_page.dart:68`） | 缓存管理页可清 |
| 封面/头像图片 | `DefaultCacheManager`（默认 key `libCachedNetworkImageData`） | 缓存管理页可清 |
| 漫画下载 | 默认 `getApplicationDocumentsDirectory()/comic_downloads/`，清单 `manifest.json`；可通过 `download_save_directory` 自定义为公共目录（Android，见下） | `DownloadManager` |
| 漫画下载队列 | prefs 键 `download_queue_state_v1`：队列任务、暂停状态与批次失败快照，启动时恢复并自动续传（`main.dart` 初始化 `DownloadManager`） | `DownloadManager` |
| 字体 / 原生库 | 各自目录 | 缓存管理页可清 |

**自定义下载保存目录**（`DownloadManager.setSaveDirectory`，`download_manager.dart`）：
- 偏好键 `download_save_directory`（`download_` 前缀族），存绝对路径；缺省/置空 = 应用内部默认目录。
- 启动解析：自定义目录存在、可创建且可写探测通过才使用，否则回退默认（如换机恢复备份后路径失效）。
- 切换目录时逐漫画迁移（同卷 rename / 跨卷 copy+delete），并重写 `chapter.json` 的 `contents` 与 `comic.json` 的 `cover_path`/`comic.cover` 绝对路径前缀；manifest 只含相对标识无需改写。
- Android 侧授权:API 30+ 走 `MANAGE_EXTERNAL_STORAGE`("所有文件访问"系统开关页,**不是**应用内运行时弹窗);API ≤29 期望退化到 `WRITE_EXTERNAL_STORAGE` 的运行时授权。两者都**必须**声明在 `android/app/src/main/AndroidManifest.xml` 的 `<uses-permission>` —— `permission_handler` 的 `determinePermissionStatus`/`requestPermissions` 会先查 manifest,缺声明时直接判定 `denied` 并 `continue`,不会调用 `launchSpecialPermission`,表现为点"保存位置"立刻提示"未授予存储权限"、无任何系统页或弹窗。选目录用 `file_picker`(`lib/utils/download_directory.dart`)。
  - 已知缺口:Android 10(API 29)下 `Permission.storage` 仅在 `WRITE_EXTERNAL_STORAGE` 已声明**且** `Environment.isExternalStorageLegacy()` 为真时才请求;当前未声明 `requestLegacyExternalStorage`,该分支 manifest names 为空,同样静默失败(API 24-28 不受影响)。

`_ReaderImageFileService`（`reader_image_cache.dart:3`）按响应 `Cache-Control: max-age` 解析有效期，默认 7 天，`no-cache` 立即过期。

## 7. 备份/恢复（设置迁移）

`SettingsBackupService`（`lib/utils/settings_backup.dart`）通过 `BackupSchema`（`lib/backup/backup_category.dart`）执行**键名与类型白名单**，不是导出所有非缓存键：

- 分类包括设置、阅读历史、阅读统计、书签、账号和 AI 连接。默认只选择「设置」；账号与 AI 连接是敏感分类，须显式选择（兼容 API 的 `includeSensitive: true` 会加入这两类）。
- `SharedBackupPreferences` 从 `SecureCredentialStore` 读取有效主账号凭据，映射回备份协议的逻辑键 `user_token`、`saved_username`、`saved_password`、`saved_credentials`；`user_account_id` 与其他主账号资料也在账号白名单中。导出不会迁移或补写原记录。
- `secure_mirror_*` **物理键不直接导出**；普通设置备份也不导出上述主账号凭据。不能因为物理前缀未被登记，就认为显式选择「账号」时也不会导出主账号。
- 独立 `copy_account_v1` 记录、WebDAV 凭据、备份口令、回滚密钥及迁移标记均不在白名单；它们的正式键和旧裸键都不直接导出。`cache_*`、下载路径/队列、AI 会话/总结、其他未登记键同样排除。
- 导入只事务性替换选中的分类，不清空所有非缓存键。主账号凭据仍经 `SecureCredentialStore` 写入/清除，其他未选分类与独立 COPY 记录不得被改写。
- 恢复先暂停并排空运行时写入，再保存加密回滚日志、替换分类、重载内存，最后清除日志作为提交点；失败回滚，启动时可恢复未完成事务。`BackupCodec` 的 PBKDF2 / AES-GCM 备份文件加密与加密日志保持不变，`crypto`、`cryptography`、`cryptography_flutter` 仍有用途。

### 导入 / 清除后必须重载内存单例

导入只改 prefs,而多数单例用 `_loaded` / `_initialized` / 内存 `_cache` 守卫只在进程内加载一次——不重载就会「导入成功但不生效,重启才恢复」。

`reloadRuntimeSettings()`（`lib/utils/settings_reload.dart`）按分类重载 `UserManager`、`DownloadManager`、`AiSettings`、`AppLogger`、`ReadingStats`、`FontManager`、`BookmarkStore` 与 `NovelBookmarkStore`，并重新加载选中字体。普通重载各步骤独立容错；备份事务用 `strict: true` 把重载失败反馈给回滚流程。指定分类时账号初始化使用 `persistMigrations: false`，不能在恢复其他设置时顺带迁移或改写凭据。

调用点:`general_page`(导入 / 重置应用)、`cache_management`(删除单条 / 批量 / 分区)。

**新增一次性加载的单例时必须同步登记进去**,否则该设置又会变成「要重启才生效」。此类单例应提供 `reloadFromPrefs()` 之类的重载入口,而不是仅暴露 `@visibleForTesting` 的 reset 方法。

## 8. 新增存储的决策流程

1. **进程级临时数据** → 用页面 State Map 或 `Services` 单例；无需持久化。
2. **可丢弃的业务缓存（首页/详情/列表）** → 继承 `CachedRepository`，设 `cacheKey` + **明确 TTL**，走 `AppStorage.cache`（`cache_` 前缀）。
3. **按实体索引的历史/记录** → 直接写 SharedPreferences，沿用对应前缀（`reading_history_` 等），不带 `cache_` 前缀。
4. **用户偏好设置** → 加到对应子 store，归入前缀族，setter 调 `notifyListeners()`。
5. **敏感凭据** → 用 `SecureCredentialStore`（已接入 `UserManager.init()` 迁移，见 §4）。
6. **大文件（下载/图片/字体）** → 文件系统 + `path_provider`。

## 9. 轻小说（新增）

- `novel_reading_history_<pathWord>`：本地卷、原始章节索引、段落位置；不使用漫画历史前缀，备份归入阅读历史。
- `novel_bookmarks_v1`：用户手动添加的轻小说书签，全量 JSON 列表（上限 500）；独立于 `novel_reading_history_`，不随缓存或阅读历史清理。按书、卷、原始章节索引和段落索引去重，精确保存段落 alignment；不保存正文地址/会话。通过 `NovelBookmarkStore` 串行读写，备份归入书签；恢复时暂停写入并由 `reloadRuntimeSettings()` 重载内存。
- `reader_novel_settings_v1`：字号（10–48）、行距/段距、预设/自定义 ARGB 背景与文字色和常亮偏好；对白总开关与浅深色对白样式也保存在同一 JSON（`dialogueEnabled`、`lightDialogueStyle`、`darkDialogueStyle`），旧记录缺字段时默认关闭。备份归入设置；配对区间仅存在章节身份的弱引用内存缓存，不写入正文缓存或偏好。
- `novel_status_overlay*`（`lib/models/novel_reader_status_settings.dart`）：轻小说阅读器状态组件的独立配置（开关/时间/网络/电量/章节名/页码/帧率段位、顺序、六位摆放、不透明度、前景/背景色）。与漫画侧 `reader_status_overlay*` 互不影响；首次初始化（无任何 `novel_status_overlay*` 键）时一次性继承漫画现值并由哨兵键 `novel_status_overlay_seeded` 固化。经 `UserManager.init` 加载与 `reloadRuntimeSettings()` 重载，备份归入设置。
- 阅读历史和阅读设置每次读取当前 prefs，无一次性数据快照，恢复备份后无需注册额外单例重载。
- `cache_novel_*`：按主机/账号指纹区分的元数据缓存，明确 TTL。
- 应用支持目录 `novel_text_cache_v1`：整卷正文和对应目录的文件快照；缓存管理可单独清理，保留阅读历史。
- 应用文档目录 `novel_downloads`（可改到自定义目录，键 `download_novel_save_directory`）：**永久下载**，与上面的可清理正文缓存是两套存储。带版本清单 `manifest_v1.json`，每卷保存同一版本的原始 TXT + 目录快照、书籍/卷元数据与插图 URL 映射。**启动只做轻量探测**：读两级清单 JSON，对每个被索引文件做「存在且长度相符」检查（不读正文、不算摘要、不解析文本），据此区分「已完成 / 部分完成 / 待修复」；缺失或长度不符立即标为「待修复」。摘要与正文合法性在真正读取该卷时（`readVolumeSnapshot`/`readImageBytes`）惰性校验，不符则降级。这样启动耗时不随离线库体积增长。删除只作用于被索引、被探测过的文件。
- `download_novel_queue_state_v1`：小说未完成下载队列（版本、暂停标记、任务列表）。完整成功后只删除任务记录，本地文件保留；启动时依据探测结果清理遗留完成记录，缺失/损坏转待修复，失败/暂停/部分完成任务保留。只持久化稳定来源标识（`CopyAccountSession.id`，游客为 `guest`）与主机，**不保存 token**；账号或线路变化后未完成任务暂停。`download_novel_concurrency` 控制并发（1–4）。管理器初始化与续传在首帧之后后台进行，不阻塞 `runApp`。
- 清理边界：清正文缓存不动已下载内容；清下载不动阅读进度/历史/书签。退出账号不删除本机已下载内容。
- `secure_mirror_copy_account_v1`：`SecureCredentialStore` 在私有 prefs 中保存的独立拷贝会话及迁移/退出标记，兼容读取旧裸键 `copy_account_v1`。不导出到普通设置或账号分类备份；退出附加账号不得清除其他凭据键。通过认证但尚无资料的账号使用随机 `local:` 标识；`account_id` 固定后不随资料补全或 Token 更新变化。主账号的同一标识以 `user_account_id` 保存，归入敏感账号备份分类；它不是 Token 或 Token 指纹。
- 详细阅读/鉴权/下载边界见 [轻小说](novel.md)。
