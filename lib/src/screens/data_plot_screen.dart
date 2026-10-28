import 'dart:async';

import 'package:dca/src/fall_detection/fall_detection.dart';
import 'package:dca/src/screens/components/battery_component.dart';
import 'package:fhir/r4/general_types/general_types.dart';
import 'package:fhir/r4/resource_types/base/individuals/individuals.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:dca/src/data_handlers/fhir_handler.dart';
import 'package:dca/src/data_handlers/fhir_utils.dart';
import 'package:dca/src/data_handlers/influx_db_handler.dart';
import 'package:dca/src/data_handlers/influx_utils.dart';
import 'package:dca/src/providers/influx_provider.dart';
import 'package:dca/src/screens/components/bar_chart_widget.dart';
// import 'package:dca/src/screens/components/measurement_card.dart';
import 'package:dca/src/screens/components/standalone_measurement_card.dart';
import 'package:dca/src/screens/components/week_navigator.dart';
import 'package:dca/src/utils/data_util.dart';

import '../data-distribution/data_source_type.dart';
import '../data-distribution/measurement.dart';
import 'components/line_chart_widget.dart';

class DataPlotsScreen extends StatefulWidget {
  final Patient user;

  const DataPlotsScreen({super.key, required this.user});

  static Map<String, List<Measurement>> staticData = {};
  static Map<String, Map<String, Metrics>> staticMetrics = {};

  @override
  State<DataPlotsScreen> createState() => _DataPlotsScreenState();
}

var sensors = [
  DataType.HEART_RATE,
  DataType.SPO2,
  DataType.STEPS,
  // DataType.R2R_INTERVALS
];

class _DataPlotsScreenState extends State<DataPlotsScreen> {
  final Map<DataType, GlobalKey<StandaloneMeasurementCardState>> metricsKeys = {};
  List<Measurement> data = [];
  static Map<String, Metrics> metrics = {};
  static List<Workout> workouts = [];
  Set<DataType> loadingList = {};
  double minX = 0;
  double maxX = 0;
  var date = DateTime.now();
  var dateStart = DateTime.now();
  var dateEnd = DateTime.now();
  String userId = '202';
  String id = '';

  // Falls on the selected day (plan D4). Null while loading.
  FallDetectionServices? fallDetection;
  StreamSubscription<String>? answeredFallsSubscription;
  DayFalls? dayFalls;
  bool dayFallsFailed = false;
  int dayFallsRequest = 0;

  @override
  void initState() {
    super.initState();
    InfluxProvider.shouldFetchStatic = false;
    userId = widget.user.fhirId.toString();
    updateDate(date);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = FallDetectionScope.maybeOf(context);
    if (services == fallDetection) return;
    answeredFallsSubscription?.cancel();
    fallDetection = services;
    // A newly answered fall for this patient shows up in the count when
    // today is selected.
    answeredFallsSubscription = services?.answeredFalls.listen((patientId) {
      if (patientId == userId && DateUtils.isSameDay(date, DateTime.now())) loadDayFalls();
    });
    loadDayFalls();
  }

  @override
  void dispose() {
    answeredFallsSubscription?.cancel();
    data.clear();
    metrics.clear();
    InfluxProvider.shouldFetchStatic = true;
    super.dispose();
  }

  Future<void> loadDayFalls() async {
    final services = fallDetection;
    if (services == null) return;
    final request = ++dayFallsRequest; // a later date change wins
    final day = InfluxFallRepository.localDay(date);
    try {
      final result = await services.repository
          .fetchFallsBetween(patientId: patientIdOf(widget.user), start: day.start, stop: day.stop);
      if (!mounted || request != dayFallsRequest) return;
      setState(() {
        dayFalls = result;
        dayFallsFailed = false;
      });
    } on InfluxQueryException catch (error) {
      debugPrint('Falls for $userId unavailable: $error');
      if (!mounted || request != dayFallsRequest) return;
      setState(() => dayFallsFailed = true);
    }
  }

