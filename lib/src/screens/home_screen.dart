import 'package:dca/src/screens/components/user_data_item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/influx_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final users = context.watch<InfluxProvider>().patients;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Übersicht der Patient:innen'),
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
