# Repository Guidelines

## Project Structure & Module Organization

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

After completing any code change while a Flutter app is connected through the Dart MCP/DTD tools, run MCP hot reload (`dart_hot_reload`) before reporting completion, then check runtime errors.

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
