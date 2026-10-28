import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dca/src/data_handlers/influx_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:influxdb_client/api.dart';

//import '../../../../authentication_repository/lib/authentication_repository.dart';
import '../data-distribution/data_source_type.dart';
import '../data-distribution/measurement.dart';
import '../data-distribution/publish_subscribe_manager.dart';
import '../environment.dart';

class InfluxDBHandler {
  static InfluxDBHandler? _instance;
  InfluxDBClient? client;

  InfluxDBHandler() {
    debugPrint(
        "influx DB config is: Host {${MCSDashboardEnvironment.influxDBHost}}, Token: {${MCSDashboardEnvironment.hasInfluxDBToken ? 'set' : 'MISSING'}}, Org: {${MCSDashboardEnvironment.influxDBOrg}}, Bucket: {${MCSDashboardEnvironment.influxDBBucket}}");
    if (!MCSDashboardEnvironment.hasInfluxDBToken) {
      debugPrint(
          "INFLUXDB_TOKEN is not set. Build/run with --dart-define=INFLUXDB_TOKEN=... (see README); InfluxDB queries will fail with 401.");
    }
    initBucketClient();
  }

  factory InfluxDBHandler.getInstance() {
    _instance ??= InfluxDBHandler();
    return _instance!;
  }

  initBucketClient() {
    client ??= InfluxDBClient(
        url: MCSDashboardEnvironment.influxDBHost,
        token: MCSDashboardEnvironment.influxDBAPIToken,
        org: MCSDashboardEnvironment.influxDBOrg,
        bucket: MCSDashboardEnvironment.influxDBBucket,
        followRedirects: false,
        debug: false);
  }

  Future<List<Measurement>> getLastData(AggregatedDataParams params) async {
    // if (params.tags.firstWhereOrNull((t) => t.value == 'soc') == null) return [];
    var result = await compute(_getLastData, params);
    // var result = await (()async{return [] as List<Measurement>;})();
    if (result.isNotEmpty) {
      result = [result.reduce((a, b) => a.time >= b.time ? a : b)];
      if (params.publish) {
        result.forEach((m) {
          SubscriptionManager.publish(SourceType.INFLUX_DB, m.dataType, m);
        });
      }
    }

    // if (params.field == 'hr'|| params.field == 'spo2') debugPrint('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++getLastData result ${params.field} ${result.map((e) => '${e.time}||${e.values}')}');

    return result;
  }

