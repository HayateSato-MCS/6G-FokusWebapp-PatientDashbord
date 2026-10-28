import 'dart:async';

import 'package:fhir/r4/general_types/general_types.dart';
import 'package:fhir/r4/resource_types/base/individuals/individuals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:dca/src/data_handlers/fhir_utils.dart';
import 'package:dca/src/data_handlers/influx_db_handler.dart';
import 'package:dca/src/providers/influx_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../mcs_dashboard_tab.dart';
import '../../fall_detection/fall_detection.dart';
import '../../data-distribution/data_source_type.dart';
import '../../data-distribution/measurement.dart';
import '../../data-distribution/publish_subscribe_manager.dart';
import '../../utils/data_util.dart';
import '../data_plot_screen.dart';

class UserDataItem extends StatefulWidget {
  final Patient user;

  static Map<String, Map<DataType, List<Value>>> lastValuesStatic = {};

  const UserDataItem({super.key, required this.user});

  @override
  State<UserDataItem> createState() => _UserDataItemState();
}

class _UserDataItemState extends State<UserDataItem> {
  Map<DataType, List<Value>> dataMap = {};
  String userId = '';
  Timer? timer;
  bool isActive = false;
  String name = '';
  InfluxDBHandler influxHandler = InfluxDBHandler.getInstance();

  @override
  void initState() {
    userId = widget.user.fhirId.toString();
    dataMap = UserDataItem.lastValuesStatic[userId] ?? {};

    var nameList = widget.user.name;
    HumanName humanName = nameList != null && nameList.isNotEmpty
        ? nameList[0]
        : const HumanName();
    name = '${humanName.given?.join('-')} ${humanName.family}';
    fetchDataPeriodically();
    super.initState();
  }

  @override
  void dispose() {
    cancelDataFetching();
    super.dispose();
  }

  void cancelDataFetching() {
    SubscriptionManager.unsubscribe('MeasurementListItem${userId}');
    timer?.cancel();
  }

