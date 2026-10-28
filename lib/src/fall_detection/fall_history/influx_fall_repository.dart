import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../core/time_utils.dart';
import 'fall_record.dart';
import 'flux_csv.dart';

/// Thrown when InfluxDB answers with an error or cannot be reached.
class InfluxQueryException implements Exception {
  InfluxQueryException(this.message);
  final String message;
  @override
  String toString() => 'InfluxQueryException: $message';
}

/// Reads fall counts and fall history from the `fall_events` measurement.
///
/// Talks to the InfluxDB 2 HTTP API directly, so it runs on any platform.
/// Pure Dart (no Flutter import).
///
/// In this webapp it runs in the browser, like the existing biosignal
/// queries. The OpenShift InfluxDB allows cross-origin requests (checked
/// 2026-10-28, see docs/fall_integration_plan.md, phase 0).
class InfluxFallRepository {
  InfluxFallRepository(this.settings, {http.Client? httpClient, DateTime Function()? clock})
      : _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final InfluxSettings settings;
  final http.Client _http;
  final DateTime Function() _clock;

  /// Falls per patient within the last [window] (rolling, not calendar days).
  ///
  /// One count per fall: rows sharing an observation_id (for example written
  /// by both the mobile app and the fall dashboard) count once. Rows without
  /// an observation_id, or with the shared "simulated-fall" id, count per
  /// timestamp. Simulated falls count. Patients with no falls are absent.
  Future<Map<String, int>> fetchFallCounts({Duration window = const Duration(days: 7)}) async {
    final rows = await _query('''
from(bucket: "${_flux(settings.bucket)}")
  |> range(start: -${window.inHours}h)
  |> filter(fn: (r) => r["_measurement"] == "fall_events")
  |> filter(fn: (r) => r["_field"] == "fall_detected" or r["_field"] == "observation_id")
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r["fall_detected"] == true)
  |> keep(columns: ["_time", "patient_id", "observation_id"])
''');
    return countFalls(
      [
        for (final row in rows)
          if ((row['patient_id'] ?? '').isNotEmpty && parseUtcTimestamp(row['_time']) != null)
            (
              patientId: row['patient_id']!,
              observationId: row['observation_id'],
              time: parseUtcTimestamp(row['_time'])!,
            ),
      ],
      _clock(),
      window,
    );
  }

  /// The falls of [patientId] between [start] (inclusive) and [stop]
  /// (exclusive), newest first, one entry per fall, simulated falls included.
  /// Use [localDay] for the day picked in the calendar.
  Future<DayFalls> fetchFallsBetween({
    required String patientId,
    required DateTime start,
    required DateTime stop,
    int limit = 500,
  }) async {
    final rows = await _query('''
from(bucket: "${_flux(settings.bucket)}")
  |> range(start: ${start.toUtc().toIso8601String()}, stop: ${stop.toUtc().toIso8601String()})
  |> filter(fn: (r) => r["_measurement"] == "fall_events")
  |> filter(fn: (r) => r["patient_id"] == "${_flux(patientId)}")
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r["fall_detected"] == true)
  |> group(columns: ["patient_id"])
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: $limit)
''');
    return DayFalls(dedupe([for (final row in rows) _toRecord(row)]));
  }

  /// Local midnight of [day] and the next local midnight. Day lengths
  /// follow the clock change (23 or 25 hours), which `DateTime` handles.
  static ({DateTime start, DateTime stop}) localDay(DateTime day) {
    final local = day.toLocal();
    return (
      start: DateTime(local.year, local.month, local.day),
      stop: DateTime(local.year, local.month, local.day + 1),
    );
  }

  /// One record per fall, in input order: same rule as [countFalls].
  static List<FallRecord> dedupe(Iterable<FallRecord> records) {
    final seen = <String>{};
    return [
      for (final record in records)
        if (seen.add(_fallKey(record.observationId, record.detectionTime))) record,
    ];
  }

