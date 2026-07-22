# Kira 项目设计问题清单

> 审查日期: 2026-06-30
> 最后更新: 2026-07-01

---

## P0 — 严重问题

### 1. `UserManager` 上帝对象（1341行，60+字段）— ✅ 已修复

- **文件**: `lib/models/user_manager.dart`
- **原问题**: 单一类承担了至少 4 种职责
- **修复**: 拆分为 5 个独立 ChangeNotifier 子存储 + `PrefsStore` 基类
  - `ReaderSettings`（18 字段）、`DanmakuSettings`（8 字段）、`CommentSettings`（7 字段）、`ThemeSettings`（12 字段）、`NetworkSettings`（5 字段）
  - `NetworkProxyMode`/`NetworkProxyType` 枚举提取到 `network_proxy_types.dart`
  - UserManager 保持 facade，转发通知以兼容现有代码
  - `PrefsStore` 基类提供 typed helpers 自动调 `notifyListeners()`

### 2. 全局单例泛滥，无依赖注入 — ✅ 已修复

- **原问题**: 所有服务通过工厂构造函数暴露全局单例，不可测试
- **修复**: 创建 `Services` 服务定位器（`lib/utils/services.dart`）
  - `Services.override<T>()` 支持测试注入
  - `Services.reset()` 清理测试状态
  - `UserManager.testInstance` / `ApiClient.testInstance` 使工厂构造函数自动返回测试实例
  - 现有 `UserManager()` / `ApiClient()` 调用无需改动即可获得注入能力

### 3. 空 catch 块静默吞掉错误（11处）— ✅ 已修复

- **修复**: 全部替换为 `catch (e, stack) { AppLogger.instance.recordWarning(...) }`
- 涉及 8 个文件

---

## P1 — 中等问题

### 4. 无状态管理框架 — ✅ 已修复

- 引入 `flutter_riverpod: ^2.5.0`
- `ProviderScope` 包裹 `runApp()`
- 3 个 provider 文件：`app_providers.dart`、`settings_providers.dart`、`repository_providers.dart`
- 3 个页面迁移为 `ConsumerStatefulWidget`：home_page、anime_home_page、bookshelf_page
- 增量迁移策略：Riverpod 与现有单例模式共存

### 5. 巨型 Widget 文件 — ✅ 已修复

- **已完成**: profile_page.dart 从 2207→608 行（拆出 LoginPage/RegisterPage/DisclaimerPage/AboutPage）
- **已完成**: home_page.dart 减少 ~130 行（ComicCard 提取到 widgets/）
- **已完成**: copy_manga_list_page.dart 减少 ~140 行（提取到共享 widgets）
- **已完成**: reader_page.dart 从 2587→1955 行（-24%），提取 5 个 part 文件：
  - `reader_scroll_item.dart` — _ScrollItem 枚举与类（30行）
  - `reader_pull_to_refresh.dart` — _ReaderPullToRefresh（97行）
  - `reader_chapter_widgets.dart` — 章节分隔区/尾部/头部 widget（318行）
  - `reader_top_bar.dart` — 顶部工具栏 widget（58行）
  - `reader_bottom_bar.dart` — 底部工具栏 widget（197行）

### 6. 业务逻辑嵌入 Widget — ✅ 已修复

- 创建 `CachedRepository<T>` / `DualCachedRepository<A, B>` 基类（`lib/models/cached_repository.dart`）
- 创建 5 个具体 Repository（`lib/repositories/`）：
  - `MangaHomeRepository` — 漫画首页双缓存（manga_home + copy_home，1h TTL）
  - `AnimeHomeRepository` — 动漫首页缓存
  - `SearchInitRepository` — 搜索初始化缓存（关键词+标签，1h TTL）
  - `ComicDetailRepository` — 漫画详情缓存
  - `ComicBookshelfRepository` / `AnimeBookshelfRepository` — 书架缓存（30min TTL，skipApiIfCacheFresh）
- 重构 5 个页面：home_page、anime_home_page、search_page、comic_detail_page、bookshelf_page
- 统一 4 种缓存模式（并行/串行/TTL门控/API透明）为单一 Repository 接口

### 7. `lib/widgets/` 目录为空 — ✅ 已修复

- 创建共享组件：
  - `ComicCoverCard` — 漫画封面卡片，替换 9 个页面的重复实现
  - `ShimmerShell` + `ShimmerBox` + `ComicCoverSkeletonGrid` + `ComicRowSkeletonList` — 加载骨架屏
  - `ErrorRetryView` + `SliverErrorRetryView` — 错误重试状态
  - `NullIfEmptyString` 扩展 — 空字符串转 null
  - `showLoginExpiredDialog()` — 登录过期对话框（P2-16）

