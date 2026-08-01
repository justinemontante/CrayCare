import 'package:flutter/material.dart';
import 'actuator_group.dart';

class ActuatorsTab extends StatelessWidget {
  final Map<String, String> actuatorModes;
  final void Function(String actuatorId, String mode) onSetActuatorMode;
  final void Function(
    BuildContext context,
    String label,
    List<(String, String, String, String?)> actuators,
  ) onShowGroupLog;
  final Map<String, String> actuatorRuntimeLabels;

  final bool isOnline;

  const ActuatorsTab({
    super.key,
    required this.actuatorModes,
    required this.onSetActuatorMode,
    required this.onShowGroupLog,
    required this.actuatorRuntimeLabels,
    this.isOnline = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActuatorGroup(
            label: 'Aeration',
            icon: Icons.air,
            actuators: const [
              ('aerator1', 'Aerator 1', 'Air Pump', 'assets/images/aerator.png'),
              ('aerator2', 'Aerator 2', 'Air Pump', 'assets/images/aerator.png'),
            ],
            actuatorModes: actuatorModes,
            onSetActuatorMode: onSetActuatorMode,
            onShowGroupLog: onShowGroupLog,
            actuatorRuntimeLabels: actuatorRuntimeLabels,
            isOnline: isOnline,
          ),
          const SizedBox(height: 14),
          ActuatorGroup(
            label: 'Filtration',
            icon: Icons.water_drop,
            actuators: const [
              ('pump', 'Water Pump', 'For Filtration System', 'assets/images/waterPump.png'),
            ],
            actuatorModes: actuatorModes,
            onSetActuatorMode: onSetActuatorMode,
            onShowGroupLog: onShowGroupLog,
            actuatorRuntimeLabels: actuatorRuntimeLabels,
            isOnline: isOnline,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
