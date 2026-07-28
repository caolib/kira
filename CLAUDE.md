# Repository Guidelines

## Project Structure & Module Organization

Platform folders (`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`) hold only platform-specific integration code. Static assets live in `assets/` and must be declared in `pubspec.yaml`. Release notes belong in `docs/CHANGELOG.md`. `ref/` holds reference material only (dandanplay API docs, sample JSON, category scratch dirs) — never import from it in production code.

### `lib/` 一级目录速览

| 目录 | 职责 |
| ------ | ---------- |
| `api/` | `ApiTransport` + 领域 API（`manga/` `anime/` `network/` `user/` 子目录）、`dandanplay_api.dart`、`ai_api.dart`，`api_client.dart` 为 facade |
| `models/` | 数据模型 `fromJson`/`toJson`（基类 `cached_repository.dart` 与 `secure_credential_store.dart` 也在此） |
| `repositories/` | 各领域 `CachedRepository` 子类（manga/anime home、comic detail、bookshelf、search init）—— 实现 `models/cached_repository.dart` 基类 |
| `providers/` | Riverpod providers：`app_providers`（单例）、`settings_providers`（子 store）、`repository_providers`（数据仓库） |
| `pages/` | 页面与路由目标（最大目录，~59 文件） |
| `routing/` | `app_router.dart`（GoRouter 声明 + `AppRoutes`）、`MainShell`（底部导航） |
| `theme/` | 设计令牌：spacing/radius/shadows/typography + `player_chrome`/`reader_chrome` |
| `widgets/` | 复用组件（骨架、错误态、登录过期、列表页等）—— 见下方「Reusable Widget Patterns」 |
| `utils/` | JSON 安全助手、`AppLogger`、应用更新、中文转换等工具 |
| `l10n/` | ARB 模板与生成的 `app_localizations*.dart` |

## Maintenance Scope

Anime functionality is no longer maintained. Ignore anime-related code when making changes unless the user explicitly requests anime work.

## Architecture Patterns

### State Management: Riverpod (incremental)
- **New pages**: Use `ConsumerStatefulWidget` + `ref.read(provider)` for dependencies.
- **Existing pages**: Still use singleton access (`UserManager()`, `ApiClient()`) — both patterns coexist.
- **Providers live in `lib/providers/`**: `app_providers.dart` (singletons), `settings_providers.dart` (sub-stores), `repository_providers.dart` (data repos).

### Navigation: GoRouter
- All routes defined declaratively in `lib/routing/app_router.dart` with `AppRoutes` name constants.
- Use `context.pushNamed(AppRoutes.xxx)` instead of `Navigator.push(MaterialPageRoute(...))`.
- For routes that need extra data, use `extra` parameter with typed classes (`ComicDetailExtra`, `ReaderExtra`, `AnimeDetailExtra`).
- Bottom-nav shell uses `ShellRoute` via `MainShell`.

### API Layer: Transport + Domain Classes
- `ApiTransport` holds shared Dio instance, auth tokens, cache headers, host rotation logic.
- Domain API classes (`MangaApi`, `AnimeApi`, `NetworkApi`, `UserApi`) receive `ApiTransport` via constructor injection.
- `ApiClient` is a facade that creates the transport and exposes domain API objects as `.manga/.anime/.network/.user` fields.
- Call sites: `ApiClient().manga.getMangaHome()` not `ApiClient().getMangaHome()`.

### Data Layer: CachedRepository
- `CachedRepository<T>` and `DualCachedRepository<A,B>` in `lib/models/cached_repository.dart`.
- Each repository defines: `cacheKey`, `ttl`, `skipApiIfCacheFresh`, `deserialize`/`serialize`, `fetchFromApi()`.
- Call `repo.load()` for auto-cache-first, `repo.loadFromCache()` for cache-only, `repo.invalidateCache()` to refresh.
- 4 strategies: parallel (default), sequential, TTL-gate, API-transparent — configured via constructor params.

