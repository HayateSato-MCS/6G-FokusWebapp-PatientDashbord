import 'dart:math';

import 'package:flutter/material.dart';
import '../data-distribution/data_source_type.dart';
import 'package:collection/collection.dart';

import '../data-distribution/measurement.dart';

class DataUtil {
  static const int SECOND_IN_MILLIS = 1000;
  static const int MINUTE_IN_MILLIS = 60000;
  static const int HOUR_IN_MILLIS = 3600000;
  static const int DAY_IN_MILLIS = 86400000;

  static String underlineSeparated(String s) {
    var res = s.split(' ').map((w) => w?.toLowerCase() ?? '').join('_').trim();
    return res.isNotEmpty ? res : 'n/a';
  }

  static String toSnakeCase(String input) {
    return input.replaceAllMapped(RegExp(r'(?<=[a-zA-Z0-9])[A-Z]'), (match) {
      return '_${match.group(0)!.toLowerCase()}';
    });
  }


  static List<Value> getDisplayMeasurementValue(Measurement? data) {
    List<Value> value = [];
    if (data == null) return value;
    final type = data.dataType;
    switch (type) {
      // case DataType.SKIN_CONTACT:
      //   var v = data.getMainValue().firstWhereOrNull((val) =>
      //   val.name == 'skin_contact');
      //
      //   value = v?.value == 3 ? 'Skin detected' : 'Off Skin';
      //   break;
      default:
        // value = data.getMainValue();
        value = data.getAllValues();
        var t = Value('timestamp', '', data.time, false);
        value.add(t);
    }
    return value;
  }

  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  static List<Measurement> generateDailyMeasurements(String deviceAddress) {
    List<Measurement> measurements = [];
    DateTime now = DateTime.now();
    DateTime start = DateTime(now.year, now.month, now.day, 0, 0, 0); // Midnight

    Random random = Random();
    Map<int, int> stepData = {};

    // Generate step data per hour with realistic patterns
    for (int i = 0; i < 24; i++) {
      DateTime timestamp = start.add(Duration(hours: i));
      int epochTime = timestamp.millisecondsSinceEpoch;

      int steps;

      if (i < 5) {
        steps = 0; // Low activity before 6 AM
      } else if (i < 6) {
        steps = random.nextInt(50); // Low activity before 6 AM
      } else if (i >= 8 && i <= 10 || i >= 17 && i <= 20) {
        steps = random.nextInt(400) + 800; // High activity peak times (800-1200)
      } else if (i >= 12 && i <= 13) {
        steps = random.nextInt(300) + 500; // Midday activity (500-800)
      } else {
        steps = random.nextInt(200) + 100; // General activity (100-300)
      }

      stepData[i] = steps;

      measurements.add(
        Measurement(DataType.STEPS, deviceAddress, values: [
          Value("steps", "count", steps, true),
        ], time: epochTime),
      );
    }

    debugPrint('-------------------------stepData  ${stepData.values.sum}');
    var min = 1000;
    var max = -1;
    // Generate heart rate, SpO2, and IBI every 15 minutes
    for (int i = 0; i < 96; i++) {
      DateTime timestamp = start.add(Duration(minutes: i * 15));
      int epochTime = timestamp.millisecondsSinceEpoch;
      int hour = timestamp.hour;

      // Determine step influence (more steps = higher HR)
      int stepCount = stepData[hour] ?? 0;
      double activityFactor = (stepCount / 1200).clamp(0, 1); // Normalize step impact (0-1)

      // Adjust heart rate based on steps
      int baseHeartRate = 60 + random.nextInt(10); // Baseline HR (60-70)
      int activityBoost = (activityFactor * 40).round(); // Max +40 bpm if very active
      int heartRate = baseHeartRate + activityBoost;
      if(heartRate < min) {
        min = heartRate;
      }
      if(heartRate > max) {
        max = heartRate;
      }
      // Calculate IBI (inverse relation to HR)
      int ibi = (60000 / heartRate).round(); // In milliseconds

      // Stable SpO2 values (97-99%)
      int spo2 = 97 + random.nextInt(3); // 97-99%

      measurements.add(
        Measurement(DataType.HEART_RATE, deviceAddress, values: [
          Value("heart_rate", "bpm", heartRate, true),
        ], time: epochTime),
      );

      measurements.add(
        Measurement(DataType.SPO2, deviceAddress, values: [
          Value("spo2", "%", spo2, true),
        ], time: epochTime),
      );

      measurements.add(
        Measurement(DataType.R2R_INTERVALS, deviceAddress, values: [
          Value("ibi", "ms", ibi, true),
        ], time: epochTime),
      );
    }

    debugPrint('-------------------------heartRate  $max $min');

    return measurements;
  }


}