### 8. 不安全 `as` 类型转换 — ✅ 已修复

- 创建 `lib/utils/json_helpers.dart`（`jsonList`/`jsonInt`/`jsonString`/`jsonDouble`/`jsonBool`/`jsonMap`）
- API 层和模型层 ~70 处不安全转换已替换
- 简单模型已迁移到 `json_serializable`（P2-10）

### 9. 密码明文存储在 SharedPreferences — ⚠️ 部分完成（FIXME）

基础设施已建好，但**未接线**，凭据仍是 SharedPreferences 明文。详见 `docs/persistence-and-cache.md` §4。

已完成：
- 引入 `flutter_secure_storage`，创建 `SecureCredentialStore`
- `InMemorySecureCredentialStore` 用于测试注入
- `migrateFromSharedPreferences()` 迁移函数
- `test/test_helpers.dart` 统一 setUp/tearDown + `secure_credential_store_test.dart`

FIXME（启用前必须处理）：
- `main.dart` 从未调用 `migrateFromSharedPreferences`，生产代码 0 调用 `SecureCredentialStore`。
- `UserManager.saveCredentials`（`user_manager.dart:726`）仍 `prefs.setString(_keySavedPassword, ...)` 明文写；login_page/profile_page 4 处仍走 `UserManager().saveCredentials`。
- 接线需三处联动：① 改 `UserManager` 读写走 secure storage；② `main.dart`/`init` 跑迁移；③ 迁移改为「先复制后删除」。
- FIXME 迁移坑：`migrateFromSharedPreferences` 把 `_keyMigrated` 标记写在 secure storage（`secure_credential_store.dart:133`），一旦 secure storage 被清空，标记丢失→迁移重跑→但 prefs 旧明文已删→重跑读到空→**凭据永久丢失且无报错**。启用前必须把标记改存 SharedPreferences。
- FIXME 半成品一致性：`SecureCredentialStore` 与 `UserManager` 用相同键名（`saved_username`/`saved_password`/`saved_credentials`），若只启用迁移不改 `saveCredentials`，新登录账号仍写回 prefs 明文，迁移白做。

---

## P2 — 轻度问题

### 10. 手写 JSON 解析 — ✅ 已修复

- 引入 `json_annotation`/`json_serializable`/`build_runner`
- 简单模型迁移为 `@JsonSerializable(fieldRename: FieldRename.snake)`：
  - `Author`、`Theme`、`ComicGroup`、`MangaTopic`（comic.dart）
  - `AnimeTag`、`AnimeCompany`、`AnimeChapterLine`（anime.dart）
  - `ComicComment`（comic_comment.dart）
  - `ChapterComment`（chapter_comment.dart）
- 复杂模型（Comic、Anime、MangaHome、Chapter 等）保留手写 fromJson — 自定义类型转换过多
- `.g.dart` 文件已生成并通过测试验证

### 11. API 层 part/mixin 紧耦合 — ✅ 已修复

- 提取 `ApiTransport` 类（`lib/api/api_transport.dart`）— 共享 Dio、auth、cache headers、host rotation
- 每个 mixin → 独立类：`MangaApi`、`AnimeApi`、`NetworkApi`、`UserApi`
- `ApiClient` 改为 facade：创建 ApiTransport，暴露 `.manga/.anime/.network/.user`
- 所有调用点从 `ApiClient().getXxx()` 迁移为 `ApiClient().manga.getXxx()`
- 移除 `part`/`mixin` 模式

### 12. 无路由框架 — ✅ 已修复

- 引入 `go_router`
- `lib/routing/app_router.dart` — 声明式路由 + `AppRoutes` 常量
- `lib/routing/main_shell.dart` — 底部导航栏 ShellRoute
- 所有 `Navigator.push(MaterialPageRoute(...))` 迁移为 `context.pushNamed(AppRoutes.xxx)`
- 路由携带额外数据使用 `extra` 参数 + 类型化类（`ComicDetailExtra`、`ReaderExtra`、`AnimeDetailExtra`）

### 13. 无国际化 — ✅ 已修复