  Future<List<Measurement>> _getLastData(AggregatedDataParams params) async {
    Duration? range = params.range;
    DateTime? start = params.start;
    DateTime? stop = params.stop;
    List<Aggregation> aggregations = params.aggregations;
    List<String>? fields = params.fields;
    List<Tag>? tags = params.tags;
    bool publish = params.publish;
    bool startOfDay = params.startOfDay;

    initBucketClient();
    final now = start ?? DateTime.now();
    final startOfDays = DateTime(now.year, now.month, now.day);
    var field = params.field;
    tags.add(Tag(key: '_field', value: 'batch_id', type: OperationType.notEqual));
    // tags.add(Tag(
    //     key: '_field',
    //     value: 'measurement_time',
    //     type: OperationType.notEqual));
    tags.add(Tag(key: '_field', value: 'transmission_start', type: OperationType.notEqual));

    var tmpStop = stop ?? DateTime.now();
    var tmpStart = startOfDay
        ? startOfDays
        : start != null
            ? start
            : stop != null
                ? stop.subtract(range)
                : DateTime.now().subtract(range);

    // tmpStart = DateTime.fromMillisecondsSinceEpoch(max(startOfDays.millisecondsSinceEpoch, tmpStart.millisecondsSinceEpoch));
    String formatStop = "${tmpStop.toIso8601String().split('.')[0]}${_getTimezoneOffset(tmpStop)}";
    String formatStart =
        "${tmpStart.toIso8601String().split('.')[0]}${_getTimezoneOffset(tmpStart)}";

    // STEP 1: Fetch latest _time per user+macAddress
    final lastTimeQuery = '''
from(bucket: "${client!.bucket}")
  |> range(start: $formatStart, stop: $formatStop)
  ${tags.isNotEmpty ? "|> filter(fn: (r) => ${tags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ''}
  ${fields != null && fields.isNotEmpty ? "|> filter(fn: (r) => ${fields.map((field) => 'r[\"measurement\"] == \"$field\"').join(' or ')})" : ''}
    |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r.measurement_time >= ${tmpStart.millisecondsSinceEpoch}.0 and r.measurement_time <= ${tmpStop.millisecondsSinceEpoch}.0)
  |> map(fn: (r) => ({
      r with
      _time: time(v: int(v: float(v: r.measurement_time) * 1000000.0))
  }))
  |> rename(columns: {${field}: "_value"})
  |> sort(columns: ["_time"], desc: true)
  |> group(columns: ["user", "macAddress"])
  |> first()
  |> keep(columns: ["_time", "user", "macAddress", "measurement", "_value"])
''';
    // if (field == 'hr') debugPrint('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++last Time query $field ${lastTimeQuery} $aggregations');

    final lastTimeResponse = await http.post(
      Uri.parse('${client!.url}/api/v2/query?org=${client!.org}'),
      headers: {
        'Authorization': 'Token ${client!.token}',
        'Content-Type': 'application/vnd.flux',
      },
      body: lastTimeQuery,
    );
    // if (field == 'hr') debugPrint('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++last Time query ${lastTimeResponse.statusCode} ${lastTimeResponse.body}');

    final lastTimeMap = <String, String>{};

    if (lastTimeResponse.statusCode == 200) {
      final lines = LineSplitter.split(lastTimeResponse.body).toList();
      // if (field == 'hr')debugPrint('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++lastTimeResponse lines ${lines}');
      if (lines.length > 1) {
        final headers = lines[0].split(',');
        final timeIndex = headers.indexOf('_time');
        final userIndex = headers.indexOf('user');
        final macIndex = headers.indexOf('macAddress');
        // final fieldIndex = headers.indexOf('measurement');

        if (timeIndex == -1 || userIndex == -1 || macIndex == -1) {
          throw Exception('Missing required headers: $headers');
        }

        final maxIndex = [timeIndex, userIndex, macIndex].reduce((a, b) => a > b ? a : b);

        for (var i = 1; i < lines.length; i++) {
          final row = lines[i].split(',');
          // if (row.length >= maxIndex) {
          //
          //   debugPrint('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++lastTimeResponse row[fieldIndex] ${row[fieldIndex]} ,,,,,,,, $fields');
          // }
          if (row.length <= maxIndex) continue;
          final user = row[userIndex];
          final mac = row[macIndex];
          final time = row[timeIndex];
          // final measurement = row[measureIndex];
          lastTimeMap['$user|$mac'] = time;
        }
      }
    } else {
      throw Exception('Failed to get last_time data: ${lastTimeResponse.body}');
    }
    // debugPrint('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++lastTimeResponse lastTimeMap ${lastTimeMap}');

    // STEP 2: Build and run queries per user+macAddress
    List<Measurement> results = [];

    for (final entry in lastTimeMap.entries) {
      final keyParts = entry.key.split('|');
      final user = keyParts[0];
      final mac = keyParts[1];
      // final measurement = keyParts[2];
      final lastTime = entry.value;

      // Extend tags with specific user/mac filter
      final scopedTags = List<Tag>.from(tags);
      scopedTags.add(Tag(key: 'user', value: user, type: OperationType.equal));
      scopedTags.add(Tag(key: 'macAddress', value: mac, type: OperationType.equal));
      // scopedTags.add(Tag(key: 'measurement', value: measurement, type: OperationType.equal));

      var queryString = '';
      scopedTags.add(Tag(key: '_field', value: 'measurement_time', type: OperationType.notEqual));
      for (var aggregation in aggregations) {
        final tableName = '${aggregation.type.name}_agg';
        queryString += '''
$tableName = from(bucket: "${client!.bucket}")
  |> range(start: $formatStart, stop: $formatStop)
  ${scopedTags.isNotEmpty ? "|> filter(fn: (r) => ${scopedTags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ''}
  ${fields != null && fields.isNotEmpty ? "|> filter(fn: (r) => ${fields.map((field) => 'r[\"measurement\"] == \"$field\"').join(' or ')})" : ''}
  |> aggregateWindow(every: ${aggregation.interval.inSeconds}s, fn: ${aggregation.type.name}, createEmpty: false)
''';
      }
      // debugPrint(
      //     '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++lastTimeResponse queryString ${queryString}');

      bool multi = aggregations.length > 1;
      if (multi) {
        for (var i = 1; i < aggregations.length; i++) {
          var left = i == 1 ? '${aggregations[0].type.name}_agg' : 'join_${i - 1}';
          var right = '${aggregations[i].type.name}_agg';
          var join = i == aggregations.length - 1 ? 'final_join' : 'join_$i';

          queryString += '''
$join = join(tables: {$left: $left, $right: $right}, on: ["_time"])
''';
        }
      }

      final finalTable = multi ? 'final_join' : '${aggregations.first.type.name}_agg';
      var columns = ['_field', 'measurement', 'macAddress', 'user'];

      queryString += '''
$finalTable
|> map(fn: (r) => ({
  _time: r._time,
  last_time: time(v: "$lastTime"),
  ${aggregations.map((e) => '${e.type.name}: r._value${multi ? '_${e.type.name}_agg' : ''}').join(', ')},
  ${columns.map((c) => '$c: r.${c}${multi ? '_${aggregations[0].type.name}_agg' : ''}').join(', ')}
}))
|> yield(name: "result")
''';

      final response = await http.post(
        Uri.parse('${client!.url}/api/v2/query?org=${client!.org}'),
        headers: {
          'Authorization': 'Token ${client!.token}',
          'Content-Type': 'application/vnd.flux',
        },
        body: queryString,
      );

      if (response.statusCode == 200) {
        final lines = LineSplitter.split(response.body).toList();
        if (lines.isEmpty) continue;

        final header = lines[0].split(',');
        for (var i = 1; i < lines.length; i++) {
          if (lines[i].isEmpty) continue;

          final record = _parseInfluxRecord(lines[i], header);
          final field = record['_field'];
          if (exclude.contains(field)) continue;

          DataType type = getDataTypeFromValue(record['measurement'] ?? record['_measurement']);
          if (type == DataType.STEPS_BOSCH) type = DataType.STEPS;

          var measurement = Measurement(type, record['user'] ?? '');
          DateTime dateTime =
              DateTime.tryParse(record['_time'] ?? record['last_time']) ?? DateTime.now();
          // DateTime? lastTimeParsed = record.containsKey('last_time')
          //     ? DateTime.tryParse(record['last_time'])
          //     : null;
          // if (field == 'hr' || field == 'spo2') debugPrint(
          //     '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++lastTimeResponse measurement time $type,, $dateTime,, ${record['macAddress']} \n\n $record');

          measurement.time = dateTime.millisecondsSinceEpoch;
          // if (lastTimeParsed != null) {
          //   measurement.lastTime = lastTimeParsed.millisecondsSinceEpoch;
          // }

          measurement.values =
              aggregations.map((e) => Value(e.type.name, '', record[e.type.name], true)).toList();

          // if (field == 'hr') debugPrint(
          //     '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++lastTimeResponse measurement ${measurement.values}');
          results.add(measurement);
        }
      } else {
        debugPrint('Query failed for $user / $mac: ${response.body}');
      }
    }

    return results;
  }

