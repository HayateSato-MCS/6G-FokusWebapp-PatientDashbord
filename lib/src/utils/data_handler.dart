import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dca/src/data_handlers/fhir_utils.dart';
import 'package:fhir/r4/resource_types/base/individuals/individuals.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DataHandler {

  static const KEY_USERS = 'KEY_USERS';
  static const KEY_TASK_IDS = 'KEY_TASK_IDS';
  static const KEY_TASK_METADATA = 'KEY_TASK_METADATA';


  static Future<bool> store(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, json.encode(value));
      return true;
    } catch (error) {
      debugPrint('DataHandler store error $error, key $key, $value');
    }
    return false;
  }

  static Future<dynamic> retrieve(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(key);
      return value != null ? json.decode(value) : null;
    } catch (error) {
      debugPrint('DataHandler retrieve error $error');
    }
  }

  static Future<dynamic> clearData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.clear();
    } catch (error) {
      debugPrint('DataHandler clearData error $error');
    }
  }

  static Future<dynamic> removeData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.remove(key);
    } catch (error) {
      debugPrint('DataHandler removeData error $error');
    }
  }

  static Future<List<Patient>> getUsers() async {
    try {
      var res = await retrieve(KEY_USERS) ?? [];
        if((res as List).isNotEmpty && res[0] is String) {
             await removeData(KEY_USERS);
        res = [];
      }
      return res.map((e) => Patient.fromJson(e))
          .toList();
    } catch (error) {
      throw error;
    }
  }

  static Future<bool> setUsers(List<Patient> users) async {
    try {
      return await store(KEY_USERS, users);
    } catch (error) {
      throw error;
    }
  }

  static Future<bool> addUsers(List<Patient> users) async {
    List<Patient> savedUsers = await getUsers();
    var ids = users.map((e) => e.fhirId.toString());
    savedUsers = savedUsers.whereNot((p) => ids.contains(p.fhirId.toString())).toList();
    savedUsers.addAll(users);
    try {
      return await store(KEY_USERS, savedUsers);
    } catch (error) {
      throw error;
    }
  }

  static Future<List<String>> getStoredTaskIds() async {
    try {
      var res = await retrieve(KEY_TASK_IDS) ?? [];
           return (res as List).cast<String>();
    } catch (error) {
      throw error;
    }
  }

  static Future<bool> setStoredTaskIds(List<String> taskIds) async {
    try {
      return await store(KEY_TASK_IDS, taskIds);
    } catch (error) {
      throw error;
    }
  }

  static Future<TaskMetaData?> getTaskMetadata(id) async {
    try {
      var res = await retrieve(KEY_TASK_METADATA+id);
          return res != null ? TaskMetaData.fromJson(res) : null;
    } catch (error) {
      throw error;
    }
  }

  static Future<bool> setTaskMetadata(id, metadata) async {
    try {
      var ids = await getStoredTaskIds();
      await setStoredTaskIds(<String>{...ids, id}.toList());
      return await store(KEY_TASK_METADATA + id, metadata);
    } catch (error) {
      throw error;
    }
  }
}