  void fetchDataPeriodically() {
    influxHandler.queryInfluxData(userId);
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (InfluxProvider.shouldFetchStatic) {
        this.timer = timer;
        try {
          influxHandler.queryInfluxData(userId);
          debugPrint(
              '########################################################################## fetchDataPeriodically $userId');
        } catch (e) {
          debugPrint(e.toString());
        }
      }
    });
    SubscriptionManager.subscribe('MeasurementListItem${userId}',
        (source, type, data) {
      if (data is Measurement && mounted && data.getId() == userId) {
        setState(() {
          if (data.dataType == DataType.ACTIVITY) {
            // value = DataUtil.getActivity(data, activityList);
          } else {
            dataMap[type] = DataUtil.getDisplayMeasurementValue(data);
          }
        });
      }
    }, [SourceType.INFLUX_DB], [DataType.ANY]);
  }

  String getStringValue(List<Value>? values) {
    var result = '--';
    if (values != null && values.isNotEmpty) {
      result = values.first.value;
    }
    // if (result != '--')debugPrint(
    //     '########################################################################## getStringValue $result,,,, ${values}');

    return result;
  }

  int getTimestamp(List<Value>? values) {
    var result = 0;

    // debugPrint(
    //     '########################################################################## getTimestamp $values');
    if (values != null && values.isNotEmpty) {
      result =
          values.firstWhereOrNull((v) => v.name == 'timestamp')?.value ?? 0;
    }
    return result;
  }

  String getTimeString(List<Value>? values) {
    var result = '';
    var time = getTimestamp(values);
    String v = getStringValue(values);
    // debugPrint(
    //     '########################################################################## getTimeString $v,,,, $time,,,, ${DateTime.now().millisecondsSinceEpoch - time}');
    // if (time > 0 && DateTime.now().millisecondsSinceEpoch - time > 60000) {
    if (getStringValue(values) != '--') {
      result =
          'gemessen um ${DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(time))}';
    }
    // }
    return result;
  }

  void openPatient(FallDetectionServices? fallDetection) {
    // Opening the patient counts as acknowledging their fall alert, as in
    // the Python fall dashboard.
    fallDetection?.alerts.acknowledge(userId);
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: patientRouteName(userId)),
        builder: (context) => DataPlotsScreen(user: widget.user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallDetection = FallDetectionScope.maybeOf(context);
    if (fallDetection == null) return buildCard(null, null);
    return ListenableBuilder(
      listenable: Listenable.merge([fallDetection.alerts, fallDetection.counts]),
      builder: (context, _) => buildCard(fallDetection, fallDetection.alerts.stateFor(userId)),
    );
  }

  /// Card colouring follows the Python fall dashboard (style.css): pale red
  /// while pending, red border + strip + large line for an alert, green when
  /// resolved; colours fade over 200 ms.
  Widget buildCard(FallDetectionServices? fallDetection, PatientAlertState? alert) {
    final colors = alertCardColors(alert);
    final isAlert = alert?.kind == PatientAlertKind.alert;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
        color: colors?.$1 ?? Colors.white, // Container's background color
        border: Border.all(color: colors?.$2 ?? Colors.transparent),
        borderRadius: BorderRadius.circular(8), // Optional: Rounded corners
        boxShadow: const [
          BoxShadow(
            color: Colors.grey, // Shadow color
            offset: Offset(0, 3), // Offset of the shadow
            blurRadius: 5, // Blur radius of the shadow
            spreadRadius: 0, // How much the shadow should spread
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 20),
      child: GestureDetector(
          onTap: () => openPatient(fallDetection),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fallDetection != null)
                PatientAlertBanner(
                    controller: fallDetection.alerts, patientId: userId, showOverlay: false),
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  height: 80,
                  child: buildRow(fallDetection, showVitals: !isAlert),
                ),
              ),
              if (isAlert && alert?.overlay != null)
                Container(
                  color: FallColors.alertOverlay,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  child: Text(
                    alert!.overlay!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: FallColors.alertOverlayText,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          )),
    );
  }

  Widget buildFallCount(FallCountsProvider counts) {
    final count = counts.countFor(userId);
    final value = count?.toString() ?? (counts.failed ? 'n. v.' : '—');
    return Column(children: [
      const Text('Stürze (7 Tage)'),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ]);
  }

  /// The original tile content. During an alert only the name stays, like
  /// the Python dashboard hides the details behind "Help is requested".
  Widget buildRow(FallDetectionServices? fallDetection, {required bool showVitals}) {
    return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                    flex: 20,
                    child: Container(
                      color: Colors.transparent,
                      child: Row(
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Flexible(
                                    flex: 1,
                                    fit: FlexFit.loose,
                                    child: Wrap(
                                      children: [
                                        const Icon(Icons.person),
                                        const SizedBox(
                                          width: 10,
                                        ),
                                        Text(name),
                                      ],
                                    )),
                                Text('  ID: $userId'),
                              ])),
                          Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: BatteryComponent(
                                // macAddress: '6C:1D:EB:04:A9:E6',
                                macAddress: '',
                                userId: userId,
                              )),
                        ],
                      ),
                    )),
                if (showVitals) ...[
                Container(
                  color: Colors.grey,
                  width: 1,
                  height: double.maxFinite,
                ),
                Expanded(
                    flex: 15,
                    child: Container(
                        color: Colors.transparent,
                        child: Column(children: [
                          const Text('Bewegungsübersicht'),
                          Text(
                              '${getStringValue(dataMap[DataType.STEPS])} Schritte'),
                          Expanded(
                              child: Container(
                            alignment: Alignment.bottomCenter,
                            child: Text(getTimeString(dataMap[DataType.STEPS])),
                          ))
                        ]))),
                Container(
                  color: Colors.grey,
                  width: 1,
                  height: double.maxFinite,
                ),
                Expanded(
                    flex: 15,
                    child: Container(
                        color: Colors.transparent,
                        child: Column(children: [
                          const Text('Puls'),
                          Text(
                              '${getStringValue(dataMap[DataType.HEART_RATE])} Bpm'),
                          Expanded(
                              child: Container(
                            alignment: Alignment.bottomCenter,
                            child: Text(
                                getTimeString(dataMap[DataType.HEART_RATE])),
                          ))
                        ]))),
                Container(
                  color: Colors.grey,
                  width: 1,
                  height: double.maxFinite,
                ),
                Expanded(
                    flex: 15,
                    child: Container(
                        color: Colors.transparent,
                        child: Column(children: [
                          const Text('Blutsauerstoff'),
                          Text('${getStringValue(dataMap[DataType.SPO2])} %'),
                          Expanded(
                              child: Container(
                            alignment: Alignment.bottomCenter,
                            child: Text(getTimeString(dataMap[DataType.SPO2])),
                          ))
                        ]))),
                if (fallDetection != null) ...[
                  Container(
                    color: Colors.grey,
                    width: 1,
                    height: double.maxFinite,
                  ),
                  Expanded(flex: 12, child: buildFallCount(fallDetection.counts)),
                ],
                ],
                // Container(
                //   color: Colors.grey,
                //   width: 1,
                //   height: double.maxFinite,
                // ),
                // Expanded(
                //     flex: 15,
                //     child: Container(
                //         color: Colors.transparent,
                //         child: Column(children: [
                //           const Text('RR-Wert'),
                //           Text(
                //               '${getStringValue(dataMap[DataType.R2R_INTERVALS])} ms')
                //         ]))),
              ]);
  }
}