  Future<List<Measurement>> getAggregatedData(AggregatedDataParams params) async {
    // if (params.tags.firstWhereOrNull((t) => t.value == 'soc') == null) return [];
    var result = await compute(_getAggregatedData, params);
    // var result = await (()async{return [] as List<Measurement>;})();
    if (params.publish) {
      result.sorted((a, b) => a.time - b.time).forEach((m) {
        SubscriptionManager.publish(SourceType.INFLUX_DB, m.dataType, m);
      });
    }
    return result;
  }

  Future<List<Measurement>> _getAggregatedData(AggregatedDataParams params) async {
    Duration? range = params.range;
    DateTime? start = params.start;
    DateTime? stop = params.stop;
    List<Aggregation> aggregations = params.aggregations;
    List<String>? fields = params.fields;
    List<Tag>? tags = params.tags;
    bool publish = params.publish;
    bool startOfDay = params.startOfDay;
    initBucketClient();
    final now = start ?? DateTime.now();
    final startOfDays = DateTime(now.year, now.month, now.day);
    String field = params.field;
    debugPrint(
        ' ******************************************* InfluxDB Query tags: $field ,,,,,, ${tags}');
    tags.add(Tag(key: '_field', value: 'batch_id', type: OperationType.notEqual));
    // tags.add(Tag(
    //     key: '_field',
    //     value: 'measurement_time',
    //     type: OperationType.notEqual));
    tags.add(Tag(key: '_field', value: 'transmission_start', type: OperationType.notEqual));
    var tmpStop = stop ?? DateTime.now();
    var tmpStart = startOfDay
        ? startOfDays
        : start != null
            ? start
            : stop != null
                ? stop.subtract(range)
                : DateTime.now().subtract(range);

    String formatStop = "${tmpStop.toIso8601String().split('.')[0]}${_getTimezoneOffset(tmpStop)}";
    String formatStart =
        "${tmpStart.toIso8601String().split('.')[0]}${_getTimezoneOffset(tmpStart)}";

    // Debug the query string
    var queryString = '';
    for (var aggregation in aggregations) {
      queryString += '''
  ${aggregation.type.name} = from(bucket: "${client!.bucket}")
  |> range(start: $formatStart, stop: $formatStop)
  ${tags.isNotEmpty ? "|> filter(fn: (r) => ${tags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ''}
  ${fields != null && fields.isNotEmpty ? "|> filter(fn: (r) => ${fields.map((field) => 'r[\"measurement\"] == \"$field\"').join(' or ')})" : ''}
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r.measurement_time >= ${tmpStart.millisecondsSinceEpoch}.0 and r.measurement_time <= ${tmpStop.millisecondsSinceEpoch}.0)
  |> map(fn: (r) => ({
      r with
      _time: time(v: int(v: float(v: r.measurement_time) * 1000000.0))
  }))
  |> rename(columns: {${field}: "_value"})
  // |> aggregateWindow(every: 1s, fn: last, createEmpty: false)
  |> aggregateWindow(every: ${aggregation.interval.inSeconds}s, fn: ${aggregation.type.name}, createEmpty: false)
  ''';
    }

// Generate pairwise joins dynamically
    bool multi = aggregations.length > 1;
    if (multi) {
      var joinChain = '';
      for (var i = 1; i < aggregations.length; i++) {
        var leftTable = i == 1 ? aggregations[0].type.name : 'join_${i - 1}';
        var rightTable = aggregations[i].type.name;
        var joinName = i == aggregations.length - 1 ? 'final_join' : 'join_$i';

        joinChain += '''
    $joinName = join(tables: {$leftTable: $leftTable, $rightTable: $rightTable}, on: ["_time"])
    ''';
      }
      queryString += joinChain;
    }

// Define columns to retain
    var columns = ['_field', 'measurement', 'macAddress', 'user'];
    bool multipleAggregations = aggregations.length > 1;

// Add final map transformation
    queryString += '''
  |> map(fn: (r) => ({_time: r._time, ${aggregations.asMap().entries.map((e) => '${e.value.type.name}: r._value${e.key == aggregations.length - 1 || !multi ? '' : '_${e.value.type.name}'}').join(', ')}, ${columns.map((c) => '$c: r.${c}${multi ? '_${aggregations[0].type.name}' : ''}').join(', ')}}))
  |> yield(name: "${multi ? 'result' : aggregations.first.type.name}")
''';

    debugPrint('InfluxDB Query: $queryString');

    // Send the query via HTTP POST
    final response = await http.post(
      Uri.parse('${client!.url}/api/v2/query?org=${client!.org}'),
      headers: {
        'Authorization': 'Token ${client!.token}',
        'Content-Type': 'application/vnd.flux',
      },
      body: queryString,
    );
    debugPrint('InfluxDB Query result: ${response.statusCode} ,,,,,, ${response.body}');
    List<Measurement> results = [];
    if (response.statusCode == 200) {
      // Parse the response (InfluxDB responses are usually in CSV-like format)
      final responseBody = response.body;
      final lines = LineSplitter.split(responseBody).toList();
      final resultData = [];
      List<String> header = lines[0].split(',');
      debugPrint('InfluxDB Query lines: ${header}');
      // Skip header line and parse data
      for (var i = 1; i < lines.length; i++) {
        if (lines[i].isEmpty) continue;
        debugPrint('1 Record: ${lines[i]}');
        final record = _parseInfluxRecord(lines[i], header);
        final field = record['_field'];

        if (exclude.contains(field)) continue;
        // debugPrint(
        //     '1 ++++++++++++++++++++++++++++++++++++++++++++++++++ Record : ${field}');
        // debugPrint('2 Record: $record');
        DataType type = getDataTypeFromValue(record['measurement'] ?? record['_measurement']);
        if (type == DataType.STEPS_BOSCH) {
          type = DataType.STEPS;
        }
        if (record['measurement'] == 'steps')
          debugPrint(
              '1 ++++++++++++++++++++++++++++++++++++++++++++++++++ STEPS_BOSCH : ${record['macAddress']} : ${record['_time']} :: ${record['max']}');

        var measurement = Measurement(type, record['user'] ?? '');
        DateTime dateTime = DateTime.tryParse(record['_time']) ?? DateTime.now();
        measurement.time = dateTime.millisecondsSinceEpoch;
        measurement.values =
            aggregations.map((e) => Value(e.type.name, '', record[e.type.name], true));

        results.add(measurement);
        // if (publish) {
        //   SubscriptionManager.publish(SourceType.INFLUX_DB, type, measurement);
        // }
      }
    } else {
      throw Exception('Failed to query InfluxDB: ${response.body}');
    }
    // debugPrint('--------------------------------------- fetched Records: ${results.length}, ${aggregations.map((e) => e.type.name)}');
    return results;
  }

