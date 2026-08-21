import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class NotifSettings extends StatefulWidget {
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
  State<NotifSettings> createState() => _NotifSettingsState();
}

class _NotifSettingsState extends State<NotifSettings> {
  late bool _notifSound;
  late bool _notifVibration;
  late bool _notifCritical;
  late bool _notifWarning;
  late bool _notifFeeding;
  late bool _notifSampling;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant NotifSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromWidget();
  }

  void _syncFromWidget() {
    _notifSound = widget.notifSound;
    _notifVibration = widget.notifVibration;
    _notifCritical = widget.notifCritical;
    _notifWarning = widget.notifWarning;
    _notifFeeding = widget.notifFeeding;
    _notifSampling = widget.notifSampling;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIntroCard(),
            const SizedBox(height: 24),
            _buildSectionLabel(Icons.settings_outlined, 'GENERAL'),
            const SizedBox(height: 10),
            _buildToggleGroup([
              _NotifItem(
                label: 'Notification Sound',
                subtitle: 'Play a sound for incoming alerts',
                icon: Icons.volume_up_rounded,
                color: AppColors.primary,
                value: _notifSound,
                onChanged: (value) {
                  setState(() => _notifSound = value ?? true);
                  widget.onNotifSoundChanged(value);
                },
              ),
              _NotifItem(
                label: 'Vibration',
                subtitle: 'Vibrate for important updates',
                icon: Icons.vibration_rounded,
                color: AppColors.primary,
                value: _notifVibration,
                onChanged: (value) {
                  setState(() => _notifVibration = value ?? true);
                  widget.onNotifVibrationChanged(value);
                },
              ),
            ]),
            const SizedBox(height: 24),
            _buildSectionLabel(Icons.notifications_active_outlined, 'ALERTS & REMINDERS'),
            const SizedBox(height: 10),
            _buildToggleGroup([
              _NotifItem(
                label: 'Critical Alerts',
                subtitle: 'Urgent changes in water parameters',
                icon: Icons.error_outline_rounded,
                color: AppColors.critical,
                value: _notifCritical,
                onChanged: (value) {
                  setState(() => _notifCritical = value ?? true);
                  widget.onNotifCriticalChanged(value);
                },
              ),
              _NotifItem(
                label: 'Warning Alerts',
                subtitle: 'Parameters approaching unsafe levels',
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                value: _notifWarning,
                onChanged: (value) {
                  setState(() => _notifWarning = value ?? true);
                  widget.onNotifWarningChanged(value);
                },
              ),
              _NotifItem(
                label: 'Feeding Reminders',
                subtitle: 'Daily feeding confirmations and reminders',
                icon: Icons.set_meal_rounded,
                color: AppColors.primary,
                value: _notifFeeding,
                onChanged: (value) {
                  setState(() => _notifFeeding = value ?? true);
                  widget.onNotifFeedingChanged(value);
                },
              ),
              _NotifItem(
                label: 'Sampling Schedule',
                subtitle: 'Weekly growth tracking reminders',
                icon: Icons.calendar_month_rounded,
                color: AppColors.primary,
                value: _notifSampling,
                onChanged: (value) {
                  setState(() => _notifSampling = value ?? true);
                  widget.onNotifSamplingChanged(value);
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    final enabledCount = [
      _notifSound,
      _notifVibration,
      _notifCritical,
      _notifWarning,
      _notifFeeding,
      _notifSampling,
    ].where((enabled) => enabled).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.055),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.notifications_none_rounded, color: AppColors.primary, size: 25),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stay informed',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
                ),
                const SizedBox(height: 3),
                Text(
                  '$enabledCount of 6 notification options enabled',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.subtitleText),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$enabledCount/6 ON',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: 0.35,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: AppColors.primary.withValues(alpha: 0.14))),
      ],
    );
  }

  Widget _buildToggleGroup(List<_NotifItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.darkWith(0.05)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.045),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          return Column(
            children: [
              _buildToggleRow(items[index]),
              if (index < items.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 68, right: 16),
                  child: Divider(height: 1, thickness: 1, color: AppColors.darkWith(0.06)),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildToggleRow(_NotifItem item) {
    return InkWell(
      onTap: () => item.onChanged(!item.value),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(item.icon, size: 21, color: item.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.subtitleText),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.76,
              child: Switch(
                value: item.value,
                onChanged: item.onChanged,
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primaryWith(0.24),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: AppColors.darkWith(0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifItem {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _NotifItem({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.value,
    required this.onChanged,
  });
}
