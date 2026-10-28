import 'dart:convert';

import 'package:fall_dashboard/fall_dashboard.dart';
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

  group('countFalls', () {
    final now = DateTime.utc(2026, 10, 21, 12);

    test('dedupes by observation_id, counts simulated and id-less rows per time', () {
      final counts = InfluxFallRepository.countFalls([
        // the same fall written twice (mobile app + dashboard)
        (patientId: 'p1', observationId: 'obs-A', time: now.subtract(const Duration(hours: 1))),
        (patientId: 'p1', observationId: 'obs-A', time: now.subtract(const Duration(hours: 1))),
        (patientId: 'p1', observationId: 'simulated-fall', time: now.subtract(const Duration(hours: 2))),
        (patientId: 'p1', observationId: 'simulated-fall', time: now.subtract(const Duration(hours: 3))),
        (patientId: 'p1', observationId: null, time: now.subtract(const Duration(days: 3))),
        (patientId: 'p2', observationId: 'obs-B', time: now.subtract(const Duration(days: 5))),
      ], now);
      expect(counts['p1']!.last30Days, 4);
      expect(counts['p1']!.last24Hours, 3);
      expect(counts['p2']!.last30Days, 1);
      expect(counts['p2']!.last24Hours, 0);
      expect(counts.containsKey('p3'), isFalse);
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
      expect(counts['p1']!.last24Hours, 1);
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

  group('FallEventsWriter.toLineProtocol', () {
    FallEvent alertEvent(Map<String, Object?> extra) => FallEvent.fromMqtt(
          topic: 'fall/alert/p1',
          payload: jsonEncode({
            'patient_id': 'p1',
            'fall_detected': true,
            'patient_confirmed': 'no',
            'timestamp': '2026-10-21T08:00:00.123Z',
            ...extra,
          }),
        )!;

    test('same schema as the mobile app writes', () {
      final line = FallEventsWriter.toLineProtocol(alertEvent({
        'observation_id': 'obs-A',
        'confidence': 0.912345,
        'model_version': 'v3',
        'needs_help': null,
      }), deviceIdFallback: 'aa:bb');
      expect(
        line,
        'fall_events,device_id=aa:bb,patient_id=p1 '
        'fall_detected=true,patient_confirmed=0i,confidence=0.9123,'
        'observation_id="obs-A",model_version="v3" 1792569600123000000',
      );
    });

    test('escapes tag values and keeps needs_help when answered', () {
      final line = FallEventsWriter.toLineProtocol(alertEvent({
        'patient_id': 'ward 3,bed=1',
        'needs_help': false,
      }));
      expect(line, startsWith(r'fall_events,patient_id=ward\ 3\,bed\=1 '));
      expect(line, contains('needs_help=false'));
      expect(line, isNot(contains('device_id')));
    });
  });
}
