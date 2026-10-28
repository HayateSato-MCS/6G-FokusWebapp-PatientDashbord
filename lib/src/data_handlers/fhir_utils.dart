
class User {
  String id;
  String familyName;
  List<String> nameList;

  User({required this.id, required this.familyName, this.nameList = const []});

  /// Convert User object to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyName': familyName,
      'nameList': nameList,
    };
  }

  static User fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      familyName: json['familyName'] as String,
      nameList: List<String>.from(json['nameList'] ?? []),
    );
  }

  @override
  String toString() {
    return '$id - $familyName, ${nameList.join(' ')}';
  }
}

// class Patient extends User {
//   Patient({required super.id, required super.familyName, super.nameList = const []});
//
//   static Patient fromJson(Map<String, dynamic> json) {
//     return Patient(
//       id: json['id'] as String,
//       familyName: json['familyName'] as String,
//       nameList: List<String>.from(json['nameList'] ?? []),
//     );
//   }
// }

class Workout {
  String id;
  String name;
  DateTime start;
  DateTime end;
  String icon;

  Workout({required this.id, required this.name, required this.start, required this.end, required this.icon});

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'icon': icon,
    };
  }

  factory Workout.fromJson(Map<String, dynamic> json) {
    return Workout(
      id: json['id'],
      name: json['name'],
      start: DateTime.parse(json['start']),
      end: DateTime.parse(json['end']),
      icon: json['icon'],
    );
  }

  @override
  String toString() {
    return '$id - $name [$start, $end]';
  }
}

class TaskMetaData {
  String id;
  String name;
  String icon;

  TaskMetaData({required this.id, required this.name, required this.icon});

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
    };
  }

  factory TaskMetaData.fromJson(Map<String, dynamic> json) {
    return TaskMetaData(
      id: json['id'],
      name: json['name'],
      icon: json['icon'],
    );
  }

  @override
  String toString() {
    return '$id - $name';
  }
}