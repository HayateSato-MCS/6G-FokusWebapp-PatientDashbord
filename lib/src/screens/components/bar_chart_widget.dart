import 'package:collection/collection.dart';
import 'package:dca/src/data-distribution/measurement.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data-distribution/data_source_type.dart';

class BarChartWidget extends StatelessWidget {
  final List<Measurement> data;
  final String label;
  final Color color;
  final double minX;
  final double maxX;

  const BarChartWidget({
    super.key,
    required this.data,
    required this.label,
    required this.color,
    required this.minX,
    required this.maxX,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    // Fill data for all 24 hours to ensure alignment
    final hourlyData = List.generate(24, (hour) {
      final time = startOfDay.add(Duration(hours: hour));
      final filtered = data
          .where((measurement) =>
              DateTime.fromMillisecondsSinceEpoch(measurement.time)
                      .toLocal()
                      .hour -
                  1 ==
              hour)
          .sorted((a, b) => b.time - a.time);
      final matchingMeasurement = filtered.isNotEmpty
          ? filtered.last
          : Measurement(
              DataType.STEPS,
              '',
              time: time.millisecondsSinceEpoch,
              values: [Value(label, 'count', 0, true)],
            );

      // debugPrint(
      //     '7 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> fetchDataForUser steps: ${hour},, ${matchingMeasurement.values} ::::${filtered.map((e) => e.values)}');
      final value = matchingMeasurement.values.first.value.toDouble() ?? 0.0;

      return BarChartGroupData(
        x: hour,
        barRods: [
          BarChartRodData(
            toY: value,
            color: color,
            width: 8, // Bar width
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      );
    });

    // Determine max Y value dynamically with padding
    final maxBarValue = hourlyData
        .map((group) => group.barRods.first.toY)
        .reduce((a, b) => a > b ? a : b);
    final maxY = maxBarValue > 0
        ? maxBarValue + 50
        : 200; // Ensure there is always some vertical scale

    return Card(
      child: Container(
        padding: const EdgeInsets.only(top: 20.0),
        child: BarChart(
          BarChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              verticalInterval: 0.04,
              // Ensure grid lines at every hour
              horizontalInterval: 200,
              // Adjust this value for better horizontal scaling
              getDrawingVerticalLine: (value) => FlLine(
                  color: Colors.grey.withOpacity(0.5),
                  strokeWidth: 0.8,
                  dashArray: [1, 2, 3, 4, 5, 6]),
              getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey.withOpacity(0.5),
                  strokeWidth: 0.5,
                  dashArray: [1, 2, 3, 4, 5, 6]),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1, // Ensure labels appear at every hour
                  getTitlesWidget: (value, meta) {
                    final hour = value.toInt();
                    final formattedTime = DateFormat('HH:mm')
                        .format(startOfDay.add(Duration(hours: hour)));
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        formattedTime,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: 200, // Match with horizontal grid lines
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(
              show: false,
              border: Border.all(color: Colors.grey.withOpacity(0.5), width: 1),
            ),
            barGroups: hourlyData,
            // maxY: 800,
            minY: 0,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                tooltipPadding:
                    EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                getTooltipColor: (ls) {
                  return Colors.blue;
                },
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  return BarTooltipItem(
                    rod.toY.toStringAsFixed(0),
                    // customize your tooltip text here
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
