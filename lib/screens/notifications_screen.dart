import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/notification_service.dart';
import '../models/notification_item.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _activeFilter = 'all';

  List<NotificationItem> get _filtered {
    final all = NotificationService.instance.notifications;
    if (_activeFilter == 'all') return all;
    return all.where((n) => n.type == _activeFilter).toList();
  }

  @override
  void initState() {
    super.initState();
    NotificationService.instance.addListener(_onNotifsChanged);
  }

  @override
  void dispose() {
    NotificationService.instance.removeListener(_onNotifsChanged);
    super.dispose();
  }

  void _onNotifsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final svc = NotificationService.instance;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildKpiRow(svc),
          _buildFilterRow(),
          _buildHeaderRow(),
          Expanded(child: _filtered.isEmpty ? _buildEmptyState() : _buildList()),
        ],
      ),
    );
  }

  Widget _buildKpiRow(NotificationService svc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _buildKpiCard('Total Today', '${svc.todayCount}', AppColors.primary),
          const SizedBox(width: 6),
          _buildKpiCard('Unread', '${svc.unreadCount}', AppColors.warning),
          const SizedBox(width: 6),
          _buildKpiCard('Critical', '${svc.criticalCount}', AppColors.critical),
          const SizedBox(width: 6),
          _buildKpiCard('Reminders', '${svc.reminderCount}', AppColors.warningDark),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkWith(0.12), width: 1.5),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.6), letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = ['all', 'critical', 'warning', 'operational', 'reminders'];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: filters.map((f) {
          final isActive = _activeFilter == f;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeFilter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.dark.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  f == 'all' ? 'All' : '${f[0].toUpperCase()}${f.substring(1)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? AppColors.primary
                        : AppColors.dark.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${_filtered.length} notification${_filtered.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final grouped = <String, List<NotificationItem>>{};
    for (var n in _filtered) {
      final key = _dateGroupKey(n.timestamp);
      grouped.putIfAbsent(key, () => []).add(n);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
              child: Text(entry.key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            ...entry.value.map((n) => _buildNotificationItem(n)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildNotificationItem(NotificationItem n) {
    final color = _typeColor(n.type);
    return GestureDetector(
      onTap: () {
        NotificationService.instance.markAsRead(n.id);
        _showDetail(n);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkWith(0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(_typeIcon(n.type), size: 14, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(n.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.dark))),
                      if (n.unread)
                        Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(n.message, style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.6)), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(_timeAgo(n.timestamp), style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_off_outlined, size: 48, color: AppColors.darkWith(0.15)),
          const SizedBox(height: 12),
          Text('No notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4))),
        ],
      ),
    );
  }

  void _showDetail(NotificationItem n) {
    final color = _typeColor(n.type);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(_typeIcon(n.type), size: 20, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
                          Text(_timeAgo(n.timestamp), style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.4))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.darkWith(0.08)),
                  ),
                  child: Text(n.message, style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.8), height: 1.5)),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'critical': return AppColors.critical;
      case 'warning': return AppColors.warning;
      case 'operational': return AppColors.primary;
      case 'reminder': return AppColors.warningDark;
      default: return AppColors.primary;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'critical': return Icons.warning_rounded;
      case 'warning': return Icons.info_outline;
      case 'operational': return Icons.check_circle_outline;
      case 'reminder': return Icons.notifications_outlined;
      default: return Icons.circle;
    }
  }

  String _dateGroupKey(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
