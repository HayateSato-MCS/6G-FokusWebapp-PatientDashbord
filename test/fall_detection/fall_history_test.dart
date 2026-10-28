import 'dart:convert';

import 'package:dca/src/fall_detection/fall_detection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const settings = InfluxSettings(
  url: 'http://influx.test:8086/',
  org: 'focus',
  bucket: 'sensors',
  token: 'secret',
);

void main() {
  group('parseFluxCsv', () {
    test('handles several tables, CRLF line ends and quoted values', () {
      const body = ',result,table,_time,patient_id,observation_id\r\n'
          ',_result,0,2026-10-21T07:48:16.267Z,p1,obs-A\r\n'
          ',_result,0,2026-10-21T08:00:00Z,"p,2","say ""hi"""\r\n'
          '\r\n'
          ',result,table,_time,patient_id\r\n'
          ',_result,1,2026-10-20T17:29:03Z,p3\r\n';
      final rows = parseFluxCsv(body);
      expect(rows, hasLength(3));
      expect(rows[0], {
        'result': '_result',
        'table': '0',
        '_time': '2026-10-21T07:48:16.267Z',
        'patient_id': 'p1',
        'observation_id': 'obs-A',
      });
      expect(rows[1]['patient_id'], 'p,2');
      expect(rows[1]['observation_id'], 'say "hi"');
      expect(rows[2]['patient_id'], 'p3');
      expect(rows[2].containsKey('observation_id'), isFalse);
    });

    test('empty body gives no rows', () {
      expect(parseFluxCsv(''), isEmpty);
      expect(parseFluxCsv('\r\n'), isEmpty);
    });
  });

  group('countFalls (7-day window)', () {
    final now = DateTime.utc(2026, 10, 21, 12);
    const week = Duration(days: 7);

    test('dedupes by observation_id, counts simulated and id-less rows per time', () {
      final counts = InfluxFallRepository.countFalls([
        // the same fall written twice (mobile app + dashboard)
        (patientId: 'p1', observationId: 'obs-A', time: now.subtract(const Duration(hours: 1))),
        (patientId: 'p1', observationId: 'obs-A', time: now.subtract(const Duration(hours: 1))),
        (patientId: 'p1', observationId: 'simulated-fall', time: now.subtract(const Duration(hours: 2))),
        (patientId: 'p1', observationId: 'simulated-fall', time: now.subtract(const Duration(hours: 3))),
        (patientId: 'p1', observationId: null, time: now.subtract(const Duration(days: 3))),
        (patientId: 'p2', observationId: 'obs-B', time: now.subtract(const Duration(days: 5))),
      ], now, week);
      expect(counts['p1'], 4);
      expect(counts['p2'], 1);
      expect(counts.containsKey('p3'), isFalse);
    });

    test('rolling 7 x 24 h: -167 h counts, -169 h does not', () {
      final counts = InfluxFallRepository.countFalls([
        (patientId: 'p1', observationId: 'in', time: now.subtract(const Duration(hours: 167))),
        (patientId: 'p1', observationId: 'out', time: now.subtract(const Duration(hours: 169))),
        (patientId: 'p2', observationId: 'old', time: now.subtract(const Duration(days: 8))),
      ], now, week);
      expect(counts['p1'], 1);
      expect(counts.containsKey('p2'), isFalse);
    });
  });

  group('localDay', () {
    test('runs from local midnight to the next local midnight', () {
      final day = InfluxFallRepository.localDay(DateTime(2026, 10, 28, 15, 30));
      expect(day.start, DateTime(2026, 10, 28));
      expect(day.stop, DateTime(2026, 10, 29));
    });

    test('clock-change day (2026-10-25, 25 h in Berlin) still ends at the next midnight', () {
      final day = InfluxFallRepository.localDay(DateTime(2026, 10, 25, 12));
      expect(day.start, DateTime(2026, 10, 25));
      expect(day.stop, DateTime(2026, 10, 26));
      expect((day.stop.hour, day.stop.minute), (0, 0));
    });
  });

  group('dedupe and DayFalls', () {
    FallRecord rec(String? obs, String time) =>
        FallRecord(patientId: 'p1', observationId: obs, detectionTime: DateTime.parse(time));

    test('one entry per fall; simulated falls count but are not listed', () {
      final falls = DayFalls(InfluxFallRepository.dedupe([
        rec('obs-A', '2026-10-28T10:00:00Z'),
        rec('obs-A', '2026-10-28T10:00:00Z'), // second writer
        rec('simulated-fall', '2026-10-28T09:00:00Z'),
        rec('simulated-fall', '2026-10-28T09:00:00Z'), // same simulated fall twice
        rec('simulated-fall', '2026-10-28T08:00:00Z'),
        rec(null, '2026-10-28T07:00:00Z'),
      ]));
      expect(falls.total, 4);
      expect(falls.simulated, 2);
      expect(falls.listed.map((f) => f.observationId), ['obs-A', null]);
    });
  });

  group('InfluxFallRepository over HTTP', () {
    test('fetchFallCounts sends a Flux query and counts the rows', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(
          ',result,table,_time,observation_id,patient_id\r\n'
          ',_result,0,2026-10-21T11:00:00Z,obs-A,p1\r\n'
          ',_result,1,2026-10-21T11:00:00Z,obs-A,p1\r\n',
          200,
        );
      });
      final repository = InfluxFallRepository(settings,
          httpClient: client, clock: () => DateTime.utc(2026, 10, 21, 12));

      final counts = await repository.fetchFallCounts();

      expect(sent.url.toString(), 'http://influx.test:8086/api/v2/query?org=focus');
      expect(sent.headers['Authorization'], 'Token secret');
      final query = (jsonDecode(sent.body) as Map)['query'] as String;
      expect(query, contains('from(bucket: "sensors")'));
      expect(query, contains('r["_measurement"] == "fall_events"'));
      expect(query, contains('range(start: -168h)'));
      expect(counts['p1'], 1);
    });

    test('fetchFallsBetween queries the absolute UTC range and keeps simulated falls', () async {
      late String query;
      final client = MockClient((request) async {
        query = (jsonDecode(request.body) as Map)['query'] as String;
        return http.Response(
          ',result,table,_time,fall_detected,needs_help,observation_id,patient_confirmed,patient_id\r\n'
          ',_result,0,2026-10-28T10:00:00Z,true,true,obs-1,1,202\r\n'
          ',_result,0,2026-10-28T09:00:00Z,true,,simulated-fall,0,202\r\n',
          200,
        );
      });
      final repository = InfluxFallRepository(settings, httpClient: client);
      final day = InfluxFallRepository.localDay(DateTime(2026, 10, 28));

      final falls = await repository.fetchFallsBetween(
          patientId: '202', start: day.start, stop: day.stop);

      expect(
        query,
        contains('range(start: ${day.start.toUtc().toIso8601String()}, '
            'stop: ${day.stop.toUtc().toIso8601String()})'),
      );
      expect(query, contains('r["patient_id"] == "202"'));
      expect(query, isNot(contains('simulated-fall')));
      expect(falls.total, 2);
      expect(falls.simulated, 1);
      expect(falls.listed.single.needsHelp, isTrue);
    });

    test('fetchFalls maps rows to records and escapes the patient filter', () async {
      late String query;
      final client = MockClient((request) async {
        query = (jsonDecode(request.body) as Map)['query'] as String;
        return http.Response(
          ',result,table,_time,confidence,device_id,fall_detected,model_version,'
          'needs_help,observation_id,patient_confirmed,patient_id\r\n'
          ',_result,0,2026-10-21T08:07:00.4488983Z,0.9701,6c:1d,true,v1,true,obs-1,1,p1\r\n'
          ',_result,0,2026-10-21T07:00:00Z,0.88,6c:1d,true,v1,,obs-2,-1,p1\r\n',
          200,
        );
      });
      final repository = InfluxFallRepository(settings, httpClient: client);

      final records = await repository.fetchFalls(patientId: 'p"1', hours: 24);

      expect(query, contains(r'r["patient_id"] == "p\"1"'));
      expect(query, contains('range(start: -24h)'));
      expect(query, contains('group(columns: ["patient_id"])'));
      expect(records, hasLength(2));
      expect(records[0].patientConfirmed, 1);
      expect(records[0].needsHelp, isTrue);
      expect(records[0].confidence, 0.9701);
      expect(records[0].detectionTime!.isUtc, isTrue);
      expect(records[1].needsHelp, isNull);
      expect(records[1].patientConfirmed, -1);

      final stats = PatientFallStats.from(records);
      expect((stats.total, stats.confirmed, stats.helpRequested), (2, 1, 1));
    });

    test('HTTP errors become InfluxQueryException', () async {
      final repository = InfluxFallRepository(settings,
          httpClient: MockClient((_) async => http.Response('{"code":"unauthorized"}', 401)));
      expect(repository.fetchFallCounts(), throwsA(isA<InfluxQueryException>()));
    });
  });
}