  Map<String, dynamic> _parseInfluxRecord(String line, List<String> header) {
    final values = line.split(',');
    // Parse fields based on the known schema of the response
    Map<String, dynamic> res = {};
    for (int i = 0; i < header.length; i++) {
      res[header[i]] = values[i];
    }
    return res;
  }

  Future<List<String>> fetchUniqueUsers() async {
    // Flux query to get distinct users
    initBucketClient();
    final String fluxQuery = '''
      from(bucket: "${client!.bucket}")
        |> range(start: -100d)
        |> filter(fn: (r) => r["_measurement"] == "SIX_G_PATH" and r["measurement"] == "skin_contact")
        // |> keep(columns: ["user"])
        // |> unique(column: "user")
        |> group(columns: ["user"])
        |> distinct(column: "user")  // Ensures unique users efficiently
        |> keep(columns: ["user"]) 
        
    ''';
    // debugPrint(
    //     '--------------------------------- fetchUniqueUsers  fluxQuery ------------------------------- $fluxQuery');

    final response = await http.post(
      Uri.parse('${client!.url!}/api/v2/query?org=${client!.org}'),
      headers: {
        'Authorization': 'Token ${client!.token!}',
        'Content-Type': 'application/vnd.flux',
        // 'Accept-Type': 'application/json'
      },
      body: fluxQuery,
    );
    List<String> userList = [];
    // debugPrint(
    //     '--------------------------------- InfluxDBHandler fetchUniqueUsers  ------------------------------- ${response.body}');

    if (response.statusCode == 200) {
      final data = response.body;

      // Parse the CSV-like response from InfluxDB
      final lines = LineSplitter.split(data).toList();

      // Skip headers and parse the data rows
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i];
        final columns = line.split(',');
        if (columns.isNotEmpty && columns.last.isNotEmpty) {
          userList.add(columns.last); // Assuming "user" is the last column
        }
      }
    } else {
      debugPrint('Failed to fetch unique users: ${response.body}');
    }
    return userList;
  }

  Future<List<Measurement>> fetchData(FetchDataParams params) async {
    var result = await compute(_fetchData, params);
    // var result = await (()async{return [] as List<Measurement>;})();
    if (params.publish) {
      result.forEach((m) {
        SubscriptionManager.publish(SourceType.INFLUX_DB, m.dataType, m);
      });
    }
    return result;
  }

  Future<List<Measurement>> _fetchData(FetchDataParams params) async {
    Duration? range = params.range;
    DateTime? start = params.start;
    DateTime? stop = params.stop;
    String aggregationMethod = params.aggregationMethod;
    Duration interval = params.interval;
    List<Tag> tags = params.tags;
    bool publish = params.publish ?? false;
    // Determine the range start and stop
    var field = params.field;
    tags.add(Tag(key: '_field', value: 'batch_id', type: OperationType.notEqual));
    // tags.add(Tag(
    //     key: '_field',
    //     value: 'measurement_time',
    //     type: OperationType.notEqual));
    tags.add(Tag(key: '_field', value: 'transmission_start', type: OperationType.notEqual));
    final DateTime rangeStop = stop ?? DateTime.now();
    final DateTime rangeStart = start ?? rangeStop.subtract(range ?? const Duration(days: 1));

    String startOfDayIso =
        "${rangeStart.toIso8601String().split('.')[0]}${_getTimezoneOffset(rangeStart)}";
    String endOfDayIso =
        "${rangeStop.toIso8601String().split('.')[0]}${_getTimezoneOffset(rangeStop)}";

    initBucketClient();
    // Build the Flux query
    String fluxQuery = '''
from(bucket: "${client!.bucket}")
  |> range(start: $startOfDayIso, stop: $endOfDayIso)
  ${tags != null && tags.isNotEmpty ? "|> filter(fn: (r) => ${tags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ""}
    |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r.measurement_time >= ${rangeStart.millisecondsSinceEpoch}.0 and r.measurement_time <= ${rangeStop.millisecondsSinceEpoch}.0)
  |> map(fn: (r) => ({
      r with
      _time: time(v: int(v: float(v: r.measurement_time) * 1000000.0))
  }))
  |> rename(columns: {${field}: "_value"})
  |> aggregateWindow(every: 1s, fn: last, createEmpty: false)  // Downsample to 1s intervals
  |> aggregateWindow(every: ${interval.inSeconds}s, fn: $aggregationMethod, createEmpty: false)
  |> yield(name: "${aggregationMethod}")
''';

    // Debugging: Print the generated query
    // debugPrint("Generated Flux Query: $fluxQuery");

    // Send the HTTP request
    final response = await http.post(
      Uri.parse('${client!.url}/api/v2/query?org=${client!.org}'),
      headers: {
        'Authorization': 'Token ${client!.token}',
        'Content-Type': 'application/vnd.flux',
      },
      body: fluxQuery,
    );
    List<Measurement> results = [];
    if (response.statusCode == 200) {
      // Parse the response
      final lines = LineSplitter.split(response.body).toList();

      // Extract data from CSV-like response
      if (lines.isEmpty) {
        return [];
      }

      // Extract headers and data rows
      final headers = lines.first.split(',');
      final dataRows = lines.skip(1);

      // // Map rows into structured data
      // return dataRows.map((row) {
      //   final values = row.split(',');
      //   return Map<String, String>.fromIterables(headers, values);
      // }).toList();
      for (var i = 1; i < lines.length; i++) {
        if (lines[i].isEmpty) continue;
        // debugPrint('1 Record: ${lines[i]}');
        final record = _parseInfluxRecord(lines[i], headers);
        // debugPrint('2 Record: $record');
        DataType type = getDataTypeFromValue(record['measurement'] ?? record['_measurement']);
        var measurement = Measurement(type, record['macAddress'] ?? '');
        DateTime dateTime = DateTime.parse(record['_time']);
        measurement.time = dateTime.millisecondsSinceEpoch;
        measurement.values = [Value(aggregationMethod, '', num.parse(record['_value']), true)];

        results.add(measurement);
      }
    } else {
      throw Exception('Failed to fetch data: ${response.body}');
    }
    return results;
  }

  Future<List<Measurement>> fetchHourlyStepsData(String user, DateTime date) async {
    // debugPrint('1 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData $user');
    // Get the start of the day
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59);
    String startOfDayIso =
        "${startOfDay.toIso8601String().split('.')[0]}${_getTimezoneOffset(startOfDay)}";
    String endOfDayIso =
        "${endOfDay.toIso8601String().split('.')[0]}${_getTimezoneOffset(endOfDay)}";

    initBucketClient();
    List<Tag> tags = [];
    tags.add(Tag(key: '_field', value: 'batch_id', type: OperationType.notEqual));
    // tags.add(Tag(
    //     key: '_field',
    //     value: 'measurement_time',
    //     type: OperationType.notEqual));
    tags.add(Tag(key: '_field', value: 'transmission_start', type: OperationType.notEqual));
    // tags.add(Tag(key: 'macAddress', value: '6C:1D:EB:04:A9:E6', type: OperationType.notEqual));
    // debugPrint('2 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData ${client?.url}');
    // Flux query to aggregate steps hourly
    final fluxQuery = '''
//   firstSteps = from(bucket: "${client!.bucket}")
//   |> range(start: $startOfDayIso, stop: $endOfDayIso)
//   |> filter(fn: (r) => r["measurement"] == "steps" and r["user"] == "$user")
//   ${tags.isNotEmpty ? "|> filter(fn: (r) => ${tags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ''}
//   |> aggregateWindow(every: 1h, fn: first, createEmpty: false)
//   |> rename(columns: {_value: "first_value"}) // Rename to avoid conflicts
//   |> keep(columns: ["_time", "first_value", "user", "macAddress", "_field","measurement"]) // Keep relevant columns
//
// lastSteps = from(bucket: "${client!.bucket}")
//   |> range(start: $startOfDayIso, stop: $endOfDayIso)
//   |> filter(fn: (r) => r["measurement"] == "steps" and r["user"] == "$user")
//   ${tags.isNotEmpty ? "|> filter(fn: (r) => ${tags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ''}
//   |> aggregateWindow(every: 1h, fn: last, createEmpty: false)
//   |> rename(columns: {_value: "last_value"}) // Rename to avoid conflicts
//   |> keep(columns: ["_time", "last_value", "user", "macAddress", "_field","measurement"]) // Keep relevant columns

firstSteps = from(bucket: "${client!.bucket}")
   |> range(start: $startOfDayIso, stop: $endOfDayIso)
   |> filter(fn: (r) => r["measurement"] == "steps" and r["user"] == "$user")
  ${tags.isNotEmpty ? "|> filter(fn: (r) => ${tags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ''}
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r.measurement_time >= ${startOfDay.millisecondsSinceEpoch}.0 and r.measurement_time <= ${endOfDay.millisecondsSinceEpoch}.0)
  |> map(fn: (r) => ({
      r with
      _time: time(v: int(v: float(v: r.measurement_time) * 1000000.0))
  }))
  |> rename(columns: {stepsbosch: "_value"})
  |> keep(columns: ["_time", "_value", "user", "macAddress", "measurement"])
|> aggregateWindow(every: 1h, fn: first, createEmpty: false)
   |> rename(columns: {_value: "first_value"}) // Rename to avoid conflicts
   |> keep(columns: ["_time", "first_value", "user", "macAddress", "_field","measurement"]) // Kee

lastSteps = from(bucket: "${client!.bucket}")
   |> range(start: $startOfDayIso, stop: $endOfDayIso)
   |> filter(fn: (r) => r["measurement"] == "steps" and r["user"] == "$user")
  ${tags.isNotEmpty ? "|> filter(fn: (r) => ${tags.map((tag) => 'r[\"${tag.key}\"] ${tag.type.symbol} ${tag.value is String ? '\"${tag.value}\"' : tag.value}').join(' and ')})" : ''}
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => r.measurement_time >= ${startOfDay.millisecondsSinceEpoch}.0 and r.measurement_time <= ${endOfDay.millisecondsSinceEpoch}.0)
  |> map(fn: (r) => ({
      r with
      _time: time(v: int(v: float(v: r.measurement_time) * 1000000.0))
  }))
  |> rename(columns: {stepsbosch: "_value"})
  |> keep(columns: ["_time", "_value", "user", "macAddress", "measurement"])
|> aggregateWindow(every: 1h, fn: last, createEmpty: false)
   |> rename(columns: {_value: "last_value"}) // Rename to avoid conflicts
   |> keep(columns: ["_time", "last_value", "user", "macAddress", "_field","measurement"]) // Kee

join(tables: {first: firstSteps, last: lastSteps}, on: ["_time","user", "macAddress" ,"measurement"])
  |> map(fn: (r) => ({
      _time: r._time,
      user: r.user,
      macAddress: r.macAddress,
      _field: r._field,
      measurement: r.measurement,
      _value: r.last_value - r.first_value
    }))

''';

    debugPrint(
        '3 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData $fluxQuery');
    // Send the query to the InfluxDB API
    final response = await http.post(
      Uri.parse('${client!.url}/api/v2/query?org=${client!.org}'),
      headers: {
        'Authorization': 'Token ${client!.token}',
        'Content-Type': 'application/vnd.flux',
      },
      body: fluxQuery,
    );

    debugPrint(
        '4 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData ${response.statusCode},, ${response.body}');
    List<Measurement> results = [];
    if (response.statusCode == 200) {
      // Parse the CSV-like response from InfluxDB
      final liness = LineSplitter.split(response.body).toList();
      debugPrint(
          '5 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData $liness');

      if (liness.isEmpty) {
        return [];
      }

      final tabless = liness.join(' ').split(',result,table').where((e) => e.isNotEmpty).toList();
      debugPrint(
          '5.2 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData $tabless');
      final tables =
          tabless.map((e) => ',result,table$e'.split(' ')).where((e) => e.isNotEmpty).toList();
      debugPrint(
          '5.5 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData ${liness.length} ${tabless.length} ::::${liness}::::: | ::::${liness}::::: | $tabless ::::::::: $tables');
      for (var j = 0; j < tables.length; j++) {
        final lines = tables[j];
        final headers = lines.first.split(',');
        final dataRows = lines.skip(1).toList();
        // debugPrint('6 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData $headers');
        // debugPrint('7 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData ${dataRows[1]}');

        for (var i = 0; i < dataRows.length; i++) {
          var data = dataRows[i].trim();
          var header = lines.first.trim();
          if (data.isEmpty || data == header) continue;
          // debugPrint('1 Record: ${dataRows[i]}');
          final record = _parseInfluxRecord(dataRows[i], headers);
          // debugPrint('2 Record: $record');
          // DataType type = getDataTypeFromValue(
          //     record['measurement'] ?? record['_measurement']);
          DataType type = DataType.STEPS;
          var measurement = Measurement(type, record['macAddress'] ?? '');
          DateTime dateTime = DateTime.tryParse(record['_time']) ?? DateTime.now();
          debugPrint(
              '7 +++++++++++++++++++++++++++++++++++++++++++++++++++++++ fetchHourlyStepsData date ${record['_time']} ::::: ${dateTime.hour} ::: ${record['measurement']} ::: ${record['_value']}');
          measurement.time = dateTime.millisecondsSinceEpoch;
          measurement.values = [Value(type.name, '', num.parse(record['_value']), true)];

          results.add(measurement);
        }
      }
    } else {
      throw Exception('Failed to fetch hourly steps data: ${response.body}');
    }
    return results;
  }

  String _getTimezoneOffset(DateTime dateTime) {
    String offset = dateTime.timeZoneOffset.isNegative ? "-" : "+";
    String hours = dateTime.timeZoneOffset.inHours.abs().toString().padLeft(2, '0');
    String minutes =
        dateTime.timeZoneOffset.inMinutes.remainder(60).abs().toString().padLeft(2, '0');

    return "$offset$hours:$minutes";
  }

  void queryInfluxData(String tagValue,
      {String tag = 'user',
      int rangeSec = 60 * 60,
      Duration allDur = const Duration(hours: 1),
      List<DataType> dataTypes = const [
        DataType.HEART_RATE,
        DataType.SPO2,
        // DataType.R2R_INTERVALS,
        DataType.STEPS
      ]}) {
    var range = Duration(seconds: rangeSec);
    var all = allDur;
    dataTypes.forEach((type) {
      var tags = [Tag(key: tag, value: tagValue)];
      var fields = [type.value];
      var field = '';
      if (type == DataType.R2R_INTERVALS) {
        // tags.add(Tag(key: '_field', value: 'rr'));
        field = 'rr';
      }
      if (type == DataType.HEART_RATE) {
        // tags.add(Tag(key: '_field', value: 'hr'));
        field = 'hr';
      }
      if (type == DataType.SPO2) {
        // tags.add(Tag(key: '_field', value: 'spo2'));
        field = 'spo2';
      }
      if (type == DataType.STEPS) {
        fields.add('steps');
        field = 'stepsbosch';
      }
      getLastData(AggregatedDataParams(
          range: range,
          field: field,
          fields: fields,
          tags: tags,
          aggregations: [
            Aggregation(type == DataType.STEPS ? AggregationType.max : AggregationType.last, all),
            // Aggregation(AggregationType.max, all),
          ],
          startOfDay: false));
    });
  }
}
