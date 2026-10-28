import 'dart:convert';
import 'dart:math';
import 'package:dca/src/data_handlers/fhir_utils.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:dca/src/data-distribution/measurement.dart';
import 'dart:ui' as ui;

class LineChartWidget extends StatelessWidget {
  final List<Measurement> data;
  final String label;
  final double minX;
  final double maxX;
  final List<Workout> workoutIntervals;

  const LineChartWidget({
    super.key,
    required this.data,
    required this.label,
    required this.minX,
    required this.maxX,
    required this.workoutIntervals,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, List<Measurement>> groupedData = {};
    for (var measurement in data) {
      var deviceData =
          groupedData.putIfAbsent(measurement.deviceAddress, () => []);
      if (deviceData.firstWhereOrNull((d) => d.time == measurement.time) ==
          null) {
        deviceData.add(measurement);
      }
    }

    final List<Color> colors = [
      Colors.blue.withOpacity(1),
      Colors.red.withOpacity(1),
      Colors.green.withOpacity(1),
      Colors.orange.withOpacity(1),
      Colors.purple.withOpacity(1)
    ];

    List<LineChartBarData> lineBarsData = [];
    int colorIndex = 0;

    groupedData.forEach((deviceAddress, measurements) {
      lineBarsData.add(
        LineChartBarData(
          preventCurveOverShooting: true,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          spots: measurements
              .map((entry) => FlSpot(
                  entry.time.toDouble(), entry.values.first.value.toDouble()))
              .toList(),
          isCurved: true,
          // color: Colors.cyan, // Default line color
        ),
      );
      colorIndex++;
    });

    List<VerticalRangeAnnotation> backgroundAnnotations =
        workoutIntervals.map((workout) {
      double start =
          workout.start.millisecondsSinceEpoch.toDouble();
      double end =
          workout.end.millisecondsSinceEpoch.toDouble();

      return VerticalRangeAnnotation(
        x1: start,
        x2: end,
        color: colors[colorIndex++ % colors.length].withOpacity(0.2), // Cycle through colors
      );
    }).toList();

    return Stack(
      children: [
        Card(
          child: Container(
            height: 300,
            alignment: Alignment.bottomCenter,
            // padding: const EdgeInsets.only(top: 40, right: 30),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(

                  // padding: const EdgeInsets.only(top: 40, right: 30),
                    height: 200,
                    child: LineChart(
                  duration: const Duration(),
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final dateTime =
                                DateTime.fromMillisecondsSinceEpoch(
                                    value.toInt());
                            final formattedTime =
                                DateFormat('HH:mm').format(dateTime);
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(formattedTime,
                                  style: const TextStyle(fontSize: 10)),
                            );
                          },
                          interval: 3600000,
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: lineBarsData,
                    maxX: maxX,
                    minX: minX,
                    rangeAnnotations: RangeAnnotations(
                        verticalRangeAnnotations: backgroundAnnotations),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (ls) {
                          return Colors.blue;
                        },
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            return LineTooltipItem(
                              spot.y.toStringAsFixed(0), // custom text
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    // extraLinesData: ExtraLinesData(
                    //   verticalLines: workoutMarkers,
                    // ),
                  ),
                )),
                Container(
                    margin: const EdgeInsets.only(left: 45, right: 0),
                    // color: Colors.amberAccent,
                    child: Stack(children: [Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: workoutIntervals.asMap().entries.map((entry) {
                              int i = entry.key;
                              Workout workout = entry.value;
                              double start =
                              workout.start.millisecondsSinceEpoch.toDouble();
                              double end =
                              workout.end.millisecondsSinceEpoch.toDouble();
                              var t = Text(
                                workout.name,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              );

                              TextPainter tp = TextPainter(
                                text: TextSpan(
                                  text: workout.name,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                textDirection: ui.TextDirection.ltr,
                              )..layout(); // Lays out the text

                              // double tw = tp.width;
                              double tw = 44; // Get the width in pixels

                              // Use the exact middle of the interval
                              double mid = (start + end) / 2;

                              // Normalize to the X range [0, 1]
                              double xNormalized =
                                  (mid - minX) / (maxX - minX);

                              double w = constraints.maxWidth - 4;

                              double x = xNormalized * w;
                              double xPosition = x - tw/2;

                              return Positioned(
                                left: max(0, xPosition), // Adjust dynamically
                                top: i % 2 == 0 ? 50 : 5, // Adjust height for proper alignment
                                // width: 60,
                                child: Container(
                                  // color: Colors.green,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _getWorkoutIcon(workout, colors[i % colors.length]),
                                      const SizedBox(
                                          height:
                                          4), // Adjust for proper spacing
                                      // t,
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    )],))
              ],
            ),
          ),
        ),

        // Overlay workout markers (icons + labels)
      ],
    );
  }

  String getDur(int seconds) {
    int minutes = seconds ~/ 60; // Get whole minutes
    int remainingSeconds = seconds % 60; // Get remaining seconds
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Returns the appropriate workout icon based on the type
  Widget _getWorkoutIcon(Workout w, Color color) {
    String base64Image = w.icon;
    String name = w.name;
    String dur = getDur(w.end.difference(w.start).inSeconds);
    return Tooltip(
        message: '$name\n$dur min',
        decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ), // Message shown on hover
        child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.4),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 2, spreadRadius: 1),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 2, spreadRadius: 1),
          ],
        ),
        child: Image.memory(
        base64Decode(base64Image),
        width: 30, // Set size for the image
        height: 30,
        fit: BoxFit.cover,
      ),
    )));
  }
}
