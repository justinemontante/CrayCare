import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class NotifSettings extends StatelessWidget {
  final bool notifSound;
  final bool notifVibration;
  final bool notifCritical;
  final bool notifWarning;
  final bool notifFeeding;
  final bool notifSampling;
  final ValueChanged<bool?> onNotifSoundChanged;
  final ValueChanged<bool?> onNotifVibrationChanged;
  final ValueChanged<bool?> onNotifCriticalChanged;
  final ValueChanged<bool?> onNotifWarningChanged;
  final ValueChanged<bool?> onNotifFeedingChanged;
  final ValueChanged<bool?> onNotifSamplingChanged;

  const NotifSettings({
    super.key,
    required this.notifSound,
    required this.notifVibration,
    required this.notifCritical,
    required this.notifWarning,
    required this.notifFeeding,
    required this.notifSampling,
    required this.onNotifSoundChanged,
    required this.onNotifVibrationChanged,
    required this.onNotifCriticalChanged,
    required this.onNotifWarningChanged,
    required this.onNotifFeedingChanged,
    required this.onNotifSamplingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFf7f7f7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMenuSection('General Settings', [
              _buildToggle(
                'Notification Sound',
                'Play sound for incoming alerts',
                notifSound,
                onNotifSoundChanged,
              ),
              _buildToggle(
                'Vibration',
                'Vibrate on important updates',
                notifVibration,
                onNotifVibrationChanged,
              ),
            ]),
            const SizedBox(height: 12),
            _buildMenuSection('Alerts & Reminders', [
              _buildToggle(
                'Critical Alerts',
                'Critical alerts for water parameters',
                notifCritical,
                onNotifCriticalChanged,
              ),
              _buildToggle(
                'Warning Alerts',
                'Warnings when parameters approach thresholds',
                notifWarning,
                onNotifWarningChanged,
              ),
              _buildToggle(
                'Feeding Reminders',
                'Confirmations for daily feeding',
                notifFeeding,
                onNotifFeedingChanged,
              ),
              _buildToggle(
                'Sampling Schedule',
                'Weekly growth tracking reminders',
                notifSampling,
                onNotifSamplingChanged,
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection(String label, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.darkWith(0.4),
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildToggle(
    String label,
    String subtitle,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.04)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.darkWith(0.4),
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primaryWith(0.2),
                inactiveTrackColor: AppColors.darkWith(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
