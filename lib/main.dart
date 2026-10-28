import 'package:dca/src/providers/influx_provider.dart';
import 'package:dca/src/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart'; // Import this!
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure async execution
  await initializeDateFormatting('de_DE', null); // Initialize locale
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
      home: const HomeScreen(),
    ));
  }
}