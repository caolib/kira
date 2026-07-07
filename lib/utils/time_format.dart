import '../l10n/app_localizations.dart';

/// Relative time formatting helpers.
class TimeFormat {
  TimeFormat._();

  /// Parses a date string and returns relative time; returns input on failure.
  static String relativeOf(String dateStr, AppLocalizations l10n) {
    if (dateStr.isEmpty) return dateStr;
    final normalized = dateStr.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return dateStr;
    return relative(parsed, l10n);
  }

  /// Converts [time] to relative time; future time is treated as just now.
  static String relative(DateTime time, AppLocalizations l10n) {
    final local = time.isUtc ? time.toLocal() : time;
    final diff = DateTime.now().difference(local);
    if (diff.isNegative || diff.inSeconds < 60) return l10n.relativeTimeJustNow;
    if (diff.inMinutes < 60) {
      return l10n.relativeTimeMinutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) return l10n.relativeTimeHoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.relativeTimeDaysAgo(diff.inDays);
    if (diff.inDays < 365) {
      return l10n.relativeTimeMonthsAgo((diff.inDays / 30).floor());
    }
    return l10n.relativeTimeYearsAgo((diff.inDays / 365).floor());
  }

  /// Locale-agnostic fallback that mirrors [relative] with neutral English
  /// labels. Used only by places without a context (e.g. background jobs).
  static String relativeFallback(DateTime time) {
    final local = time.isUtc ? time.toLocal() : time;
    final diff = DateTime.now().difference(local);
    if (diff.isNegative || diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 30) return '${diff.inDays} d ago';
    if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()} mo ago';
    }
    return '${(diff.inDays / 365).floor()} y ago';
  }
}
