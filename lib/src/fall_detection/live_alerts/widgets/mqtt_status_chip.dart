import 'package:flutter/material.dart';

import '../../ui/fall_colors.dart';
import '../fall_mqtt_service.dart';

/// "Live status: Connected / Disconnected" indicator for the broker link.
class MqttStatusChip extends StatelessWidget {
  const MqttStatusChip({super.key, required this.service});

  final FallMqttService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MqttLinkState>(
      stream: service.linkStates,
      initialData: service.linkState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? MqttLinkState.disconnected;
        final (label, color) = switch (state) {
          MqttLinkState.connected => ('Connected', FallColors.connected),
          MqttLinkState.connecting => ('Connecting...', FallColors.textMuted),
          MqttLinkState.reconnecting => ('Reconnecting...', FallColors.textMuted),
          MqttLinkState.disconnected => ('Disconnected', FallColors.disconnected),
        };
        return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600));
      },
    );
  }
}