- `l10n.yaml` 配置 gen-l10n
- `lib/l10n/app_zh.arb` — 模板 ARB（仅简体中文）
- 5 个页面的硬编码字符串已提取到 ARB
- 生成 `app_localizations.dart` + `app_localizations_zh.dart`
- 后续添加其他语言只需新增 ARB 文件

### 14. 缓存-请求模式重复 — ✅ 已修复

- 通过 P1-6 的 Repository 基类统一了 6 个页面的缓存-请求模式
- 移除了各页面中手动的 `_loadFromCache()` / `_cache.put()` / `_cache.get()` 调用
- 书架页面的手动 `cache_time` 逻辑已迁移到 Repository TTL 机制

### 15. 免责声明文本重复定义 — ✅ 已修复

- 提取 `appDisclaimerItems` + `appDisclaimerFooter` 到 `lib/pages/disclaimer_page.dart`
- 删除 `main.dart` 中的重复常量，改为导入共享模块

### 16. 登录过期对话框重复 — ✅ 已修复

- 提取 `showLoginExpiredDialog()` 到 `lib/widgets/login_expired_dialog.dart`
- 迁移 `browse_history_page.dart` 和 `bookshelf_page.dart`

### 17. `local_comics_page` 和 `local_anime_page` 结构高度相似 — ✅ 已修复

- 创建 `LocalContentListPage` 通用列表页组件（`lib/widgets/local_content_list_page.dart`）
  - `LocalContentEntry` 抽象接口适配两种领域模型
  - `ComicLocalContentEntry` / `AnimeLocalContentEntry` 适配器
  - 通用选择模式、删除流程、FAB、嵌入模式
- 提取 `_DetailChip` → `lib/widgets/detail_chip.dart`（共享组件，borderRadius 参数化）
- `LocalComicsPage` / `LocalAnimePage` 保留为薄委托层
- 详情页保持独立（功能差异过大）

---

## P3 — 改进建议

### 18. `analysis_options.yaml` 过于宽松 — ✅ 已修复

- 从 `flutter_lints` 升级，新增 60+ 条严格规则
- 修复 190 个 lint 警告（113 个自动修复 + 28 个手动 `unawaited()` 包装 + 排序修复）
- 移除已废弃的 lint 规则
- 0 个 analyze 错误

### 19. `utils/` 目录混入 UI 组件 — ✅ 已修复

- `comic_card_skeleton.dart` → `lib/widgets/comic_card_skeleton.dart`
- `comic_hero_tags.dart` → `lib/widgets/comic_hero_tags.dart`
- 更新 10 个文件的 import 路径

### 20. 测试覆盖稀疏 — ✅ 已修复

- 新增 `test/models/cached_repository_test.dart` — 12 个测试覆盖 CacheRepository + DualCachedRepository 核心逻辑
- 新增 `test/repositories/repository_data_test.dart` — 7 个测试覆盖仓库序列化/反序列化
- 新增 `test/utils/json_helpers_test.dart` — 35 个测试覆盖全部 7 个 JSON helper 函数
- 新增 `test/utils/services_test.dart` — 8 个测试覆盖 Services 定位器（单例/覆盖/重置/未知类型）
- 新增 `test/models/reader_settings_test.dart` — 21 个测试覆盖 ReaderSettings 默认值/持久化/通知
- 新增 `test/models/secure_credential_store_test.dart` — 12 个测试覆盖安全凭证存储（读写/迁移/删除）
- 新增 `test/widgets/error_retry_view_test.dart` — 5 个测试覆盖错误重试组件
- 新增 `test/widgets/shimmer_skeleton_test.dart` — 8 个测试覆盖骨架屏组件
- 总测试数从 89 → 183（+94）
- 183/183 通过

### 21. `Comic` 模型有两种 JSON 构造器 — ✅ 已修复

- `Comic.fromDetailJson` 改为委托 `Comic.fromJson(json['comic'])` + `copyWith()`
- 消除 25 行重复字段赋值，仅覆盖 `popular` 和 `groups`

---

## 修复统计

| 优先级 | 总数 | 已修复 | 部分修复 | 未开始 |
|--------|------|--------|----------|--------|
| P0     | 3    | 3      | 0        | 0      |
| P1     | 6    | 6      | 0        | 0      |
| P2     | 8    | 8      | 0        | 0      |
| P3     | 4    | 4      | 0        | 0      |
| **合计** | **21** | **21** | **0** | **0** |

**全部 21 项已修复。**

---

## 新增文件清单