  void updateDate(DateTime newDate, [bool force = false]) async {
    date = newDate;
    dayFalls = null;
    dayFallsFailed = false;
    loadDayFalls();
    dateStart = DateTime(date.year, date.month, date.day);
    id = userId + dateStart.toString();
    debugPrint(
        '################################################## updateDate $id, ${DataPlotsScreen
            .staticData}');
    minX = dateStart.millisecondsSinceEpoch.toDouble();
    dateEnd = DateTime(
        date.year,
        date.month,
        date.day,
        23,
        59,
        59,
        999);
    maxX = dateEnd.millisecondsSinceEpoch.toDouble();
    // Fetch data when the screen is initialized
    // data = DataPlotsScreen.staticData[id] ?? data;
    // metrics = DataPlotsScreen.staticMetrics[id] ?? metrics;
    fetchDataForUser(userId, force);
  }

  void fetchDataForUser(String user, bool force) async {
    var influx = InfluxDBHandler.getInstance();
    var userData = DataPlotsScreen.staticData[id] ?? [];

    sensors.forEach((type) {
      var typeData = userData.where((m) => m.dataType == type);

      if (typeData.isNotEmpty) {
        setState(() {
          data = data.whereNot((d) => d.dataType == type).toList();
          data.addAll(typeData);
        });
      }
      if (typeData.isEmpty || force) {
        setState(() {
          loadingList.add(type);
        });
      }

      if (type == DataType.STEPS) {
        influx.fetchHourlyStepsData(userId, date).then((value) {
          debugPrint(
              '1 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> fetchDataForUser steps: ${value}');
          setState(() {
            loadingList.remove(type);
            var newData = value.where((v) => v.time >= minX && v.time < maxX);
            debugPrint(
                '2 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> fetchDataForUser steps: ${newData}');
            data.addAll(newData);
            userData.addAll(newData);
            DataPlotsScreen.staticData[id] = userData;
            debugPrint(
                '3 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> fetchDataForUser steps: ${data}');
            debugPrint(
                '4 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> fetchDataForUser steps: ${userData
                    .map((m) => m.dataType)}');
          });
        }).catchError((err) {
          loadingList.remove(type);
        });
      } else {
        var tags = [
          Tag(key: 'user', value: userId),
          Tag(key: 'measurement', value: type.value)
        ];
        var field = '';
        if (type == DataType.R2R_INTERVALS) {
          // tags.add(Tag(key: '_field', value: 'rr'));
          field = 'rr';
        }
        if (type == DataType.SPO2) {
          // tags.add(Tag(key: '_value', value: 100, type: OperationType.lessEqual));
          // tags.add(Tag(key: '_field', value: 'spo2'));
          field = 'spo2';
        }
        if (type == DataType.HEART_RATE) {
          // tags.add(Tag(key: '_field', value: 'hr'));
          field = 'hr';
        }
        if (type == DataType.STEPS) {
          // tags.add(Tag(key: '_field', value: 'stepsbosch'));
          field = 'stepsbosch';
        }
        influx
            .fetchData(
            FetchDataParams(start: dateStart,
                stop: dateEnd,
                field: field,
                aggregationMethod: 'median',
                interval: const Duration(minutes: 15),
                tags: tags)
        )
            .then((value) {
          setState(() {
            loadingList.remove(type);
            var newData = value.where((v) => v.time >= minX && v.time < maxX);
            data.addAll(newData);
            userData.addAll(newData);
            DataPlotsScreen.staticData[id] = userData;
          });
        }).catchError((err) {
          loadingList.remove(type);
        });
      }
      getDayMetrics(type);
    });

    FhirHandler handler = FhirHandler();
    workouts = await handler.fetchWorkouts(user, date);
    if (mounted) setState(() {});
  }