### Model Serialization
- **Simple models** (Author, Theme, ComicGroup, MangaTopic, AnimeTag, AnimeCompany, AnimeChapterLine, ComicComment, ChapterComment): use `json_serializable` with `@JsonSerializable(fieldRename: FieldRename.snake)`. Run `dart run build_runner build` after changes.
- **Complex models** (Comic, Anime, MangaHome, Chapter, etc.): hand-written `fromJson`/`toJson` — too many custom coercions for generated code.

### Internationalization
- `l10n.yaml` at project root configures `gen-l10n`. Template ARB is `app_zh.arb`; `app_zh_Hant.arb` holds the Traditional Chinese mirror (简繁双语).
- Access strings via `AppLocalizations.of(context)!.keyName`.
- Parameterized strings become methods: `l10n.deleteLocalComicsContent(count)` returns `String`.

### UserManager: Facade + Sub-stores
- `UserManager` is a singleton facade. Internally delegates to `ReaderSettings`, `DanmakuSettings`, `ThemeSettings`, etc.
- Sub-stores are independent `ChangeNotifier`s — can be used directly or through UserManager.
- Sub-store changes are forwarded through the facade's single `notifyListeners()`, so a listener on `UserManager` rebuilds on *any* settings change, not just the domain it cares about. Listen to the sub-store directly when that matters.
- **The split is still partial**: ~48 preference keys are declared in *both* `UserManager` and a sub-store, each keeping its own in-memory copy, and most `UserManager` setters write SharedPreferences directly instead of delegating. Changing such a key through one path does not update the other's copy. It does not currently misbehave only because the two paths happen to touch disjoint sets of settings (sub-stores are used directly only for newer settings like `reader.statusOverlay*` and `theme.appFontFamily`). **When touching one of these keys, route it through the sub-store and delete the `UserManager` copy** — see `readerMode` for the pattern.

## Build, Test, and Development Commands

Run these from the repository root:

- `flutter pub get` — install dependencies
- `flutter run` — launch on current device/emulator
- `flutter analyze` — run lint rules from `analysis_options.yaml` (60+ strict rules)
- `flutter test` — run automated tests under `test/`
- `flutter build apk --release --target-platform android-arm64` — Android release artifact
- `dart format lib test` — format source files before review
- `dart run build_runner build` — regenerate `.g.dart` files after model changes
- `flutter gen-l10n` — regenerate localization files after ARB changes
- `run-kira` — skill to start / stop / hot-restart / hot-reload the running kira app. Hot-reload is auto-triggered by a PostToolUse(Edit|Write) hook after code edits; reach for the skill explicitly for cold starts, hot-restarts, or stops.

### Windows Build Note
`flutter_secure_storage` (^10.3.1) is a dependency. If a Windows build fails to find ATL/MFC under a particular MSVC toolchain, add an ATL auto-discovery block to `windows/CMakeLists.txt` that scans installed MSVC versions for `atlmfc` — the current file does not need one for the default setup.

`windows/CMakeLists.txt` passes `/utf-8` to MSVC. Do not remove it: on non-UTF-8 system locales (Chinese code page 936) MSVC reads sources using the system code page, so UTF-8 bytes in third-party plugin sources raise C4819 — which `APPLY_STANDARD_SETTINGS`' `/WX` promotes to a hard error. `connectivity_plus` fails to compile without it.

If `ephemeral/cpp_client_wrapper/*.cc` are reported missing (C1083), the Windows engine artifacts extracted incompletely: run `flutter clean` then `flutter precache --windows`.

### Android Build Note
After `flutter clean`, `flutter run -d <android>` fails with `package identifier or launch activity not found`. **Run `flutter build apk --debug` once first**, then `flutter run` works again.

Why: the launcher entry lives in `<activity-alias>` (`LauncherDefault` / `LauncherAlt1`, required by the switchable-logo feature) and `MainActivity` itself carries no LAUNCHER intent-filter. When a built APK exists Flutter reads it via `aapt dump badging`, which resolves aliases correctly; with no APK it falls back to parsing the source manifest, and `flutter_tools/lib/src/android/application_package.dart` only iterates `<activity>` — it does not recognise `<activity-alias>`.

Do **not** "fix" this by giving `MainActivity` a LAUNCHER intent-filter: that adds a second launcher icon and breaks logo switching. Disabling `MainActivity` is also wrong — an alias whose `targetActivity` is disabled stops working.

