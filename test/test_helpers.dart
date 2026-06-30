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