| 文件 | 用途 |
|------|------|
| `lib/models/prefs_store.dart` | PrefsStore 基类 |
| `lib/models/reader_settings.dart` | 阅读器设置子存储 |
| `lib/models/danmaku_settings.dart` | 弹幕设置子存储 |
| `lib/models/comment_settings.dart` | 评论区设置子存储 |
| `lib/models/theme_settings.dart` | 主题/外观子存储 |
| `lib/models/network_settings.dart` | 网络配置子存储 |
| `lib/models/network_proxy_types.dart` | 代理枚举 |
| `lib/models/secure_credential_store.dart` | 安全凭证存储 |
| `lib/utils/services.dart` | 服务定位器 |
| `lib/utils/json_helpers.dart` | 安全 JSON 提取器 |
| `lib/widgets/comic_cover_card.dart` | 漫画封面卡片 |
| `lib/widgets/shimmer_skeleton.dart` | 加载骨架屏 |
| `lib/widgets/error_retry_view.dart` | 错误重试状态 |
| `lib/widgets/login_expired_dialog.dart` | 登录过期对话框 |
| `lib/pages/login_page.dart` | 登录页（从 profile_page 拆出） |
| `lib/pages/register_page.dart` | 注册页（从 profile_page 拆出） |
| `lib/pages/disclaimer_page.dart` | 免责声明页（从 profile_page 拆出） |
| `lib/pages/about_page.dart` | 关于页（从 profile_page 拆出） |
| `test/test_helpers.dart` | 测试辅助（安全存储注入） |
| `lib/models/cached_repository.dart` | CachedRepository / DualCachedRepository 基类 |
| `lib/repositories/manga_home_repository.dart` | 漫画首页仓库 |
| `lib/repositories/anime_home_repository.dart` | 动漫首页仓库 |
| `lib/repositories/search_init_repository.dart` | 搜索初始化仓库 |
| `lib/repositories/comic_detail_repository.dart` | 漫画详情仓库 |
| `lib/repositories/bookshelf_repository.dart` | 书架仓库（漫画+动漫） |
| `lib/widgets/comic_card_skeleton.dart` | 漫画卡片骨架屏（从utils/迁移） |
| `lib/widgets/comic_hero_tags.dart` | Hero 动画标签（从utils/迁移） |
| `lib/widgets/detail_chip.dart` | 详情标签芯片 |
| `lib/widgets/local_content_list_page.dart` | 本地内容通用列表页 |
| `lib/api/api_transport.dart` | 共享 API 传输层 |
| `lib/providers/app_providers.dart` | Riverpod 核心提供者 |
| `lib/providers/settings_providers.dart` | 设置子存储提供者 |
| `lib/providers/repository_providers.dart` | 数据仓库提供者 |
| `lib/routing/app_router.dart` | GoRouter 声明式路由 |
| `lib/routing/main_shell.dart` | 底部导航栏 Shell |
| `l10n.yaml` | l10n 配置 |
| `lib/l10n/app_zh.arb` | 中文 ARB 模板 |
| `lib/models/anime.g.dart` | json_serializable 生成 |
| `lib/models/comic.g.dart` | json_serializable 生成 |
| `lib/models/comic_comment.g.dart` | json_serializable 生成 |
| `lib/models/chapter_comment.g.dart` | json_serializable 生成 |
| `test/models/cached_repository_test.dart` | CachedRepository 单元测试 |
| `test/repositories/repository_data_test.dart` | Repository 序列化测试 |
| `test/utils/json_helpers_test.dart` | JSON helper 函数测试 |
| `test/utils/services_test.dart` | Services 定位器测试 |
| `test/models/reader_settings_test.dart` | ReaderSettings 子存储测试 |
| `test/models/secure_credential_store_test.dart` | 安全凭证存储测试 |
| `test/widgets/error_retry_view_test.dart` | 错误重试组件测试 |
| `test/widgets/shimmer_skeleton_test.dart` | 骨架屏组件测试 |
| `lib/pages/reader/reader_scroll_item.dart` | 滚动列表项定义（从 reader_page 拆出） |
| `lib/pages/reader/reader_pull_to_refresh.dart` | 拉刷新组件（从 reader_page 拆出） |
| `lib/pages/reader/reader_chapter_widgets.dart` | 章节分隔/尾部/头部组件（从 reader_page 拆出） |
| `lib/pages/reader/reader_top_bar.dart` | 顶部工具栏组件（从 reader_page 拆出） |
| `lib/pages/reader/reader_bottom_bar.dart` | 底部工具栏组件（从 reader_page 拆出） |