  /// Fall history, newest first.
  ///
  /// [hours] is the look-back window (the detail view uses 24). Simulated
  /// falls are excluded and each observation_id appears once, even when two
  /// writers stored it under different device_id tags.
  Future<List<FallRecord>> fetchFalls({
    String? patientId,
    bool onlyFalls = true,
    int limit = 200,
    int hours = 720,
  }) async {
    final patientFilter = patientId == null
        ? ''
        : '  |> filter(fn: (r) => r["patient_id"] == "${_flux(patientId)}")\n';
    final onlyFallsFilter =
        onlyFalls ? '  |> filter(fn: (r) => r["fall_detected"] == true)\n' : '';
    final rows = await _query('''
from(bucket: "${_flux(settings.bucket)}")
  |> range(start: -${hours}h)
  |> filter(fn: (r) => r["_measurement"] == "fall_events")
$patientFilter  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r["observation_id"] != "$simulatedObservationId")
$onlyFallsFilter  |> group(columns: ["patient_id"])
  |> unique(column: "observation_id")
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: $limit)
''');
    return [for (final row in rows) _toRecord(row)];
  }

  void close() => _http.close();

  /// Pure counting step of [fetchFallCounts], exposed for tests.
  static Map<String, int> countFalls(
    Iterable<({String patientId, String? observationId, DateTime time})> rows,
    DateTime now,
    Duration window,
  ) {
    final cutoff = now.toUtc().subtract(window);
    // patient_id -> dedup keys
    final falls = <String, Set<String>>{};
    for (final row in rows) {
      if (row.time.isBefore(cutoff)) continue;
      falls.putIfAbsent(row.patientId, () => {}).add(_fallKey(row.observationId, row.time));
    }
    return {for (final entry in falls.entries) entry.key: entry.value.length};
  }

  /// Rows with the same real observation_id are one fall; rows without one,
  /// or with the shared simulated id, are told apart by their timestamp.
  static String _fallKey(String? observationId, DateTime? time) =>
      observationId != null &&
              observationId.isNotEmpty &&
              observationId != simulatedObservationId
          ? observationId
          : 'time:${time?.toUtc().toIso8601String()}';

  Future<List<Map<String, String>>> _query(String flux) async {
    final uri = Uri.parse('${_trimSlash(settings.url)}/api/v2/query')
        .replace(queryParameters: {'org': settings.org});
    final http.Response response;
    try {
      response = await _http.post(
        uri,
        headers: {
          'Authorization': 'Token ${settings.token}',
          'Content-Type': 'application/json',
          'Accept': 'application/csv',
        },
        body: jsonEncode({
          'query': flux,
          'type': 'flux',
          'dialect': {'header': true, 'annotations': <String>[]},
        }),
      );
    } catch (error) {
      throw InfluxQueryException('InfluxDB unreachable at ${settings.url}: $error');
    }
    if (response.statusCode != 200) {
      throw InfluxQueryException('HTTP ${response.statusCode}: ${response.body}');
    }
    return parseFluxCsv(utf8.decode(response.bodyBytes));
  }

  static FallRecord _toRecord(Map<String, String> row) {
    String? text(String key) {
      final value = row[key];
      return value == null || value.isEmpty ? null : value;
    }

    bool? flag(String key) => switch (text(key)) {
          'true' => true,
          'false' => false,
          _ => null,
        };

    final confidence = text('confidence');
    final confirmed = text('patient_confirmed');
    return FallRecord(
      patientId: text('patient_id') ?? '',
      detectionTime: parseUtcTimestamp(row['_time']),
      fallDetected: flag('fall_detected') ?? true,
      patientConfirmed: confirmed == null ? null : int.tryParse(confirmed),
      needsHelp: flag('needs_help'),
      confidence: confidence == null ? null : double.tryParse(confidence),
      observationId: text('observation_id'),
      modelVersion: text('model_version'),
      deviceId: text('device_id'),
    );
  }

  /// Escapes a value for use inside a Flux string literal.
  static String _flux(String value) => value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String _trimSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