  void getDayMetrics(DataType sensor) {
    var influx = InfluxDBHandler.getInstance();
    Duration range = const Duration(hours: 24);
    var typeData = DataPlotsScreen.staticMetrics[id];
    if (typeData?[sensor.value] != null) {
      setState(() {
        metrics[sensor.value] = typeData![sensor.value]!;
      });
    }
    var tags = [Tag(key: 'user', value: userId)];
    var field = '';
    if (sensor == DataType.R2R_INTERVALS) {
      // tags.add(Tag(key: '_field', value: 'rr'));
      field = 'rr';
    }
    if (sensor == DataType.SPO2) {
      // tags.add(Tag(key: '_value', value: 100, type: OperationType.lessEqual));
      // tags.add(Tag(key: '_field', value: 'spo2'));
      field = 'spo2';
    }
    if (sensor == DataType.HEART_RATE) {
      // tags.add(Tag(key: '_field', value: 'hr'));
      field = 'hr';
    }
    if (sensor == DataType.STEPS) {
      // tags.add(Tag(key: '_field', value: 'stepsbosch'));
      field = 'stepsbosch';
    }
    debugPrint(
        "1 ---------------------------------------------------- data metrics");
    influx
        .getAggregatedData(AggregatedDataParams(
      field: field,
        fields: [
          sensor.value,
        ],
        start: dateStart,
        stop: dateEnd,
        tags: tags,
        aggregations: [
          Aggregation(AggregationType.mean, range),
          Aggregation(AggregationType.min, range),
          Aggregation(AggregationType.max, range),
        ],
        publish: false,
        startOfDay: true))
        .then((value) {
      if (value.isNotEmpty) {
        setState(() {
          for (var el in value) {
            var t = DateTime.fromMillisecondsSinceEpoch(el.time);
            if (!DataUtil.isSameDay(t, date)) continue;
            Metrics metric =
                metrics[el.dataType.value] ?? Metrics(min: 0, max: 0, mean: 0);
            el.values.forEach((v) {
              if (v.name == 'min') metric.min = double.tryParse(v.value) ?? 0;
              if (v.name == 'max') metric.max = double.tryParse(v.value) ?? 0;
              if (v.name == 'mean') metric.mean = double.tryParse(v.value) ?? 0;
            });
            metrics[el.dataType.value] = metric;
            var metricData = DataPlotsScreen.staticMetrics[id] ?? {};
            metricData[el.dataType.value] = metric;
            DataPlotsScreen.staticMetrics[id] = metricData;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final stepsData = data.where((d) => d.dataType == DataType.STEPS).toList();
    debugPrint(
        '6 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> fetchDataForUser steps: ${stepsData
            .map((s) => '${s.values}')}');
    final heartRateData =
    data.where((d) => d.dataType == DataType.HEART_RATE).toList();
    final spo2Data = data.where((d) => d.dataType == DataType.SPO2).toList();
    final rrData =
    data.where((d) => d.dataType == DataType.R2R_INTERVALS).toList();
    var nameList = widget.user.name;
    HumanName name = nameList != null && nameList.isNotEmpty
        ? nameList[0]
        : const HumanName();
    return Scaffold(
        appBar: AppBar(
            title: Row(
              children: [
                CircleAvatar(radius: 25, child: Icon(Icons.person)),
                SizedBox(width: 10),
                SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                      child: Text(
                          'Statistik für ${name.given?.join('-')} ${name
                              .family}')),
                  Wrap(
                    direction: Axis.horizontal,
                    alignment: WrapAlignment.start,
                    children: [
                      Text('ID: ', style: TextStyle(fontSize: 16)),
                      Text(userId,
                          style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                    ],
                  ),
                ]),
                // BatteryComponent(macAddress: '')
              ],
            )),
        body: Container(
            padding: EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        WeekNavigator(
                          onDateChange: (newDate) {
                            setState(() {
                              date = newDate;
                              data = [];
                              metrics = {};
                              updateDate(newDate);
                            });
                          },
                        )
                      ],
                    ),
                    // DateNavigator(),
                  ],
                ),
                SizedBox(
                  height: 20,
                ),
                Container(
                  height: 130,
                  width: double.maxFinite,
                  child: Row(children: [
                    Expanded(child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              ...sensors.map((e) {
                                var item = e;
                                var metric = metrics[item.value] ??
                                    Metrics(min: 0, max: 0, mean: 0);
                                // return MeasurementCard(
                                //     label: item.value,
                                //     min: metric.min,
                                //     max: metric.max,
                                //     mean: metric.mean,
                                //     metrics: metric);
                                // metricsKeys.putIfAbsent(e, () => GlobalKey<StandaloneMeasurementCardState>());
                                return StandaloneMeasurementCard(
                                  key: metricsKeys[e],
                                    userId: userId,
                                    dataType: e,
                                date: DateTimeRange(start: dateStart, end: dateEnd),fetchInterval: const Duration(seconds: 10
                                ),);
                              }),
                              if (fallDetection != null)
                                DayFallsCard(day: date, falls: dayFalls, failed: dayFallsFailed),
                            ]))),
                    SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        updateDate(date, true);
                        // metricsKeys.values.forEach((mk) {
                        //   mk.currentState?.fetchData();
                        // });
                      },
                      child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 0, vertical: 2),
                          child: Row(
                            children: [
                              Text('Aktualisieren'),
                              SizedBox(
                                width: 5,
                              ),
                              Icon(Icons.refresh)
                            ],
                          )),
                    )
                  ],),
                ),
                SizedBox(height: 50),
                Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schritte (Stündlich)',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(
                                height: 200,
                                child: BarChartWidget(
                                  data: stepsData,
                                  label: 'Steps',
                                  color: Colors.blue,
                                  maxX: maxX,
                                  minX: minX,
                                )),
                            SizedBox(height: 24),
                            Text(
                              'Puls (Median, alle 15 Min)',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                            Stack(children: [
                              LineChartWidget(
                                data: heartRateData,
                                label: 'Heart Rate',
                                maxX: maxX,
                                minX: minX,
                                workoutIntervals: workouts,
                              ),
                              if (loadingList.contains(DataType.HEART_RATE))
                                Container(
                                    height: 200,
                                    margin: EdgeInsets.only(top: 20, right: 20),
                                    alignment: Alignment.topRight,
                                    child: CircularProgressIndicator())
                            ]),
                            SizedBox(height: 24),
                            Text(
                              'Blutsauerstoff (Median, alle 15 Min)',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                            Stack(children: [
                              LineChartWidget(
                                  data: spo2Data,
                                  label: 'SPO2',
                                  maxX: maxX,
                                  minX: minX,
                                  workoutIntervals: workouts
                              ),
                              if (loadingList.contains(DataType.SPO2))
                                Container(
                                    height: 200,
                                    margin: EdgeInsets.only(top: 20, right: 20),
                                    alignment: Alignment.topRight,
                                    child: CircularProgressIndicator())
                            ]),
                            // SizedBox(height: 24),
                            // Text(
                            //   'RR-Wert (Median, alle 15 Min)',
                            //   style: TextStyle(
                            //       fontSize: 16, fontWeight: FontWeight.w500),
                            // ),
                            // Stack(children: [
                            //   LineChartWidget(
                            //       data: rrData,
                            //       label: 'RR-Wert',
                            //       maxX: maxX,
                            //       minX: minX,
                            //       workoutIntervals: workouts
                            //       ),
                            //   if (loadingList.contains(DataType.R2R_INTERVALS))
                            //     Container(
                            //         height: 200,
                            //         margin: EdgeInsets.only(top: 20, right: 20),
                            //         alignment: Alignment.topRight,
                            //         child: CircularProgressIndicator())
                            // ]),
                          ],
                        ),
                      ),
                    )),
              ],
            )));
  }

}

class Metrics {
  double min;
  double max;
  double mean;

  Metrics({required this.min, required this.mean, required this.max});

  // Overloading the [] operator
  double operator [](String key) {
    switch (key) {
      case 'min':
        return min;
      case 'max':
        return max;
      case 'mean':
        return mean;
      default:
        throw ArgumentError(
            "Invalid key: $key. Valid keys are 'min', 'max', 'mean'.");
    }
  }
}
