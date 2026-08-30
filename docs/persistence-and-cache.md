# 缓存与持久化存储指南

> 本文件说明 kira 的三层数据存储（内存缓存 / 持久化业务缓存 / 用户偏好 / 敏感凭据）。
> 做存储/缓存相关改动前先读此文件，避免选错后端或破坏键名约定。

## 总览：后端矩阵

| 层 | 后端 | 隔离方式 | 清理方式 |
| ---- | ---------- | ---------- | ---------- |
| 内存缓存 | 进程内 `Map` | 各自类持有 | 进程重启即失；部分带 TTL/FIFO 淘汰 |
| 持久化业务缓存 | **SharedPreferences**（JSON 字符串） | `cache_` 键前缀 | `AppStorage.cache.clear*` / 缓存管理页 |
| 用户偏好 | **SharedPreferences** | 无统一前缀，按域命名 | 不应被缓存清理误删；备份时过滤 `cache_` |
| 敏感凭据 | `flutter_secure_storage`（平台 keychain/keystore） | 与 prefs 不同后端 | `SecureCredentialStore.deleteAll()` |
| 文件级 | `path_provider` 目录 | 目录路径 | 缓存管理页分类清理 |

**关键事实**：除文件系统外，几乎所有 KV 数据都落在 SharedPreferences。无 Hive、无 SQLite。业务缓存与用户设置**共用同一个 SharedPreferences 实例**，仅靠 `cache_` 前缀隔离——这是清理逻辑和备份过滤的依据。

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
| AnimeHomeRepository | `anime_home_v1` | **无** | 否 | `cache_anime_home_v1` |
| ComicBookshelfRepository | `bookshelf_comic` | 30min | 是 | `cache_bookshelf_comic` |
| AnimeBookshelfRepository | `bookshelf_anime` | 30min | 是 | `cache_bookshelf_anime` |
| ComicDetailRepository | `comic_detail_$pathWord` | **无** | 否 | `cache_comic_detail_<pathWord>` |
| SearchInitRepository | `search_init_v2` | 1h | 否 | `cache_search_init_v2` |

### cacheKey 命名约定（新增 repository 必须遵守）
- 业务类 cacheKey **不带 `cache_` 前缀**（`AppPersistentCache.fullKey` 自动加）。
- 版本化用 `_v1` / `_v2` 后缀；结构变更时 bump 版本，旧 key 自动失效。
- 按实体区分用 `_$identifier` 后缀（如 `comic_detail_$pathWord`）。
- **明确设 TTL**，否则永久缓存只能靠 `invalidateCache()` 或手动清理（如 `AnimeHomeRepository` / `ComicDetailRepository` 当前是无 TTL 的，新增不要沿用此模式）。

### 2.4 直接写 SharedPreferences 的业务数据（不走 `AppPersistentCache`）

这些键**不带 `cache_` 前缀**，因此会被 `SettingsBackupService` 导出（除非命中 sensitive 规则）：

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

`AiSettings`（`lib/api/ai_api.dart:141`）独立，键名混用 `zhipu_` / `ai_` 前缀，**`zhipu_api_key` 明文存于 prefs，未走 secure storage**（注释自述）。

### 键名前缀族（缓存管理页 `_looksLikeSettingKey` 用以区分设置 vs 缓存）
`theme_` `custom_theme_` `dark_mode_` `bottom_nav_` `nav_` `last_nav_` `desktop_font_` `bookshelf_` `reader_` `image_` `comment_` `auto_check_` `skipped_update_` `disclaimer_` `api_route` `anime_feature_` `banner_` `anime_home_` `anime_skip_` `anime_playback_progress_` `download_` `danmaku_` `local_bookshelf_`（见 `cache_management_page.dart:702`）。

新增用户偏好 key 时，归入上述某一前缀族，否则可能被缓存清理误判或备份遗漏。

### 新增用户偏好 setXxx 的标准做法
1. 在对应子 store 定义 `static const _keyXxx = '<prefix>_xxx';`。
2. 写 getter（`await prefs` → `getBool/getInt/...`）和 setter（`setBool/...` + `notifyListeners()`）。
3. 若通过 `UserManager` 暴露，在 facade 加转发方法。

