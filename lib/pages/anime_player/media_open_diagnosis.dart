part of '../anime_player_page.dart';

class _MediaOpenDiagnosis {
  final int? manifestStatus;
  final bool manifestLooksLikeHls;
  final String? manifestError;
  final String? firstSegmentUrl;
  final int? segmentStatus;
  final int? segmentBytes;
  final String? segmentError;

  const _MediaOpenDiagnosis({
    this.manifestStatus,
    this.manifestLooksLikeHls = false,
    this.manifestError,
    this.firstSegmentUrl,
    this.segmentStatus,
    this.segmentBytes,
    this.segmentError,
  });

  bool get networkLooksHealthy =>
      manifestStatus == 200 &&
      manifestLooksLikeHls &&
      segmentStatus == 200 &&
      (segmentBytes ?? 0) > 0;

  String toDebugString(AppLocalizations l10n) {
    final buffer = StringBuffer();
    if (manifestStatus != null) {
      buffer.writeln(l10n.animePlayerDiagnosisManifestStatus(manifestStatus!));
    }
    if (manifestLooksLikeHls) {
      buffer.writeln(l10n.animePlayerDiagnosisManifestHls);
    } else if (manifestStatus == 200) {
      buffer.writeln(l10n.animePlayerDiagnosisManifestNotHls);
    }
    if (manifestError != null && manifestError!.isNotEmpty) {
      buffer.writeln(l10n.animePlayerDiagnosisManifestError(manifestError!));
    }
    if (firstSegmentUrl != null && firstSegmentUrl!.isNotEmpty) {
      buffer.writeln(l10n.animePlayerDiagnosisFirstSegment(firstSegmentUrl!));
    }
    if (segmentStatus != null) {
      buffer.writeln(l10n.animePlayerDiagnosisSegmentStatus(segmentStatus!));
    }
    if (segmentBytes != null) {
      buffer.writeln(l10n.animePlayerDiagnosisSegmentBytes(segmentBytes!));
    }
    if (segmentError != null && segmentError!.isNotEmpty) {
      buffer.writeln(l10n.animePlayerDiagnosisSegmentError(segmentError!));
    }
    if (networkLooksHealthy) {
      buffer.writeln(l10n.animePlayerDiagnosisConclusionDecodeIssue);
    }
    return buffer.toString().trim();
  }
}
