# Repository Guidelines

## Project Structure & Module Organization

Platform folders (`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`) hold only platform-specific integration code. Static assets live in `assets/` and must be declared in `pubspec.yaml`. `ref/`（gitignored）存放接口文档，仅作参考 —— never import from it, and never cite anything under `ref/` as current behaviour.

### `lib/` 一级目录速览

| 目录 | 职责 |
| ------ | ---------- |
| `api/` | `ApiTransport` + 领域 API（`manga/` `network/` `novel/` `user/` 子目录）、`ai_api.dart`、`hitokoto_api.dart`（一言）、`copy_settings_auto_updater.dart`，`api_client.dart` 为 facade |
| `models/` | 数据模型 `fromJson`/`toJson`（基类 `cached_repository.dart` 与 `secure_credential_store.dart` 也在此） |
| `repositories/` | 各领域 `CachedRepository` 子类（manga home + copy home、comic detail、bookshelf、search init、小说正文缓存）与小说数据源 `novel_reader_source.dart` —— 实现 `models/cached_repository.dart` 基类 |
| `providers/` | Riverpod providers：`app_providers`（单例）、`settings_providers`（子 store）、`repository_providers`（数据仓库）、`novel_providers`（小说）、`backup_providers`（备份） |
| `pages/` | 页面与路由目标；大页面按宿主旁的子目录拆分 |
| `routing/` | `app_router.dart`（GoRouter 声明 + `AppRoutes` + `*Extra` 传参类）、`MainShell`（底部导航）、`dismiss_keyboard_observer.dart` |
| `theme/` | 设计令牌：spacing/radius/shadows/typography/icon-size/status-colors + `player_chrome`/`reader_chrome`/`novel_reader_theme` |
| `widgets/` | 复用组件（骨架、错误态、登录过期、列表页等）—— 模式见 `docs/widgets.md` |
| `backup/` | 备份子系统：本地/WebDAV、加解密编解码、分类筛选、定时调度与日志（`backup_scheduler.dart`、`webdav_client.dart`） |
| `utils/` | JSON 安全助手、`AppLogger`、`Services`（服务定位器）、下载/小说下载管理、阅读历史与统计、应用更新等 |
| `l10n/` | ARB 模板与生成的 `app_localizations*.dart`（`app_zh.arb` 为模板，`app_zh_Hant.arb` 为繁体镜像） |

大文件按宿主旁的 `*_parts/` 或页面名子目录拆分：宿主写 `part '子目录/yyy.dart';`，分片以 `part of '../host.dart';` 挂载；宿主方法可用 `extension HostXxxPart on Host`，辅助组件/函数也可直接定义在分片中。改动时沿用所在模块的拆分方式。

## Maintenance Scope

Anime was removed outright (`569f482`), not merely frozen — treat it as absent, not as deprecated code to keep compiling. Two live product areas: **漫画（拷贝 + 热辣）** 与 **轻小说**. Both are active; 轻小说 design details live in `docs/novel.md`. `ref/` 已被 gitignore 排除，只存放接口文档 — never import from it.

## Architecture Patterns

### State Management: Riverpod (incremental)
- **New pages**: Use `ConsumerStatefulWidget` + `ref.read(provider)` for dependencies.
- **Existing pages**: Still use singleton access (`UserManager()`, `ApiClient()`) — both patterns coexist widely; `lib/utils/services.dart` (`Services.api`, `Services.override<T>()` for tests) is the intended middle ground but is barely adopted yet.
- **Providers live in `lib/providers/`**: `app_providers.dart` (singletons), `settings_providers.dart` (sub-stores), `repository_providers.dart` (data repos).

### Navigation: GoRouter
- All routes defined declaratively in `lib/routing/app_router.dart` with `AppRoutes` name constants.
- Use `context.pushNamed(AppRoutes.xxx)` instead of `Navigator.push(MaterialPageRoute(...))`.
- For routes that need extra data, use `extra` parameter with typed classes (`ComicDetailExtra`, `ReaderExtra`, `NovelReaderExtra`, `RankingExtra`).
- Bottom-nav shell uses `StatefulShellRoute` via `MainShell`. The horizontal swipe between branches and the GNav capsule bar are product features — do not remove them in a refactor.
- `dismiss_keyboard_observer.dart` suppresses the keyboard reappearing when returning to the home/search branch; `test/routing/main_shell_focus_test.dart` locks that behaviour down.

