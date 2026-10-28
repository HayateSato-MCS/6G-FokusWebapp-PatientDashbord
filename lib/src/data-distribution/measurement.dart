import 'dart:convert';
import '../../../src/data-distribution/data_source_type.dart';
import '../utils/data_util.dart';

class Measurement extends Transmission {
  @override
  dynamic dbID = -1;

  String deviceAddress;

  @override
  Measurement(DataType? dataType, this.deviceAddress, {List<Value>? values, int? time}) {
    if (values != null) {
      this.values = values;
    }if (time != null) {
      this.time = time;
    } else {
      setTime(DateTime.now().millisecondsSinceEpoch);
    }
    deviceAddress = deviceAddress;
    this.dataType = dataType ?? DataType.ANY;
  }

  int getDBId() {
    return dbID;
  }

  void setDBId(int id) {
    dbID = id;
  }

  @override
  DataType getDataType() {
    return dataType;
  }

  void setDataType(DataType type) {
    dataType = type;
  }

  @override
  int getTimeReceived() {
    return time;
  }

  @override
  String getId() {
    return getDeviceAddress();
  }

  void addValue(Value value) {
    values ??= [];
    value.value ??= 0;
    values?.add(value);
   }

  void addValues(List<Value> values) {
    values ??= [];
    values.addAll(values);
    }

  void setValue(List<Value> values) {
    this.values = values;
  }

  void setTime(int time) {
    this.time = time;
  }

  String getDeviceAddress() {
    return deviceAddress;
  }

  String getName() {
    return dataType.name;
  }

  @override
  List getValue() {
    return values as List;
  }

  List<Value> getAllValues() {
    final result = <Value>[];
    if (values != null) {
      for (var val in values) {
          result.add(val);
      }
    }
    return result;
  }

  @override
  String toJson() {
    return jsonEncode({
      'time': time,
      'value': (values).map((e) => e.toJson()).toList(),
      'dataType': dataType.name,
      'deviceAddress': deviceAddress,
    });
  }

  static Transmission fromJson(String json) {
    var mJson = jsonDecode(json);
    var dataType =
        DataType.values.firstWhere((el) => el.name == mJson['dataType']);
    Measurement m = Measurement(dataType, '');
    m.time = mJson['time'];
    m.values = mJson['value'] != null
        ? (mJson['value'] as List).map((e) => Value.fromJson(e)).toList()
        : [];
    m.deviceAddress = mJson['deviceAddress'];
    return m;
  }

  @override
  void addTag(String reason) {
    tags.add(reason);
  }
}

class Value {
  String name;
  String unit;
  dynamic value;
  bool main;

  Value(this.name, this.unit, this.value, this.main);

  @override
  String toString() {
    return '($name, $unit, $value, $main)';
  }

  factory Value.fromJson(Map<String, dynamic> json) {
    return Value(
      json['name'] as String,
      json['unit'] as String,
      json['value'],
      json['main'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'name': name,
      'unit': unit,
      'value': value,
      'main': main,
    };
    return data;
  }
}

class MeasurementLabel {
  String name;
  String value;

  MeasurementLabel(this.name, this.value);

  factory MeasurementLabel.fromJson(Map<String, dynamic> json) {
    return MeasurementLabel(
      json['name'] as String,
      json['value'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'name': name,
      'value': value,
    };
    return data;
  }

  @override
  String toString() {
    return '''
    name: $name,
    value: $value''';
  }
}
