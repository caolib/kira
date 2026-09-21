import '../../backup/backup_category.dart';
import '../../backup/backup_controller.dart';
import '../../backup/backup_error.dart';
import '../../backup/backup_schedule.dart';
import '../../backup/webdav_config.dart';
import '../../l10n/app_localizations.dart';

String backupCategoryLabel(BackupCategory category, AppLocalizations l10n) =>
    switch (category) {
      BackupCategory.settings => l10n.backupCategorySettings,
      BackupCategory.readingHistory => l10n.backupCategoryHistory,
      BackupCategory.readingStatistics => l10n.backupCategoryStatistics,
      BackupCategory.bookmarks => l10n.backupCategoryBookmarks,
      BackupCategory.account => l10n.backupCategoryAccount,
      BackupCategory.aiConnection => l10n.backupCategoryAiConnection,
    };

String backupIntervalUnitLabel(
  BackupIntervalUnit unit,
  AppLocalizations l10n,
) => switch (unit) {
  BackupIntervalUnit.minutes => l10n.backupScheduleMinutes,
  BackupIntervalUnit.hours => l10n.backupScheduleHours,
  BackupIntervalUnit.days => l10n.backupScheduleDays,
};

String backupOperationLabel(BackupOperation operation, AppLocalizations l10n) =>
    switch (operation) {
      BackupOperation.idle => '',
      BackupOperation.reading => l10n.backupReading,
      BackupOperation.compressing => l10n.backupCompressing,
      BackupOperation.encrypting => l10n.backupEncrypting,
      BackupOperation.decoding => l10n.backupDecoding,
      BackupOperation.testing => l10n.backupTesting,
      BackupOperation.listing => l10n.backupListing,
      BackupOperation.uploading => l10n.backupUploading,
      BackupOperation.downloading => l10n.backupDownloading,
      BackupOperation.restoring => l10n.backupRestoring,
      BackupOperation.deleting => l10n.backupDeleting,
    };

String backupErrorMessage(Object error, AppLocalizations l10n) {
  if (error is SettingsBackupException) return error.localizedMessage(l10n);
  if (error is! WebDavException) return l10n.backupOperationFailed;
  return switch (error.code) {
    WebDavErrorCode.invalidConfiguration => l10n.backupWebDavInvalidConfig,
    WebDavErrorCode.httpNotAllowed => l10n.backupHttpWarning,
    WebDavErrorCode.authentication => l10n.backupWebDavAuthentication,
    WebDavErrorCode.forbidden => l10n.backupWebDavForbidden,
    WebDavErrorCode.notFound => l10n.backupWebDavNotFound,
    WebDavErrorCode.moveUnsupported => l10n.backupWebDavMoveUnsupported,
    WebDavErrorCode.methodUnsupported => l10n.backupWebDavMethodUnsupported,
    WebDavErrorCode.redirectRefused => l10n.backupWebDavRedirectRefused,
    WebDavErrorCode.unsafePath => l10n.backupWebDavUnsafePath,
    WebDavErrorCode.invalidResponse => l10n.backupWebDavInvalidResponse,
    WebDavErrorCode.connection => l10n.backupWebDavConnection,
    WebDavErrorCode.timeout => l10n.backupWebDavTimeout,
    WebDavErrorCode.conflict => l10n.backupWebDavConflict,
  };
}

String formatBackupBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}

String formatBackupTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