## 4. 敏感凭据存储

### `SecureCredentialStore`（`lib/models/secure_credential_store.dart:16`）
基于 `flutter_secure_storage`（平台 keychain/keystore）。接口：

```dart
Future<String?> readUsername();   Future<void> writeUsername(String? v);
Future<String?> readPassword();   Future<void> writePassword(String? v);
Future<List<SavedCredential>> readCredentials();  Future<void> writeCredentials(List<SavedCredential> v);
Future<void> deleteAll();
```

键名常量：`saved_username` / `saved_password` / `saved_credentials` / `credentials_migrated_to_secure`。

### ⚠️ 当前状态：已实现但未启用
`SecureCredentialStore` 已编写且带迁移函数 `migrateFromSharedPreferences`，但**生产代码从未调用它**，`main.dart` 也未触发迁移。当前 `UserManager.saveCredentials`（`user_manager.dart:726`）仍把 username/password 明文写入 SharedPreferences。登录页与 profile 页调用的也是 `UserManager().saveCredentials(...)`。

> 新增敏感凭据（token、密码、API key 等）时：**不要**沿用 SharedPreferences 明文模式。若需启用 secure storage 迁移，见 `docs/refactor.md` 的计划项，并在 `main.dart` 初始化阶段接入 `SecureCredentialStore().migrateFromSharedPreferences(...)`。

测试：`InMemorySecureCredentialStore`（`secure_credential_store.dart:139`）+ `test/test_helpers.dart` 的 `setupSecureCredentialStoreForTest`。

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
| 字体 / 原生库 | 各自目录 | 缓存管理页可清 |

**自定义下载保存目录**（`DownloadManager.setSaveDirectory`，`download_manager.dart`）：
- 偏好键 `download_save_directory`（`download_` 前缀族），存绝对路径；缺省/置空 = 应用内部默认目录。
- 启动解析：自定义目录存在、可创建且可写探测通过才使用，否则回退默认（如换机恢复备份后路径失效）。
- 切换目录时逐漫画迁移（同卷 rename / 跨卷 copy+delete），并重写 `chapter.json` 的 `contents` 与 `comic.json` 的 `cover_path`/`comic.cover` 绝对路径前缀；manifest 只含相对标识无需改写。
- Android 侧授权：API 30+ 为 `MANAGE_EXTERNAL_STORAGE`（"所有文件访问"开关页），API ≤29 为 `WRITE_EXTERNAL_STORAGE`；选目录用 `file_picker`（`lib/utils/download_directory.dart`）。

`_ReaderImageFileService`（`reader_image_cache.dart:3`）按响应 `Cache-Control: max-age` 解析有效期，默认 7 天，`no-cache` 立即过期。

## 7. 备份/恢复（设置迁移）

`SettingsBackupService`（`lib/utils/settings_backup.dart:66`）：
- 导出：序列化所有**非 `cache_` 前缀**的 prefs key 为 JSON。
- 敏感 key（`user_token` / `saved_username` / `saved_password` / `saved_credentials` / `zhipu_api_key` / `ai_providers`）在 `includeSensitive=false` 时跳过。
- 导入：清空已存在 key 再写入。

## 8. 新增存储的决策流程

1. **进程级临时数据** → 用页面 State Map 或 `Services` 单例；无需持久化。
2. **可丢弃的业务缓存（首页/详情/列表）** → 继承 `CachedRepository`，设 `cacheKey` + **明确 TTL**，走 `AppStorage.cache`（`cache_` 前缀）。
3. **按实体索引的历史/记录** → 直接写 SharedPreferences，沿用对应前缀（`reading_history_` 等），不带 `cache_` 前缀。
4. **用户偏好设置** → 加到对应子 store，归入前缀族，setter 调 `notifyListeners()`。
5. **敏感凭据** → 用 `SecureCredentialStore`（但需先完成迁移接入，见 §4 警告）。
6. **大文件（下载/图片/字体）** → 文件系统 + `path_provider`。
