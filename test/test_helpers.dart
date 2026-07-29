import 'package:flutter/material.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/secure_credential_store.dart';

/// Call in setUp() for any test that triggers UserManager.init().
///
/// Replaces the platform-backed SecureCredentialStore with an in-memory
/// implementation so that unit tests don't require a real keychain/keystore.
void setupSecureCredentialStoreForTest() {
  SecureCredentialStore.setInstance(InMemorySecureCredentialStore());
}

/// Call in tearDown() to restore the default platform instance.
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
/// The locale is pinned to `zh` (the template ARB) so tests can assert on the
/// Chinese strings directly.
///
/// Pass `wrapInScaffold: false` when [child] already provides its own
/// [Scaffold], as full pages do.
Widget wrapWithApp(Widget child, {bool wrapInScaffold = true}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: wrapInScaffold ? Scaffold(body: child) : child,
  );
}
