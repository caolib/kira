/// Safe JSON extraction helpers that never throw on type mismatches.
///
/// Use these instead of raw `as List` / `as int` / `as Map` casts when
/// extracting values from decoded JSON — a malformed API response should
/// produce an empty result, not a runtime crash.
library;

/// Extract a `List` from a JSON map, returning an empty list on failure.
List<dynamic> jsonList(Map<String, dynamic>? json, String key) {
  if (json == null) return [];
  final value = json[key];
  return value is List ? value : [];
}

/// Extract an `int` from a JSON map, returning [fallback] on failure.
int jsonInt(Map<String, dynamic>? json, String key, {int fallback = 0}) {
  if (json == null) return fallback;
  final value = json[key];
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

/// Extract a `String` from a JSON map, returning [fallback] on failure.
String jsonString(
  Map<String, dynamic>? json,
  String key, {
  String fallback = '',
}) {
  if (json == null) return fallback;
  final value = json[key];
  return value?.toString() ?? fallback;
}

/// Extract a `double` from a JSON map, returning [fallback] on failure.
double jsonDouble(
  Map<String, dynamic>? json,
  String key, {
  double fallback = 0.0,
}) {
  if (json == null) return fallback;
  final value = json[key];
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

/// Extract a `bool` from a JSON map, returning [fallback] on failure.
bool jsonBool(Map<String, dynamic>? json, String key, {bool fallback = false}) {
  if (json == null) return fallback;
  final value = json[key];
  if (value is bool) return value;
  return fallback;
}

/// Extract a `Map<String, dynamic>` from a JSON map, returning null on failure.
Map<String, dynamic>? jsonMap(Map<String, dynamic>? json, String key) {
  if (json == null) return null;
  final value = json[key];
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

/// Extension to convert an empty string to `null`.
extension NullIfEmptyString on String {
  String? nullIfEmpty() => isEmpty ? null : this;
}
