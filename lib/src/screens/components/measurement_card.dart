import 'package:dca/src/data-distribution/data_source_type.dart';
import 'package:dca/src/data-distribution/measurement.dart';
import 'package:dca/src/screens/data_plot_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MeasurementCard extends StatelessWidget {
  final String label;
  final double min;

  final double max;
  final double mean;
  final Metrics metrics;

  const MeasurementCard(
      {super.key,
      required this.label,
      required this.min,
      required this.max,
      required this.mean,
      required this.metrics});

  String getValue(String type) {
    var item = sensorArr[type];
    if (item != null) {
      return item['aggregations'].map((a) {
        var v = metrics[a['agg'] ?? ''] ?? 0;
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
        // height: 160,
        width: 220,
        child: Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 5),
                // Text(item['descrip1'], style: TextStyle(fontSize: 14, color: Colors.grey)),
                // Text(item['descrip2'], style: TextStyle(fontSize: 14, color: Colors.grey)),
                Text(getValue(label),
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
        ));
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
    'min': 'Min: ',
    'max': 'Max: ',
  },
  DataType.STEPS.value: {
    'image': Icons.directions_walk,
    'title': 'Schritte',
    'aggregations': [
      {'agg': 'max', 'text': 'Gesamtschritte für den Tag\n'}
    ],
    'descrip1': 'Number of steps for the day',
    'max': '',
  },
  DataType.R2R_INTERVALS.value: {
    'image': Icons.monitor_heart,
    'title': 'R2R',
    'aggregations': [
      {'agg': 'mean', 'text': 'Durchschnitt für den Tag\n'}
    ],
    'descrip1': 'The average for the day',
    'mean': '',
  },
  DataType.SPO2.value: {
    'image': Icons.bloodtype,
    'title': 'Blutsauerstoff',
    'aggregations': [
      {'agg': 'mean', 'text': 'Durchschnitt für den Tag\n'}
    ],
    'descrip1': 'The average for the day',
    'mean': '',
  },
};
