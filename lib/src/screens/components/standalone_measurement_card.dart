import 'dart:async'; // For Timer
import 'package:dca/src/data-distribution/data_source_type.dart';
import 'package:dca/src/screens/data_plot_screen.dart';
import 'package:flutter/material.dart';
import '../../data_handlers/influx_db_handler.dart';
import '../../data_handlers/influx_utils.dart';

class StandaloneMeasurementCard extends StatefulWidget {
  final String userId;
  final DataType dataType;
  final DateTimeRange date;
  final Duration fetchInterval;
  final bool fetchEnabled; // To enable/disable fetching

  const StandaloneMeasurementCard({
    super.key,
    required this.userId,
    required this.dataType,
    required this.date,
    this.fetchInterval = const Duration(seconds: 10),
    this.fetchEnabled = true,
  });

  static Map<String, Map<String, Metrics>> staticMetrics = {};

  @override
  StandaloneMeasurementCardState createState() => StandaloneMeasurementCardState();
}

class StandaloneMeasurementCardState extends State<StandaloneMeasurementCard> {
  Metrics metric = Metrics(min: 0, max: 0, mean: 0);
  String label = '';
  String? id;
  Timer? fetchTimer; // Timer for automatic data fetch

  @override
  void initState() {
    super.initState();
    label = widget.dataType.value;
    id = widget.userId + widget.date.start.toString();

    // Fetch data initially
    fetchData();

    // If fetchEnabled is true, set up the automatic fetching using Timer
    if (widget.fetchEnabled) {
      fetchDataPeriodically();
    }
  }

  @override
  void didUpdateWidget(covariant StandaloneMeasurementCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the date range changes, trigger a manual fetch
    if (widget.date.start != oldWidget.date.start) {
      id = widget.userId + widget.date.start.toString();
      fetchData();
    }

    // If fetchEnabled status changes, update the auto-fetch behavior
    if (widget.fetchEnabled != oldWidget.fetchEnabled) {
      if (widget.fetchEnabled) {
        fetchData();
        fetchDataPeriodically();
      } else {
        _cancelDataFetch();
      }
    }
  }

  @override
  void dispose() {
    _cancelDataFetch(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  // Set up the auto-fetch timer if enabled
  void fetchDataPeriodically() {
    fetchData();
    fetchTimer?.cancel();
    fetchTimer = Timer.periodic(widget.fetchInterval, (_) {
      fetchData();
    });
  }

  // Cancel the auto-fetch timer
  void _cancelDataFetch() {
    fetchTimer?.cancel();
  }

  void getDayMetrics(DataType sensor) {
    var influx = InfluxDBHandler.getInstance();
    Duration range = const Duration(hours: 24);
    var typeData = StandaloneMeasurementCard.staticMetrics[id];
    if (typeData?[sensor.value] != null) {
      setState(() {
        metric = typeData![label]!;
      });
    }
    var tags = [Tag(key: 'user', value: widget.userId)];
    var field = '';
    if (sensor == DataType.R2R_INTERVALS) field = 'rr';
    if (sensor == DataType.SPO2) field = 'spo2';
    if (sensor == DataType.HEART_RATE) field = 'hr';
    if (sensor == DataType.STEPS) field = 'stepsbosch';

    influx
        .getAggregatedData(
      AggregatedDataParams(
        field: field,
        fields: [sensor.value],
        start: widget.date.start,
        // stop: widget.date.end,
        tags: tags,
        aggregations: [
          Aggregation(AggregationType.mean, range),
          Aggregation(AggregationType.min, range),
          Aggregation(AggregationType.max, range),
        ],
        publish: false,
        startOfDay: true,
      ),
    )
        .then((values) {
      if (values.isNotEmpty) {
        setState(() {
          final value = values.first;
          value.values.forEach((v) {
            if (v.name == 'min') metric.min = double.tryParse(v.value) ?? 0;
            if (v.name == 'max') metric.max = double.tryParse(v.value) ?? 0;
            if (v.name == 'mean') metric.mean = double.tryParse(v.value) ?? 0;
          });

          var metricData = StandaloneMeasurementCard.staticMetrics[id] ?? {};
          metricData[value.dataType.value] = metric;
          if (id != null) StandaloneMeasurementCard.staticMetrics[id!] = metricData;
        });
      }
    });
  }

  void fetchData() {
    // Fetch metrics for the given data type
    getDayMetrics(widget.dataType);
  }

  String getValue(String type) {
    var item = sensorArr[type];
    if (item != null) {
      return item['aggregations'].map((a) {
        var v = metric[a['agg'] ?? ''] ?? 0;
        var val = v != 0 ? '$v'.split('.')[0] : '--';
        var res = '${a['text']}$val';
        return res;
      }).join('\n');
    }
    return '--';
  }

  @override
  Widget build(BuildContext context) {
    var item = sensorArr[label] ?? {};

    return SizedBox(
      width: 220,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item['image'], size: 30),
                  SizedBox(width: 10),
                  Text(item['title'],
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: 5),
              Text(getValue(label),
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

final Map<String, Map<String, dynamic>> sensorArr = {
  DataType.HEART_RATE.value: {
    'image': Icons.heart_broken,
    'title': 'Puls',
    'aggregations': [
      {'agg': 'min', 'text': 'Minimum: '},
      {'agg': 'max', 'text': 'Maximum: '},
      {'agg': 'mean', 'text': 'Durchschnitt: '}
    ],
  },
  DataType.STEPS.value: {
    'image': Icons.directions_walk,
    'title': 'Schritte',
    'aggregations': [
      {'agg': 'max', 'text': 'Gesamtschritte für den Tag\n'}
    ],
  },
  DataType.R2R_INTERVALS.value: {
    'image': Icons.monitor_heart,
    'title': 'R2R',
    'aggregations': [
      {'agg': 'mean', 'text': 'Durchschnitt für den Tag\n'}
    ],
  },
  DataType.SPO2.value: {
    'image': Icons.bloodtype,
    'title': 'Blutsauerstoff',
    'aggregations': [
      {'agg': 'mean', 'text': 'Durchschnitt für den Tag\n'}
    ],
  },
};
