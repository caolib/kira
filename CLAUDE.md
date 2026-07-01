# Repository Guidelines

## Project Structure & Module Organization

```
lib/
  main.dart              — App entry point, ProviderScope + MaterialApp.router
  api/
    api_transport.dart   — Shared Dio instance, auth, cache headers, host rotation
    api_client.dart      — Facade: creates ApiTransport, exposes .manga/.anime/.network/.user
    manga/manga_api.dart — MangaApi(ApiTransport _t) — standalone class, not a mixin
    anime/anime_api.dart — AnimeApi(ApiTransport _t)
    network/network_api.dart — NetworkApi(ApiTransport _t)
    user/user_api.dart   — UserApi(ApiTransport _t)
  models/
    cached_repository.dart   — CachedRepository<T> + DualCachedRepository<A,B> base classes
    comic.dart               — Comic, Author, Theme, ComicGroup, MangaTopic (simple models use json_serializable)
    anime.dart               — Anime, AnimeTag, AnimeCompany, AnimeChapterLine (simple models use json_serializable)
    comic_comment.dart       — ComicComment (json_serializable)
    chapter_comment.dart     — ChapterComment (json_serializable)
    user_manager.dart        — Facade: forwards to sub-stores (ReaderSettings, ThemeSettings, etc.)
    user_manager/
      prefs_store.dart       — Base class for SharedPreferences-backed stores
      reader_settings.dart   — Reader configuration sub-store
      danmaku_settings.dart  — Danmaku configuration sub-store
      comment_settings.dart  — Comment display sub-store
      theme_settings.dart    — Theme mode/fonts sub-store
      network_settings.dart  — Proxy/API host sub-store
      network_proxy_types.dart — Enum for proxy types
  pages/                 — Screen widgets (StatefulWidget or ConsumerStatefulWidget)
  widgets/               — Shared UI components
    comic_cover_card.dart     — Reusable comic cover card
    shimmer_skeleton.dart     — ShimmerBox, ShimmerShell, ComicCoverSkeletonGrid, ComicRowSkeletonList
    error_retry_view.dart     — ErrorRetryView + SliverErrorRetryView
    local_content_list_page.dart — Generic local content list (LocalContentEntry interface)
    detail_chip.dart          — Shared DetailChip widget
    comic_card_skeleton.dart  — Moved from utils/
    comic_hero_tags.dart      — Moved from utils/
    login_expired_dialog.dart — Extracted login-expired dialog
  repositories/          — CachedRepository subclasses for each data domain
    manga_home_repository.dart
    anime_home_repository.dart
    search_init_repository.dart
    comic_detail_repository.dart
    bookshelf_repository.dart (ComicBookshelfRepository + AnimeBookshelfRepository)
  providers/             — Riverpod providers (incremental migration)
    app_providers.dart        — Singleton providers: userManagerProvider, apiClientProvider, etc.
    settings_providers.dart   — Sub-store providers derived from userManagerProvider
    repository_providers.dart — Repository providers
  routing/
    app_router.dart       — GoRouter configuration with named routes (AppRoutes constants)
    main_shell.dart       — Bottom-nav shell via ShellRoute
  l10n/
    app_zh.arb            — Chinese strings (template ARB)
    app_localizations.dart — Generated localizations
  utils/                 — Helpers (AppLogger, AppStorage, toast, etc.)
```

Platform folders (`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`) hold only platform-specific integration code. Static assets live in `assets/` and must be declared in `pubspec.yaml`. Release notes belong in `docs/CHANGELOG.md`. Use `ref/` for reference material, not production code.

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
- `l10n.yaml` at project root configures `gen-l10n`. Template ARB is `app_zh.arb` (Chinese only currently).
- Access strings via `AppLocalizations.of(context)!.keyName`.
- Parameterized strings become methods: `l10n.deleteLocalComicsContent(count)` returns `String`.

### UserManager: Facade + Sub-stores
- `UserManager` is a singleton facade. Internally delegates to `ReaderSettings`, `DanmakuSettings`, `ThemeSettings`, etc.
- Sub-stores are independent `ChangeNotifier`s — can be used directly or through UserManager.
- `testInstance` supports dependency injection in tests without changing 85+ call sites.

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

### Windows Build Note
If building on Windows and `flutter_secure_storage` fails to find ATL, ensure `windows/CMakeLists.txt` includes the ATL auto-discovery block that scans all MSVC tool versions for `atlmfc`.

## Coding Style & Naming Conventions

- 2-space indentation, trailing commas where they improve widget diffs, small focused widgets.
- `PascalCase` for classes/widgets, `camelCase` for members/methods, `snake_case.dart` for filenames, leading `_` for private APIs.
- **Never** use `as` type casts on dynamic JSON — use the safe JSON helpers (`jsonString`, `jsonInt`, `jsonList`, `jsonMap`, `jsonDouble`, `jsonBool`, `NullIfEmptyString`) from `lib/utils/`.
- **Never** leave empty catch blocks — use `AppLogger.recordWarning(error, stackTrace)`.
- **Never** use `@ts-ignore`-equivalent suppression; fix the type error instead.
- Prefer `const` constructors where possible.
- Import `comic.dart` with `hide Theme` to avoid Flutter `Theme` conflict.

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
- `♻️ refactor: API层解耦为Transport+Domain类`
- `💄 ui: 骨架屏组件提取到widgets/`

PRs should include a short behavior summary, linked issues, test/analyze results, and screenshots for UI changes. Update `docs/CHANGELOG.md` if the change affects a release.

## Security

- Do not commit signing material (`android/key.properties`, keystores).
- Use `flutter_secure_storage` for credentials (token, password) — never SharedPreferences for secrets.
- `SecureCredentialStore` wraps flutter_secure_storage; `InMemorySecureCredentialStore` for tests.
- GitHub release workflow expects Android signing secrets and publishes tag-based releases named `v*`.
