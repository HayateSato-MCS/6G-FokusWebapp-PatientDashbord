import 'dart:async';
import 'package:collection/collection.dart';
import 'package:dca/src/data-distribution/data_source_type.dart';
import 'package:dca/src/data_handlers/fhir_handler.dart';
import 'package:dca/src/data_handlers/fhir_utils.dart';
import 'package:dca/src/data_handlers/influx_db_handler.dart';
import 'package:dca/src/data_handlers/influx_utils.dart';
import 'package:dca/src/utils/data_handler.dart';
import 'package:fhir/r4/resource_types/base/individuals/individuals.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InfluxProvider with ChangeNotifier {
  final InfluxDBHandler _handler = InfluxDBHandler.getInstance();
  final FhirHandler _fhirHandler = FhirHandler();
  List<Patient> _patients = [];
  static bool shouldFetchStatic = true;
  bool _shouldFetch = true;

  List<Patient> get patients => _patients;
  bool get shouldFetch => _shouldFetch;

  InfluxProvider() {
    init();
  }

  init() {
    debugPrint(
        '--------------------------------- InfluxProvider init  -------------------------------');
    DataHandler.getUsers().then((value) {
      var pa = Patient.fromJson({'fhirId': 'smartDataApp'});
      if (value.isNotEmpty) {
        _patients = [pa.copyWith(fhirId: 'smartDataApp')];
        notifyListeners();
      }
      fetchDataPeriodically();

    });
  }


  void fetchPatients() async {
    if (!shouldFetch) return;

    var fhirPatients = await _fhirHandler.fetchPatients();
    // fhirPatients.add(pa);
    debugPrint(
        '--------------------------------- InfluxProvider fetchDataPeriodically  ------------------------------- $fhirPatients');
    if (fhirPatients.isNotEmpty) {
      var ids = fhirPatients.map((e) => e.fhirId.toString());
      _patients = _patients.whereNot((p) => ids.contains(p.fhirId.toString())).toList();
      _patients.addAll(fhirPatients);
      notifyListeners();
      // DataHandler.setUsers(_patients.whereNot((p) => p.fhirId != 'smartDataApp').toList());
    }
  }

  void fetchDataPeriodically() {
    fetchPatients();
    Timer.periodic(const Duration(seconds: 60), (timer) async {
      try {
        fetchPatients();
      } catch (e) {
        debugPrint(e.toString());
      }
    });
  }

  void setShouldFetch(state) {
    if (_shouldFetch != state) {
      _shouldFetch = state;
      notifyListeners();
    }
  }

  static InfluxProvider of(BuildContext context) {
    return Provider.of<InfluxProvider>(context, listen: false);
  }
}
