# Reusable Widget Patterns

抽取或新建可复用组件时（组件放 `lib/widgets/`），先确认下表场景是否已有既定组件 —— 每类都有定式，不要手搓替代品。

- **Skeleton/Shimmer**: Use `ShimmerBox` + `ShimmerShell` for loading states. Prefer `ComicCoverSkeletonGrid` or `ComicRowSkeletonList` for list placeholders. `ShimmerBox` must sit inside a `ShimmerShell` to animate.
- **Error states**: Use `ErrorRetryView` (box) or `SliverErrorRetryView` (in CustomScrollView). Provide `onRetry` callback. Inline banner-style errors (retry-all + dismiss, e.g. download center) are a different pattern — keep those bespoke.
- **Bottom sheets**: Build new sheets with `showAppSheet` / `AppSheet` (`lib/widgets/app_sheet.dart`). Modal sheets are centered with a default 640 dp width limit; when passing custom route constraints to `showModalBottomSheet`, keep `AppSheet.maxWidth` unless the sheet is intentionally full-screen. Sheets that must own their frame use `AppSheet.borderRadius` + `AppSheet.backgroundColor(cs)` + `AppSheetHandle()` — never hand-roll a 36x4 handle or a raw `Radius.circular(20/24)`.
- **Section headers**: Use `SectionHeader` (`lib/widgets/section_header.dart`) for "icon + 标题 (+ 更多)" rows; pass `trailing`/`onTap` for collapsible variants.
- **Collapsible content**: Use `CollapsibleContent` (`lib/widgets/collapsible_content.dart`) to preserve child state across expand/collapse. It disables hidden input/focus/semantics and settles immediately when reduced motion is enabled; use `ReaderSettingsFold` for a complete reader-settings group.
- **Cover images**: Use `CoverImage` (`lib/widgets/cover_image.dart`) for any network cover. It owns the fixed background, placeholder→image one-way fade-in, and reduced-motion handling; pass `placeholder` / `errorWidget` only when a page needs a custom tile. Never hand-write `CachedNetworkImage` fade params for covers.
- **Cover placeholders**: Use `CoverPlaceholder()` / `CoverPlaceholder.error()` for the default cover placeholder/error boxes.
- **Cover Hero flight**: Use `AppHero` (`lib/widgets/app_hero.dart`) instead of raw `Hero` so the flight is skipped when「减少动画」is on.
- **Generic list pages**: Use `LocalContentListPage` with the `LocalContentEntry` interface + per-domain adapters; the comic one lives in `lib/widgets/local_content_list_page.dart`, the novel one is `NovelLocalContentEntry` in `lib/pages/local_novels_page.dart` — follow that pattern rather than widening the widget.
- **书签组头**：漫画与轻小说共用 `BookmarkGroupHeader`（`lib/widgets/bookmark_group_header.dart`）。组头左滑露出置顶和删除，点右侧进度独立续读；不要给组内单条套这个组件，单条仍左滑直接删除。
- **Login expired**: Use `showLoginExpiredDialog(context, content: …)` from `lib/widgets/login_expired_dialog.dart` — pass the page-specific copy; do not hand-roll the AlertDialog.
