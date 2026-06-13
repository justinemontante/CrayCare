import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class HardwareGroup extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<(String, String, String, String?)> devices;
  final Map<String, String> hwModes;
  final void Function(String deviceId, String mode) onSetMode;
  final void Function(
    BuildContext context,
    String label,
    List<(String, String, String, String?)> devices,
  ) onShowGroupLog;
  final Map<String, String> deviceRuntimeLabels;

  final bool isOwner;

  const HardwareGroup({
    super.key,
    required this.label,
    required this.icon,
    required this.devices,
    required this.hwModes,
    required this.onSetMode,
    required this.onShowGroupLog,
    required this.deviceRuntimeLabels,
    this.isOwner = true,
  });

  @override
  Widget build(BuildContext context) {
    final firstId = devices.isNotEmpty ? devices.first.$1 : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.03),
        border: Border.all(color: AppColors.darkWith(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkWith(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => onShowGroupLog(context, label, devices),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryWith(0.1),
                    border: Border.all(color: AppColors.primaryWith(0.2)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book, size: 10, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Log',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...devices.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildHwCard(d.$1, d.$2, d.$3, d.$4, context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHwCard(
    String deviceId,
    String title,
    String subtitle,
    String? imageAsset,
    BuildContext context,
  ) {
    final mode = hwModes[deviceId] ?? 'auto';
    final borderColor = mode == 'on'
        ? AppColors.primaryWith(0.4)
        : mode == 'auto'
        ? AppColors.warning.withValues(alpha: 0.35)
        : AppColors.darkWith(0.1);
    final iconColor = mode == 'on'
        ? AppColors.primary
        : mode == 'auto'
        ? AppColors.warning
        : AppColors.darkWith(0.4);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0f000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                children: [
                  if (imageAsset != null)
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.asset(
                          imageAsset,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.air, size: 18, color: iconColor),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.darkWith(0.4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildRuntimeIndicator(deviceId),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _buildHwModeToggle(deviceId, mode, context),
                    ),
                  ),
                ],
              ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuntimeIndicator(String deviceId) {
    final runtime = deviceRuntimeLabels[deviceId];
    if (runtime == null || runtime.isEmpty) return const SizedBox.shrink();

    final mode = hwModes[deviceId] ?? 'auto';
    final color = mode == 'on'
        ? AppColors.primary
        : mode == 'auto'
        ? AppColors.warning
        : AppColors.darkWith(0.4);

    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 10, color: color),
        const SizedBox(width: 4),
        Text(
          'Running: ',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w400,
            color: AppColors.darkWith(0.5),
          ),
        ),
        Text(
          runtime,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildHwModeToggle(String deviceId, String currentMode, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['off', 'auto', 'on'].map((m) {
          final isActive = m == currentMode;
          return GestureDetector(
            onTap: () {
              if (isOwner) {
                onSetMode(deviceId, m);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Control denied: Only owners can control hardware devices.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                m.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive ? _modeColor(m) : AppColors.darkWith(0.4),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'on':
        return AppColors.primary;
      case 'auto':
        return AppColors.warning;
      case 'off':
        return AppColors.critical;
      default:
        return AppColors.darkWith(0.4);
    }
  }
}
