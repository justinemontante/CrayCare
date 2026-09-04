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
  static const _manilaOffset = Duration(hours: 8);
  String _activeFilter = 'all';

  List<NotificationItem> get _filtered {
    final all = NotificationService.instance.notifications;
    if (_activeFilter == 'all') return all;
    return all.where((n) => _categoryFor(n) == _activeFilter).toList();
  }

  String _categoryFor(NotificationItem notification) {
    // Feeder failures intentionally retain warning severity for their color and
    // icon, but belong with all other feeder outcomes in the Feeding filter.
    if (notification.notif_type == 'feeding' ||
        notification.id.startsWith('feeder_')) {
      return 'feeding';
    }
    return notification.notif_type;
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

  void _selectFilter(String filter) {
    if (_activeFilter == filter) return;
    setState(() => _activeFilter = filter);
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
          Expanded(
            child: _filtered.isEmpty ? _buildEmptyState() : _buildList(),
          ),
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
          border: Border.all(color: AppColors.darkWith(0.08)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.6), letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = [
      ('all', 'All'),
      ('critical', 'Critical'),
      ('warning', 'Warnings'),
      ('feeding', 'Feeding'),
      ('reminder', 'Reminders'),
      ('operational', 'System'),
    ];
    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isActive = _activeFilter == filter.$1;
          return Semantics(
            selected: isActive,
            button: true,
            label: '${filter.$2} notifications',
            child: GestureDetector(
              onTap: () => _selectFilter(filter.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.dark.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  filter.$2,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? AppColors.primary
                        : AppColors.dark.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow() {
    final svc = NotificationService.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_filtered.length} notification${_filtered.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5)),
          ),
          if (svc.unreadCount > 0)
            TextButton.icon(
              onPressed: svc.markAllRead,
              icon: const Icon(Icons.done_all_rounded, size: 14),
              label: const Text('Mark all read'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final grouped = <String, List<NotificationItem>>{};
    for (final n in _filtered) {
      final key = _dateGroupKey(n.created_at);
      grouped.putIfAbsent(key, () => []).add(n);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: grouped.entries.map((entry) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
            child: Text(entry.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
          ...entry.value.map(_buildNotificationItem),
        ],
      )).toList(),
    );
  }

  Widget _buildNotificationItem(NotificationItem n) {
    final color = _typeColor(n.notif_type);
    final isUnread = NotificationService.instance.unreadStatus(n.id);
    return GestureDetector(
      onTap: () => _showDetail(n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        decoration: BoxDecoration(
          color: isUnread ? color.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isUnread ? color.withValues(alpha: 0.25) : AppColors.darkWith(0.08), width: isUnread ? 1.5 : 1.0),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Icon(_typeIcon(n.notif_type), size: 14, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(n.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.dark))),
                    if (isUnread) Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                  ]),
                  const SizedBox(height: 2),
                  Text(n.body, style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.6)), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(_timeAgo(n.created_at), style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.notifications_off_outlined, size: 48, color: AppColors.darkWith(0.15)),
      const SizedBox(height: 12),
      Text('No notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4))),
    ]),
  );

  void _showDetail(NotificationItem n) {
    final color = _typeColor(n.notif_type);
    final displayTime = _toManila(n.created_at);
    NotificationService.instance.markAsRead(n.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(_typeIcon(n.notif_type), size: 20, color: color)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
                  const SizedBox(height: 2),
                  Text(_timeAgo(n.created_at), style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.4))),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.done_all_rounded, size: 12, color: AppColors.primary), SizedBox(width: 4), Text('Read by you', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primary))]),
                ),
              ]),
              const SizedBox(height: 16),
              Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.darkWith(0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.darkWith(0.08))), child: Text(n.body, style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.8), height: 1.6))),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text('${displayTime.month}/${displayTime.day}/${displayTime.year} · ${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')} PHT', style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.35))),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: TextButton(onPressed: () => Navigator.pop(ctx), style: TextButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Got it', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))),
            ],
          ),
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'critical': return AppColors.critical;
      case 'warning': return AppColors.warning;
      case 'feeding': return AppColors.primary;
      case 'operational': return AppColors.normal;
      case 'reminder': return AppColors.warningDark;
      default: return AppColors.normal;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'critical': return Icons.warning_rounded;
      case 'warning': return Icons.info_outline;
      case 'feeding': return Icons.set_meal_rounded;
      case 'operational': return Icons.check_circle_outline;
      case 'reminder': return Icons.notifications_outlined;
      default: return Icons.circle;
    }
  }

  DateTime _toManila(DateTime dt) => dt.toUtc().add(_manilaOffset);

  String _dateGroupKey(DateTime dt) {
    final local = _toManila(dt);
    final now = _toManila(DateTime.now());
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final dayDiff = today.difference(date).inDays;
    if (dayDiff == 0) return 'Today';
    if (dayDiff == 1) return 'Yesterday';
    return '${local.month}/${local.day}/${local.year}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
