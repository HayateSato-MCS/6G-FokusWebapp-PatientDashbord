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
/// Running it in a browser means shipping the InfluxDB token to every
/// browser, and InfluxDB may block cross-origin requests. In a web app,
/// call it from your backend instead; see handover/03_fall_history.md, section 3.
class InfluxFallRepository {
  InfluxFallRepository(this.settings, {http.Client? httpClient, DateTime Function()? clock})
      : _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final InfluxSettings settings;
  final http.Client _http;
  final DateTime Function() _clock;

  static const simulatedObservationId = 'simulated-fall';

  /// Fall counts per patient for the last 30 days and the last 24 hours.
  ///
  /// One count per fall: rows sharing an observation_id (for example written
  /// by both the mobile app and the fall dashboard) count once. Rows without
  /// an observation_id, or with the shared "simulated-fall" id, count per
  /// timestamp. Patients with no falls are absent from the map.
  Future<Map<String, FallCounts>> fetchFallCounts() async {
    final rows = await _query('''
from(bucket: "${_flux(settings.bucket)}")
  |> range(start: -720h)
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
    );
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
  static Map<String, FallCounts> countFalls(
    Iterable<({String patientId, String? observationId, DateTime time})> rows,
    DateTime now,
  ) {
    // patient_id -> {dedup key: latest time}
    final falls = <String, Map<String, DateTime>>{};
    for (final row in rows) {
      final observation = row.observationId;
      final key = observation != null &&
              observation.isNotEmpty &&
              observation != simulatedObservationId
          ? observation
          : 'time:${row.time.toIso8601String()}';
      final seen = falls.putIfAbsent(row.patientId, () => {});
      final previous = seen[key];
      if (previous == null || row.time.isAfter(previous)) seen[key] = row.time;
    }
    final cutoff = now.toUtc().subtract(const Duration(hours: 24));
    return {
      for (final entry in falls.entries)
        entry.key: FallCounts(
          last30Days: entry.value.length,
          last24Hours: entry.value.values.where((t) => !t.isBefore(cutoff)).length,
        ),
    };
  }

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