## Coding Style & Naming Conventions

- 2-space indentation, trailing commas where they improve widget diffs, small focused widgets.
- `PascalCase` for classes/widgets, `camelCase` for members/methods, `snake_case.dart` for filenames, leading `_` for private APIs.
- **Never** use `as` type casts on dynamic JSON — use the safe JSON helpers (`jsonString`, `jsonInt`, `jsonList`, `jsonMap`, `jsonDouble`, `jsonBool`, `NullIfEmptyString`) from `lib/utils/`.
- **Never** leave empty catch blocks — use `AppLogger.recordWarning(error, stackTrace)`.
- **Never** use `@ts-ignore`-equivalent suppression; fix the type error instead.
- Prefer `const` constructors where possible.
- Import `comic.dart` with `hide Theme` to avoid Flutter `Theme` conflict.
- **Prefer design tokens over hard-coded values**: use `AppSpacing` (4/8/12/16/20/24), `AppRadius` (xs~xl/full + `*R` getters), and `ReaderChrome`/`PlayerChrome` color tokens. Only fall back to literals for genuinely ad-hoc values that carry component-specific meaning (e.g. a one-off 10px padding).

## Reusable Widget Patterns

When extracting a shared widget, place it in `lib/widgets/` and follow these patterns:

- **Skeleton/Shimmer**: Use `ShimmerBox` + `ShimmerShell` for loading states. Prefer `ComicCoverSkeletonGrid` or `ComicRowSkeletonList` for list placeholders.
- **Error states**: Use `ErrorRetryView` (box) or `SliverErrorRetryView` (in CustomScrollView). Provide `onRetry` callback.
- **Generic list pages**: Use `LocalContentListPage` with `LocalContentEntry` interface + adapters (`ComicLocalContentEntry`, `AnimeLocalContentEntry`).
- **Login expired**: Use `showLoginExpiredDialog(context)` from `lib/widgets/login_expired_dialog.dart`.

## Testing Guidelines

- Use `flutter_test` for unit and widget coverage. Files: `*_test.dart`, mirror source path under `test/`.
- For `CachedRepository` subclasses: override `loadFromCache`/`saveToCache` with in-memory maps to avoid SharedPreferences in tests.
- New features and bug fixes should include tests when the behavior can be exercised outside platform-only code.

## Commit & Pull Request Guidelines

Emoji-prefixed Conventional Commit types with concise Chinese summaries:
- `✨ feat: 添加检查更新功能`
- `🐛 fix: 登录过期后提醒用户登录`

Update `docs/CHANGELOG.md` if the change affects a release.

## Security

- Do not commit signing material (`android/key.properties`, keystores).
- Use `flutter_secure_storage` for credentials (token, password) — never SharedPreferences for secrets.
- `SecureCredentialStore` wraps flutter_secure_storage; `InMemorySecureCredentialStore` for tests.

## Persistence & Cache (on-demand)

涉及持久化存储/缓存改动时（新增用户偏好、业务缓存、敏感凭据、阅读历史等），先读 `docs/persistence-and-cache.md`。该文档说明三层存储后端、键名前缀约定、`CachedRepository` 用法与决策流程。常用事实：业务缓存与用户偏好共用 SharedPreferences、仅靠 `cache_` 前缀隔离；`SecureCredentialStore` 已实现但尚未启用。

## MCP Tools: code-review-graph

This project ships a knowledge graph. **Use graph tools BEFORE Grep/Glob/Read** for exploring code — faster, cheaper, and gives callers/dependents/test-coverage context file scanning cannot.

- **Explore / find symbols**: `semantic_search_nodes_tool` or `query_graph_tool` (patterns: callers_of, callees_of, imports_of, tests_for)
- **Impact / blast radius**: `get_impact_radius_tool`, `get_affected_flows_tool`
- **Code review**: `detect_changes_tool` (risk-scored) + `get_review_context_tool` (source snippets)
- **Architecture**: `get_architecture_overview_tool` + `list_communities_tool`
- **Refactor / dead code**: `refactor_tool`

The graph auto-updates on file changes via hooks. Fall back to Grep/Glob/Read only when the graph doesn't cover what you need.
