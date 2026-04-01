# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the app code. Keep network access in `lib/api/`, domain and state objects in `lib/models/`, screens and UI flows in `lib/pages/`, and reusable helpers in `lib/utils/`. The entry point is `lib/main.dart`.

Platform folders (`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`) should only hold platform-specific integration code. Static assets live in `assets/` and must also be declared in `pubspec.yaml`. Release notes belong in `docs/CHANGELOG.md`. Use `ref/` for reference material, not production code.

## Build, Test, and Development Commands
Run these from the repository root:

- `flutter pub get` installs Dart and Flutter dependencies.
- `flutter run` launches the app on the current device or emulator.
- `flutter analyze` runs the `flutter_lints` rules from `analysis_options.yaml`.
- `flutter test` runs automated tests. Add new tests under `test/`.
- `flutter build apk --release --target-platform android-arm64` builds the Android artifact used by the release workflow.
- `dart format lib test` formats source files before review.

## Coding Style & Naming Conventions
Follow standard Dart style: 2-space indentation, trailing commas where they improve widget diffs, and small focused widgets. Use `PascalCase` for classes and widgets, `camelCase` for members and methods, `snake_case.dart` for filenames, and a leading underscore for private APIs.

Prefer keeping page-specific UI logic inside `lib/pages/` and moving reusable behavior into `models/` or `utils/` once it is shared.

## Testing Guidelines
Use `flutter_test` for unit and widget coverage. Name files `*_test.dart` and mirror the source area when possible, for example `test/pages/home_page_test.dart`. New features and bug fixes should include tests when the behavior can be exercised outside platform-only code.

## Commit & Pull Request Guidelines
Recent history uses emoji-prefixed Conventional Commit types with concise Chinese summaries, for example `✨ feat: 添加检查更新功能` and `🐛 fix: 登录过期后提醒用户登录`. Keep that format for new commits.

PRs should include a short behavior summary, linked issues when applicable, test/analyze results, and screenshots or screen recordings for UI changes. If the change affects a release, update `docs/CHANGELOG.md` in the same PR.

## Security & Release Notes
Do not commit signing material such as `android/key.properties` or keystores. The GitHub release workflow expects Android signing secrets and publishes tag-based releases named `v*`.

## Notification
When you have completed all the tasks given by the user and have finished the final summary, use the notification skill to notify the user that the task is complete, title="kira", message="All tasks have been completed"
