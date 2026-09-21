import '../l10n/app_localizations.dart';

enum SettingsBackupErrorCode {
  emptyFile,
  invalidJson,
  invalidFormat,
  wrongApp,
  unsupportedVersion,
  missingContent,
  unsupportedField,
  invalidFieldFormat,
  unsupportedFieldType,
  tooLarge,
  passwordRequired,
  authenticationFailed,
  invalidEncryptionParameters,
  noCategories,
  busy,
  writeFailed,
  recoveryRequired,
  cancelled,
}

/// Never includes preference values, passwords, file contents or server bodies.
class SettingsBackupException implements Exception {
  final SettingsBackupErrorCode code;

  const SettingsBackupException(this.code);

  String localizedMessage(AppLocalizations l10n) => switch (code) {
    SettingsBackupErrorCode.emptyFile => l10n.settingsBackupEmptyFile,
    SettingsBackupErrorCode.invalidJson => l10n.settingsBackupInvalidJson,
    SettingsBackupErrorCode.invalidFormat => l10n.settingsBackupInvalidFormat,
    SettingsBackupErrorCode.wrongApp => l10n.settingsBackupWrongApp,
    SettingsBackupErrorCode.unsupportedVersion =>
      l10n.settingsBackupUnsupportedVersion,
    SettingsBackupErrorCode.missingContent => l10n.settingsBackupMissingContent,
    SettingsBackupErrorCode.unsupportedField =>
      l10n.settingsBackupUnsupportedField,
    SettingsBackupErrorCode.invalidFieldFormat =>
      l10n.settingsBackupInvalidFieldFormat,
    SettingsBackupErrorCode.unsupportedFieldType =>
      l10n.settingsBackupUnsupportedFieldType,
    SettingsBackupErrorCode.tooLarge => l10n.backupTooLarge,
    SettingsBackupErrorCode.passwordRequired => l10n.backupPasswordRequired,
    SettingsBackupErrorCode.authenticationFailed =>
      l10n.backupAuthenticationFailed,
    SettingsBackupErrorCode.invalidEncryptionParameters =>
      l10n.backupInvalidEncryptionParameters,
    SettingsBackupErrorCode.noCategories => l10n.backupSelectCategory,
    SettingsBackupErrorCode.busy => l10n.backupBusy,
    SettingsBackupErrorCode.writeFailed => l10n.backupWriteFailed,
    SettingsBackupErrorCode.recoveryRequired => l10n.backupRecoveryRequired,
    SettingsBackupErrorCode.cancelled => l10n.backupCancelled,
  };

  @override
  String toString() => 'SettingsBackupException(${code.name})';
}
