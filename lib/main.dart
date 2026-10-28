import 'package:collection/collection.dart';
import 'package:dca/src/fall_detection/fall_detection.dart';
import 'package:dca/src/providers/influx_provider.dart';
import 'package:dca/src/screens/data_plot_screen.dart';
import 'package:dca/src/screens/home_screen.dart';
import 'package:fhir/r4/resource_types/base/individuals/individuals.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart'; // Import this!
import 'package:intl/intl.dart';

// Fall alerts and counts: one instance per running app (each browser tab).
final fallDetection = FallDetectionServices.fromEnvironment();
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure async execution
  await initializeDateFormatting('de_DE', null); // Initialize locale
  fallDetection.start(); // connects in the background and reconnects by itself
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider<InfluxProvider>(create: (_) => InfluxProvider()),],
        child: MaterialApp(
      title: '6G Path Dashboard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      // Above the Navigator, so fall popups show on every page and dialog.
      builder: (context, child) => FallDetectionScope(
        services: fallDetection,
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        patientLabel: (patientId) {
          final patient = _findPatient(context, patientId);
          return patient == null ? patientId : patientDisplayName(patient);
        },
        onOpenPatient: (patientId) => _openPatient(context, patientId),
        child: child!,
      ),
      home: const HomeScreen(),
    ));
  }

  static Patient? _findPatient(BuildContext context, String patientId) => context
      .read<InfluxProvider>()
      .patients
      .firstWhereOrNull((p) => patientIdOf(p) == patientId);

  static void _openPatient(BuildContext context, String patientId) {
    final navigator = navigatorKey.currentState;
    final patient = _findPatient(context, patientId);
    if (navigator == null || patient == null) return;
    // Don't stack a second page if this patient's page is already on top.
    String? current;
    navigator.popUntil((route) {
      current = route.settings.name;
      return true;
    });
    if (current == patientRouteName(patientId)) return;
    navigator.push(MaterialPageRoute(
      settings: RouteSettings(name: patientRouteName(patientId)),
      builder: (_) => DataPlotsScreen(user: patient),
    ));
  }
}
