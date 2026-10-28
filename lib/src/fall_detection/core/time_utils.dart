/// Parses an ISO 8601 timestamp; a value without a timezone is taken as UTC
/// (the mobile app sends UTC). Epoch numbers (seconds or milliseconds, as a
/// number or as text) are accepted too. Returns null for missing or
/// malformed input.
DateTime? parseUtcTimestamp(Object? raw) {
  if (raw is num) return _fromEpoch(raw);
  if (raw is! String || raw.isEmpty) return null;
  final asNumber = num.tryParse(raw);
  if (asNumber != null) return _fromEpoch(asNumber);
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  return DateTime.tryParse(hasZone ? raw : '${raw}Z')?.toUtc();
}

/// Epoch seconds or milliseconds; values from 1e11 on are milliseconds
/// (1e11 seconds would be the year 5138).
DateTime _fromEpoch(num value) => DateTime.fromMillisecondsSinceEpoch(
      value.abs() >= 1e11 ? value.round() : (value * 1000).round(),
      isUtc: true,
    );

/// UTC ISO 8601 with millisecond precision, e.g. `2026-10-21T08:00:00.123Z`.
String isoMillisUtc(DateTime time) {
  final iso = time.toUtc().toIso8601String();
  // toIso8601String may add microseconds; keep yyyy-MM-ddTHH:mm:ss.mmm
  return '${iso.substring(0, 23)}Z';
}

/// Local time as `yyyy-MM-dd HH:mm:ss` for tables.
String formatLocal(DateTime? time) {
  if (time == null) return '-';
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