### API Layer: Transport + Domain Classes
- Call sites: `ApiClient().manga.getMangaHome()` not `ApiClient().getMangaHome()`.
- AI 相关调用走 `AiApi`（`lib/api/ai_api.dart`），它**不**挂在 `ApiClient` 上，用独立的 `AppDio` 与 `AiSettings`；评论摘要、章节分析都从这里出。
- 分层背景（`ApiTransport` / 领域 API 类 / `ApiClient` facade、测试替身）见 `docs/architecture.md`。

### Data Layer: CachedRepository
- Call `repo.load()` for auto-cache-first, `repo.loadFromCache()` for cache-only, `repo.invalidateCache()` to refresh. Concurrent `load()` calls share one in-flight future, so callers never stampede the API.
- Cache I/O goes through `AppStorage.cache` / `AppStorage.preferences` (`lib/utils/app_storage.dart`), which is what keeps tests away from real SharedPreferences.
- 新建/改造 repository 前读 `docs/architecture.md`：仓库需定义的成员、四种缓存策略（parallel / sequential / TTL-gate / API-transparent）与 `DualCachedRepository` 的唯一用例。

### Model Serialization
- 大多数模型手写 `fromJson`/`toJson`；`comic.dart`、`chapter_comment.dart`、`comic_comment.dart` 走 `json_serializable`（3 个 `.g.dart`，共 6 个生成类）。改完生成类跑 `dart run build_runner build`。
- 动某个模型前先查 `docs/architecture.md` 的序列化一节：哪些类走生成、哪些手写、为什么 `comic.dart` 两种风格混用。

### Internationalization
- `l10n.yaml` at project root configures `gen-l10n`. Template ARB is `app_zh.arb`; `app_zh_Hant.arb` holds the Traditional Chinese mirror (简繁双语).
- Access strings via `AppLocalizations.of(context)!.keyName`.
- Parameterized strings become methods: `l10n.deleteLocalComicsContent(count)` returns `String`.

### UserManager: Facade + Sub-stores
- `UserManager` 是 facade，内部委托给同为单例的子 store（`ReaderSettings`、`CommentSettings`、`ThemeSettings`、`NetworkSettings`、`CopyAccountStore`，`Services.reader` == `UserManager().reader`）；子 store 变更经 facade 单次 `notifyListeners()` 转发 —— 只关心单一域就监听子 store 本身。
- **共有偏好已统一由子 store 保存，`UserManager` 保留纯委托接口** —— 新增/改动偏好时只在所属子 store 定义字段、默认值和持久化；facade 不再缓存第二份状态或额外通知。平台图标与兼容逻辑的边界见 `docs/architecture.md`。

## Build, Test, and Development Commands

Run these from the repository root:

发布构建前核对本地与对应 CI job 的 Flutter 版本（以 `.flutter-version` 为准），二者须保持一致；依赖一律用 `flutter pub get --enforce-lockfile` 安装，并以 `git diff --exit-code -- pubspec.lock` 确认锁文件未变化。依赖源固定为 pub.dev，不要设置 `PUB_HOSTED_URL`。

- `flutter pub get --enforce-lockfile` — install dependencies from pub.dev
- `flutter run` — launch on current device/emulator
- `flutter analyze` — run lint rules from `analysis_options.yaml`; baseline 无 error/warning，仍有既有 info（见 Testing）
- `flutter test test/xxx_test.dart --reporter compact` — 默认只运行与改动相关的测试；全量测试须用户明确要求
- `flutter build apk --release --target-platform android-arm64` — Android release artifact
- `dart format <改动的 Dart 文件路径…>` — 仅格式化本次改动文件，仓库未强制全量格式化
- `dart run build_runner build` — regenerate `.g.dart` files after model changes
- `flutter gen-l10n` — regenerate localization files after ARB changes
- `run-kira` — skill to start / stop / hot-restart / hot-reload kira。本机 gitignored 的配置有 `PostToolUse(Edit|Write)` 自动热重载 hook，新克隆不能假定存在。代码改动收尾先跑 `flutter analyze`，再在应用已运行且用户允许时热重载并检查日志；应用未运行时，冷启动须先征得用户同意。

