import 'package:flutter/material.dart';
import 'hardware_group.dart';

class DevicesTab extends StatelessWidget {
  final Map<String, String> hwModes;
  final void Function(String deviceId, String mode) onSetMode;
  final void Function(
    BuildContext context,
    String deviceId,
    String title,
    String subtitle,
  ) onShowLog;

  const DevicesTab({
    super.key,
    required this.hwModes,
    required this.onSetMode,
    required this.onShowLog,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HardwareGroup(
            label: 'Aeration',
            icon: Icons.air,
            devices: const [
              ('aerator1', 'Aerator', 'Air Pump', 'assets/images/aerator.png'),
            ],
            hwModes: hwModes,
            onSetMode: onSetMode,
            onShowLog: onShowLog,
          ),
          const SizedBox(height: 14),
          HardwareGroup(
            label: 'Filtration',
            icon: Icons.water_drop,
            devices: const [
              ('pump', 'Water Pump', 'Filtration System', 'assets/images/waterPump.png'),
            ],
            hwModes: hwModes,
            onSetMode: onSetMode,
            onShowLog: onShowLog,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
