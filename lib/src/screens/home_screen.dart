import 'package:dca/src/screens/components/user_data_item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fall_detection/fall_detection.dart';
import '../providers/influx_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final users = context.watch<InfluxProvider>().patients;
    final fallDetection = FallDetectionScope.maybeOf(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Übersicht der Patient:innen'),
        actions: [
          // live fall-alert connection, so caregivers see when alerts can't arrive
          if (fallDetection != null)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Center(child: MqttStatusChip(service: fallDetection.mqtt)),
            ),
        ],
      ),
      body: ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return UserDataItem(user: user);
        },
      ),
    );
  }
}