### Other Entry Points
- `scripts/`: PowerShell helpers — `run.ps1 <win|mumu|emu>` (device boot + `KIRA_DEVICE`), `build_apk.ps1`, `build_windows.ps1`, `count_lib_dart_lines.ps1`.
- `docs/`: `persistence-and-cache.md`（动存储前必读）、`novel.md`（轻小说设计）、`architecture.md`（API 分层 / 缓存仓库解剖 / 序列化清单 / UserManager 偏好归属与通知）、`platform-build.md`（Windows / Android 构建排查）、`widgets.md`（复用组件模式）、`TODO.md`、`CHANGELOG.md`.
- 发版 / 续发 / 发布日志修正：使用项目 `/release` skill；自然语言发版请求先读 `.claude/skills/release/SKILL.md`，按信息确认、日志审查、发布批准三道关卡执行。
- `.github/workflows/`: `build-ci.yml`（`v*-beta*` tag 或手动触发 Android 构建）、`release.yml`（非 beta 的 `v*` tag 或手动触发正式版构建）、`release-all.yaml`（手动、全平台）。

### Platform Build Notes (on-demand)

Windows / Android 构建问题按报错先读 `docs/platform-build.md`，不要直接改构建配置：

- **Windows**：`C4819` / `STL1011` / `C1083`（ephemeral 缺文件）/ `C1041`（PDB 锁）、要动 `windows/CMakeLists.txt`、想加媒体/视频依赖 —— 各报错的处理办法在文档里；删 `/utf-8` 是看似顺手、实会让中文区域系统构建失败的"修复"。
- **Android**：`flutter clean` 后 `flutter run` 报 `package identifier or launch activity not found` —— 先跑一次 `flutter build apk --debug` 即恢复；**不要**给 `MainActivity` 加 LAUNCHER intent-filter、也不要禁用它（会破坏切换 logo 功能），原因见文档。

### Platform Scope
Android 是主维护目标，Windows 是开发/调试宿主。维护定位不等于构建产物：`release.yml` 产出 arm/arm64/x64 APK 与 Windows 安装包；`release-all.yaml` 还构建 macOS/Linux，后二者不手工维护。`pubspec.yaml` 没有 `platforms:` 键；不要添加该键或仅为调试宿主引入平台原生依赖。

## Coding Style & Naming Conventions

- 2-space indentation, trailing commas where they improve widget diffs, small focused widgets.
- `PascalCase` for classes/widgets, `camelCase` for members/methods, `snake_case.dart` for filenames, leading `_` for private APIs.
- **Never** use `as` type casts on dynamic JSON — use the safe JSON helpers (`jsonString`, `jsonInt`, `jsonList`, `jsonMap`, `jsonDouble`, `jsonBool`, `NullIfEmptyString`) from `lib/utils/`.
- **Never** leave empty catch blocks — use `AppLogger.recordWarning(error, stackTrace)`.
- **Never hide the real error from the user.** When a request/operation fails, show the underlying cause instead of replacing it with a generic fixed string. Use `NetworkError.message(e, l10n: l10n)` for Dio/network errors and `novelErrorMessage(e, fallback: ...)` for novel API errors; a fixed l10n string may only serve as the fallback when the error carries no text. Keep the original exception in logs (never a synthesized `StateError`). Only deliberate exceptions: IP-block guidance copy, and novel code 210 which intentionally shows the full response body.
- **Never** use `@ts-ignore`-equivalent suppression; fix the type error instead.
- Prefer `const` constructors where possible.
- Import `comic.dart` with `hide Theme` to avoid Flutter `Theme` conflict.
 - **Prefer design tokens over hard-coded values**: use `AppSpacing` (4/8/12/16/20/24), `AppRadius` (xs~xl/full + `*R` getters), `AppIconSize` (xs 12 / sm 16 / md 18 / lg 20 / xl 24 / placeholder 32 / empty 48 / display 64), and the `ReaderChrome` color tokens. Only fall back to literals for genuinely ad-hoc values that carry component-specific meaning (e.g. a one-off 10px padding). `PlayerChrome` is a leftover class with no call sites (the video player went away with anime) — `ReaderChrome` is the live one.
 - **Text styles**: derive from `Theme.of(context).textTheme`; use `AppTypography.meta(tt)` for the small grey meta line (12px) and `AppTypography.fabLabel(tt)` for FAB labels instead of hand-writing `TextStyle(fontSize: …)`. Do not add page-local TextTheme copies.
 - **Component radius ladder**: 卡片 lg(16) / 对话框与弹层 xl(20) — enforced by `cardTheme`/`dialogTheme`/`bottomSheetTheme` in `main.dart`; don't override shapes per page.
 - **Semantic colors**: status colors go through `AppStatusColors` (`success/warning/danger/neutral/fill`, plus `hotAccent` for the comment hot-badge orange); never hand-code `Colors.green/orange/red` or raw `Color(0x…)` for these roles.

