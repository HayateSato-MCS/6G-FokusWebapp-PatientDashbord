import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dca/src/data-distribution/data_source_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data-distribution/measurement.dart';
import '../../data_handlers/influx_db_handler.dart';
import '../../data_handlers/influx_utils.dart';

class BatteryComponent extends StatefulWidget {
  final String macAddress;
  final String? userId;

  const BatteryComponent({super.key, required this.macAddress, this.userId});

  @override
  State<BatteryComponent> createState() => _BatteryComponentState();
}

class _BatteryComponentState extends State<BatteryComponent> {
  int soc = -1;
  Timer? timer;
  String address = '';
  InfluxDBHandler influxHandler = InfluxDBHandler.getInstance();

  @override
  void initState() {
    address = widget.macAddress;
    fetchDataPeriodically();
    super.initState();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refreshData() async {
    const range = Duration(seconds: 10);
    const aggRange = Duration(hours: 24);
    List<Measurement> data = await influxHandler.getAggregatedData(AggregatedDataParams(
        range: range,
        field: 'soc',
        fields: [DataType.BATTERY.value],
        tags: [widget.userId != null ? Tag(key: 'user', value: widget.userId) : Tag(key: 'macAddress', value: address)],
        aggregations: [
          Aggregation(AggregationType.last, aggRange),
          // Aggregation(AggregationType.max, range),
        ],
        startOfDay: true,
        publish: false));
    var m = data.firstWhereOrNull((e) => e.getAllValues().map((v) => v.name).contains('last'));
    if (mounted && m != null) {
      var last = m.getAllValues().firstWhereOrNull((v) => v.name == 'last')?.value;
      if (last != null) {
        var level = double.tryParse('$last');
        if (level != null) {
          setState(() {
            soc = level.toInt();
          });
        }
      }
    }
  }

  void fetchDataPeriodically() {
    // just to make sure the timer is cancelled before starting a new one
    timer?.cancel();
    refreshData();
    // assign timer like this, not within the callback of Timer.periodic
    timer = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        refreshData();
        debugPrint(
            '########################################################################## BatteryComponent fetchDataPeriodically $address $soc');
      } catch (e) {
        debugPrint(e.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    String color = soc > 50
        ? 'green'
        : soc > 15
            ? 'yellow'
            : soc >= 0
                ? 'red'
                : 'grey';
    return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        direction: Axis.vertical,
        children: [
          Container(
              // color: Colors.blueAccent,
              child: SvgPicture.string(
            '''
      <svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" fill="none">
        <path d="M4 7V17H18V7H4ZM3 5H19C19.2652 5 19.5196 5.10536 19.7071 5.29289C19.8946 5.48043 20 5.73478 20 6V18C20 18.2652 19.8946 18.5196 19.7071 18.7071C19.5196 18.8946 19.2652 19 19 19H3C2.73478 19 2.48043 18.8946 2.29289 18.7071C2.10536 18.5196 2 18.2652 2 18V6C2 5.73478 2.10536 5.48043 2.29289 5.29289C2.48043 5.10536 2.73478 5 3 5ZM21 9H23V15H21V9Z" fill=${soc >= 0 ? 'currentColor' : color}/>
        <rect x="5" y="8" width="2" height="8" fill="currentColor"/>
        <path fill=$color d="M5 8H${soc >= 0 ? (soc! * 0.12 + 5).toInt() : 17}V16H5z"/>
      </svg>
      ''',
            width: 24,
            height: 24,
          )),
          Container(
              // color: Colors.blueAccent,
              child: Text(
            soc >= 0 ? '$soc%' : '--',
            style: TextStyle(height: 1, fontSize: 12),
            textAlign: TextAlign.center,
          ))
        ]);
  }
}
