import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
// import 'package:dca/src/data_handlers/fhir_utils.dart';
import 'package:dca/src/utils/data_handler.dart';
import 'package:fhir/r4/resource_types/base/individuals/individuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;

import '../../mcs_dashboard_tab.dart';
import '../environment.dart';

class FhirHandler {
  final String fhirServerUrl = MCSDashboardEnvironment.fhirBaseUrl;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  FhirHandler();

  Future<Map<String, dynamic>> fetchResource(String type, [int? id]) async {
    final request = html.HttpRequest();
    String url = fhirServerUrl + type + (id != null ? '/$id' : '');
    request.open('GET', url);

    debugPrint(
        '1--------------------------------- FhirHandler fetchResource  ------------------------------- $url');
    // Read the access token from secure storage
    var accessToken = await _storage.read(key: MCSDashboardEnvironment.keyAccessToken);

    debugPrint(
        '2--------------------------------- FhirHandler fetchResource  ------------------------------- $accessToken');
    request.setRequestHeader(MCSDashboardEnvironment.headerKeyAuthorization,
        // MCSDashboardEnvironment.headerValuePrefixBearer + accessToken.toString());
        'SuP3rS3Cr37AcCe55T0k3n');
    request.setRequestHeader(
        MCSDashboardEnvironment.headerKeyCacheControl, MCSDashboardEnvironment.headerValueCacheControlNoCache);
    final completer = Completer<Map<String, dynamic>>(); // Completer to handle async logic
    request.onLoad.listen((_) {
      debugPrint(
          '2.5--------------------------------- FhirHandler fetchResource  ------------------------------- ${request.status}');

      if (request.status == 200) {
        try {
          var resource = jsonDecode(request.responseText ?? '{}');
          // debugPrint('FHIR Resource: $resource');
          completer.complete(resource); // Return data on success
        } catch (e) {
          completer.completeError(Exception('Failed to parse JSON: $e'));
        }
      } else {
        completer.completeError(Exception('Failed to load FHIR data: ${request.status}'));
      }
    });

    debugPrint(
        '3--------------------------------- FhirHandler fetchResource  -------------------------------');
    request.onError.listen((err) {
      completer.completeError(Exception('CORS Error: Unable to fetch data: ${err}'));
    });

    request.send();

    return completer.future; // Return the future that completes when request finishes
  }

  Future<List<Patient>> fetchPatients() async {
    debugPrint(
        '1--------------------------------- FhirHandler fetchPatients  ------------------------------- ');

    final patientBundle = await fetchResource('Patient');
    debugPrint(
        '2 --------------------------------- FhirHandler fetchPatients  ------------------------------- $patientBundle');

    List<dynamic> patients = patientBundle['entry']!.map((entry) {
      var p = entry['resource'];
      var patient = Patient.fromJson(p);
      return patient;
    }).toList();
    debugPrint(
        '3 --------------------------------- FhirHandler fetchPatients  ------------------------------- $patients');

    return (patients as List).cast<Patient>();
  }

  Future<List<TaskMetaData>> fetchAllTasksMetadata() async {
    String params = 'Task?intent=proposal&status=draft';
    final tasksBundle = await fetchResource(params);
    List<TaskMetaData> tasks = tasksBundle['entry']!.map((entry) {
      var r = entry['resource'];
      return extractTaskMetaData(r);
    }).toList();
    return (tasks as List).cast<TaskMetaData>();
  }

  Future<TaskMetaData> fetchTaskMetadata(id) async {
    String params = 'Task/$id';
    TaskMetaData? tm = await DataHandler.getTaskMetadata(id);
    if (tm != null) {
      return tm;
    }
    final taskResource = await fetchResource(params);
    return extractTaskMetaData(taskResource);
  }

  TaskMetaData extractTaskMetaData(taskResource) {
    String id = taskResource['id'];
    String name = '';
    String icon = '';
    List<dynamic> list = taskResource['input'] ?? [];
    if (list.isNotEmpty) {
      var nameItem = list.firstWhereOrNull((l) => l['type']!['coding']![0]!['code'] == '1');
      if (nameItem != null) {
        name = nameItem['valueString'];
      }
      var iconItem = list.firstWhereOrNull((l) => l['type']!['coding']![0]!['code'] == '2');
      if (iconItem != null) {
        icon = iconItem['valueAttachment']!['data'];
      }
    }
    var task = TaskMetaData(id: id, name: name, icon: icon);
    DataHandler.setTaskMetadata(id, task);
    return task;
  }

  Future<List<Workout>> fetchWorkouts(String patient, DateTime start) async {
    String params =
        'Task?subject=Patient/$patient&period=${DateFormat('yyyy-MM-dd').format(start)}';
    final taskResultBundle = await fetchResource(params);
    List<Map<String, String>> workoutData = [];
    taskResultBundle['entry']?.forEach((entry) {
      var r = entry['resource'];
      String id = r['id'];
      String start = r['executionPeriod']!['start'];
      String end = r['executionPeriod']!['end'];
      Map<String, String> res = <String, String>{
        'id': id,
        'ref': r['partOf']![0]['reference']!,
        'start': start,
        'end': end
      };
      workoutData.add(res);
    });
    List<Workout> workouts = [];
    for (var wd in workoutData) {
      String ref = wd['ref']!;
      DateTime start = DateTime.parse(wd['start']!);
      DateTime end = DateTime.parse(wd['end']!);
      String id = wd['id']!;
      final task = await fetchResource(ref);
      final taskDataID = task['partOf']![0]['reference']!.replaceAll('Task/', '');
      TaskMetaData taskData = await fetchTaskMetadata(taskDataID);
      Workout workout =
          Workout(id: id, name: taskData.name, start: start, end: end, icon: taskData.icon);
      workouts.add(workout);
    }
    return workouts;
  }
}