## Reusable Widget Patterns (on-demand)

新建或抽取可复用组件（放 `lib/widgets/`）前先读 `docs/widgets.md`。骨架屏 / 错误重试 / bottom sheet / section header / 封面占位 / 本地内容列表页 / 登录过期弹窗都有既定组件：`ShimmerShell` + `ShimmerBox`、`ErrorRetryView` / `SliverErrorRetryView`、`showAppSheet` / `AppSheet`、`SectionHeader`、`CoverPlaceholder`、`LocalContentListPage` + `LocalContentEntry`、`showLoginExpiredDialog` —— 用既定组件，不要手搓替代品。网络封面用 `CoverImage`，封面飞行用 `AppHero`，二者内置「减少动画」适配；细节见同一文档。

## Testing Guidelines

- Use `flutter_test` for unit and widget coverage. Files: `*_test.dart`. 新测试按 `lib/` 路径镜像到 `test/`：`pages/`、`api/`、`backup/`、`models/`、`repositories/`、`routing/`、`theme/`、`utils/`、`widgets/` 均有对应子目录；根目录保留小说、拷贝账号等既有用例。
- `test/test_helpers.dart` is mandatory for widget tests: `wrapWithApp(child)` injects the `AppLocalizations` delegate — a bare `MaterialApp` makes `AppLocalizations.of(context)!` throw. Call `setupSecureCredentialStoreForTest()` in `setUp` and `teardownSecureCredentialStoreForTest()` in `tearDown` to isolate account state. Persistence regressions must additionally exercise the default prefs-backed store across recreated instances.
- For `CachedRepository` subclasses: override `loadFromCache`/`saveToCache` with in-memory maps to avoid SharedPreferences in tests.
- New features and bug fixes should include tests when the behavior can be exercised outside platform-only code.
- **不要擅自跑全量测试**：默认只跑与改动相关的测试文件（`flutter test test/xxx_test.dart …`）；全量 `flutter test` 耗时且输出量大，仅在用户明确要求时执行。
- Baseline: `flutter analyze` 无 error/warning（既有 info：`test/pages/novel_reader_paginator_test.dart` 的大括号规则）；全量 `flutter test` 仍有个别既有失败（如 `test/novel_repository_test.dart` 的 TTL 持久化用例，失败集合会随提交漂移），判回归前先在干净工作区复跑。

## Commit & Pull Request Guidelines

Emoji-prefixed Conventional Commit types with concise Chinese summaries:
- `✨ feat: 添加检查更新功能`
- `🐛 fix: 登录过期后提醒用户登录`

`scripts/git-hooks/pre-commit` 提交前会跑 `scripts/update_version_code.ps1`，把 `pubspec.yaml` 的 versionCode 改成「HEAD 提交数 + 1」并自动 `git add` —— 每次提交都会带上这处改动，属预期行为，不要当成误提交回退。新克隆的仓库需先执行一次 `git config core.hooksPath scripts/git-hooks` 才会启用。

普通开发不要更新 `docs/CHANGELOG.md`；正式发版按 `/release` skill 准备完整日志并经用户审查，确认后才提交、打标签和推送。

## Security

- Do not commit signing material (`android/key.properties`, keystores).
- Credentials use `SecureCredentialStore`, backed by app-private SharedPreferences. The historical class name and `secure_mirror_*` prefix are compatibility names, not encryption guarantees; runtime Keystore/Keychain and `flutter_secure_storage` are no longer used.
- Availability is the chosen trade-off: an upgrade may require one login when old credentials exist only in the encrypted store, but subsequent cold starts must retain the newly saved session. Preserve legacy plaintext migration, logout markers, write-failure handling, backup encryption, and credential exclusions from ordinary backups/cache cleanup. See `docs/persistence-and-cache.md` before changing this path.
- Use `InMemorySecureCredentialStore` for isolated tests and the default prefs-backed store for persistence regressions.

## Persistence & Cache (on-demand)

涉及持久化存储/缓存改动时（新增用户偏好、业务缓存、敏感凭据、阅读历史等），先读 `docs/persistence-and-cache.md`：三层存储后端（`AppStorage.memory/cache/preferences`）、键名前缀约定、`CachedRepository` 用法与决策流程都在其中。
