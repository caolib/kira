import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_store.dart';

/// General app behavior settings.
class GeneralSettings extends PrefsStore {
  static final GeneralSettings _instance = GeneralSettings._();
  factory GeneralSettings() => _instance;
  GeneralSettings._();

  static const _keyAutoCheckClipboardSharedLinks =
      'auto_check_clipboard_shared_links';

  bool _autoCheckClipboardSharedLinks = false;

  bool get autoCheckClipboardSharedLinks => _autoCheckClipboardSharedLinks;

  Future<void> initFromPrefs(SharedPreferences prefs) async {
    syncPrefs(prefs);
    _autoCheckClipboardSharedLinks =
        prefs.getBool(_keyAutoCheckClipboardSharedLinks) ?? false;
  }

  Future<void> setAutoCheckClipboardSharedLinks(bool enabled) async {
    if (_autoCheckClipboardSharedLinks == enabled) return;
    _autoCheckClipboardSharedLinks = enabled;
    await setBool(_keyAutoCheckClipboardSharedLinks, enabled);
  }
}
