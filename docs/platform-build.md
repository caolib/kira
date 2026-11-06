# Platform Build Notes

Windows / Android 构建故障排查与禁改项。`CLAUDE.md` 只保留指针与硬性禁令；报错出现时先来本文，不要直接改构建配置。

## Windows

`windows/CMakeLists.txt` passes `/utf-8` to MSVC and silences the STL1011 experimental-coroutine assertion. Do not remove either: on non-UTF-8 system locales (Chinese code page 936) MSVC reads sources using the system code page, so UTF-8 bytes in third-party plugin sources raise C4819 — which `APPLY_STANDARD_SETTINGS`' `/WX` promotes to a hard error (`connectivity_plus` fails this way); STL1011 comes from `flutter_inappwebview_windows` and `permission_handler_windows` still using `<experimental/coroutine>` under MSVC 14.51+.

If `ephemeral/cpp_client_wrapper/*.cc` are reported missing (C1083), the Windows engine artifacts extracted incompletely: run `flutter clean` then `flutter precache --windows`.

Do not add media/video dependencies for Windows debugging: the player stack is gone, `pubspec.lock` has no `media_kit` entry, and nothing in `lib/` references it. A residual `C1041` PDB-lock error after `rm -rf build/windows/x64` is a transient MSVC parallel-compile race — just retry the build.

## Android

`scripts/*.ps1` are UTF-8 **without BOM** and contain Chinese text. Windows PowerShell 5.1 (`powershell.exe`) parses them with the system ANSI codepage (GBK on zh-CN), producing mojibake and parser errors like `TerminatorExpectedAtEndOfString`. Run them with **PowerShell 7** (`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build_apk.ps1`), which defaults to UTF-8. Adding a UTF-8 BOM to the scripts would fix 5.1 too.

After `flutter clean`, `flutter run -d <android>` fails with `package identifier or launch activity not found`. **Run `flutter build apk --debug` once first**, then `flutter run` works again.

Why: the launcher entry lives in `<activity-alias>` (`LauncherDefault` / `LauncherAlt1`, required by the switchable-logo feature) and `MainActivity` itself carries no LAUNCHER intent-filter. When a built APK exists Flutter reads it via `aapt dump badging`, which resolves aliases correctly; with no APK it falls back to parsing the source manifest, and `flutter_tools/lib/src/android/application_package.dart` only iterates `<activity>` — it does not recognise `<activity-alias>`.

Do **not** "fix" this by giving `MainActivity` a LAUNCHER intent-filter: that adds a second launcher icon and breaks logo switching. Disabling `MainActivity` is also wrong — an alias whose `targetActivity` is disabled stops working.
