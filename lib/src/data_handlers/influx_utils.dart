
enum AggregationType {
  mean,
  first,
  last,
  median,
  min,
  max,
  sort,
  unique,
  stddev
}

enum OperationType {
  equal,
  greater,
  greaterEqual,
  less,
  lessEqual,
  notEqual;

  String get symbol {
    switch (this) {
      case OperationType.equal:
        return '==';
      case OperationType.greater:
        return '>';
      case OperationType.greaterEqual:
        return '>=';
      case OperationType.less:
        return '<';
      case OperationType.lessEqual:
        return '<=';
      case OperationType.notEqual:
        return '!=';
    }
  }
}

final List<String> exclude = [
  'rrconf',
  'id'
];

class Aggregation {
  AggregationType type;
  Duration interval;

  Aggregation(this.type, this.interval);

  @override
  String toString() {
    return '$type, $interval';
  }
}

class Tag {
  OperationType type;
  String key;
  dynamic value;

  Tag({this.type = OperationType.equal, required this.key, required this.value});

  @override
  String toString() {
    return 'key: $key, value: $value';
  }
}

class FetchDataParams {
  final Duration? range;
  final DateTime? start;
  final DateTime? stop;
  final String field;
  final String aggregationMethod;
  final Duration interval;
  final List<Tag> tags;
  final bool publish;

  FetchDataParams({
    this.range,
    this.start,
    this.stop,
    required this.field,
    required this.aggregationMethod,
    required this.interval,
    this.tags = const [],
    this.publish = false,
  });
}
class AggregatedDataParams {
  final Duration range;
  final DateTime? start;
  final DateTime? stop;
  final String field;
  final List<String>? fields;
  final List<Tag> tags;
  final List<Aggregation> aggregations;
  final bool publish;
  final bool startOfDay;

  AggregatedDataParams({
    this.range = const Duration(days: 1),
    this.start,
    this.stop,
    required this.field,
    this.fields,
    this.tags = const [],
    required this.aggregations,
    this.publish = true,
    this.startOfDay = false,
  });
}