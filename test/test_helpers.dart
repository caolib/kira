import 'package:flutter/material.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/secure_credential_store.dart';

/// Call in setUp() for isolated tests that trigger UserManager.init().
///
/// Replaces the prefs-backed SecureCredentialStore with an in-memory store
/// that neither reads nor migrates legacy preferences. Persistence regressions
/// must use the default store with mocked SharedPreferences instead.
void setupSecureCredentialStoreForTest() {
  SecureCredentialStore.setInstance(InMemorySecureCredentialStore());
}

/// Call in tearDown() to restore the default prefs-backed instance.
void teardownSecureCredentialStoreForTest() {
  SecureCredentialStore.resetInstance();
}

/// Wraps [child] in a [MaterialApp] that has localization wired up.
///
/// Pages and widgets read copy through `AppLocalizations.of(context)!`. A bare
/// `MaterialApp` has no delegate for it, so `.of()` returns null and the widget
/// throws `Null check operator used on a null value` the moment it builds —
/// which is what every widget test here used to hit.
///
/// Defaults to `zh` (the template ARB) so tests can assert on Chinese strings.
/// Pass [locale] explicitly when checking the Traditional Chinese mirror.
///
/// Pass `wrapInScaffold: false` when [child] already provides its own
/// [Scaffold], as full pages do.
Widget wrapWithApp(
  Widget child, {
  bool wrapInScaffold = true,
  ThemeData? theme,
  TransitionBuilder? builder,
  Locale locale = const Locale('zh'),
}) {
  return MaterialApp(
    theme: theme,
    builder: builder,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: wrapInScaffold ? Scaffold(body: child) : child,
  );
}
