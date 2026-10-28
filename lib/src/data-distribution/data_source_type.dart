import 'dart:convert';


enum SourceType {
  ANY,
  INFLUX_DB,
  FHIR_SERVER,
  SMARKO_DEVICE,
  PHONE,
}

enum DataType {
  ANY,
  HEART_RATE,
  SPO2,
  ECG,
  PPG,
  ACCELEROMETER,
  GYROSCOPE,
  MAGNETOMETER,
  ACCELEROMETER_BOSCH,
  GYROSCOPE_BOSCH,
  MAGNETOMETER_BOSCH,
  HUMIDITY,
  BATTERY,
  SKIN_CONTACT,
  STEPS,
  STEPS_BOSCH,
  SKIN_TEMPERATURE,
  NTC_TEMPERATURE,
  UNKNOWN,
  WORKOUT_COMPACT,
  EDA,
  ACTIVITY,
  R2R_INTERVALS;

  String toJson() => name;
  static DataType fromJson(String json) => values.byName(json);
}

extension DataTypeExtension on DataType {
  String get value {
    switch (this) {
      case DataType.ANY:
        return 'any';
      case DataType.HEART_RATE:
        return 'heart_rate';
      case DataType.SPO2:
        return 'blood_oxygen';
      case DataType.ECG:
        return 'ecg';
      case DataType.PPG:
        return 'ppg';
      case DataType.ACCELEROMETER:
        return 'accelerometer';
      case DataType.GYROSCOPE:
        return 'gyroscope';
      case DataType.MAGNETOMETER:
        return 'magnetometer';
      case DataType.ACCELEROMETER_BOSCH:
        return 'accelerometer_bosh';
      case DataType.GYROSCOPE_BOSCH:
        return 'gyroscope_bosh';
      case DataType.MAGNETOMETER_BOSCH:
        return 'magnetometer_bosh';
      case DataType.HUMIDITY:
        return 'humidity';
      case DataType.BATTERY:
        return 'battery';
      case DataType.SKIN_CONTACT:
        return 'skin_contact';
      case DataType.STEPS:
        return 'steps';
      case DataType.STEPS_BOSCH:
        return 'steps_bosch';
      case DataType.SKIN_TEMPERATURE:
        return 'skin_temperature';
      case DataType.NTC_TEMPERATURE:
        return 'ntc_temperature';
      case DataType.WORKOUT_COMPACT:
        return 'workout_compact';
      case DataType.EDA:
        return 'eda';
      case DataType.ACTIVITY:
        return 'activity';
      case DataType.R2R_INTERVALS:
        return 'rr_intervals';
      case DataType.UNKNOWN:
        return 'unknown';
    }
  }
}

DataType getDataTypeFromValue(String value) {
  for (DataType dataType in DataType.values) {
    if (dataType.value == value) {
      return dataType;
    }
  }
  return DataType.UNKNOWN;
}

abstract class Transmission{
  late int time;
  dynamic values;
  late DataType dataType;
  Set<String> tags = {};

  int getTimeReceived();
  String getId();
  DataType getDataType();
  dynamic getValue();
  void addTag(String reason);

  String toJson() {
    return jsonEncode({
      'time': time,
      'value': values,
      'dataType': dataType,
    });
  }
}
