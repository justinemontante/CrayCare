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
    return all.where((n) => n.notif_type == _activeFilter).toList();
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              reverseDuration: const Duration(milliseconds: 140),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.025, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_activeFilter),
                child: _filtered.isEmpty ? _buildEmptyState() : _buildList(),
              ),
            ),
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
          _buildKpiCard(
            'Reminders',
            '${svc.reminderCount}',
            AppColors.warningDark,
          ),
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
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.darkWith(0.6),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = [
      ('all', 'All'),
      ('critical', 'Critical'),
      ('warning', 'Warning'),
      ('operational', 'Operational'),
      ('reminder', 'Reminders'),
    ];
    final activeIndex = filters.indexWhere((f) => f.$1 == _activeFilter);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / filters.length;

          return SizedBox(
            height: 38,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: tabWidth * (activeIndex < 0 ? 0 : activeIndex),
                  top: 0,
                  bottom: 0,
                  width: tabWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.dark.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(filters.length, (i) {
                    final filter = filters[i].$1;
                    final label = filters[i].$2;
                    final isActive = _activeFilter == filter;

                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectFilter(filter),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: isActive
                                      ? AppColors.primary
                                      : AppColors.dark.withValues(alpha: 0.45),
                                ),
                                child: Text(label, maxLines: 1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_filtered.length} notification${_filtered.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final grouped = <String, List<NotificationItem>>{};
    for (var n in _filtered) {
      final key = _dateGroupKey(n.created_at);
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
              child: Text(
                entry.key,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            ...entry.value.map((n) => _buildNotificationItem(n)),
          ],
        );
      }).toList(),
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
          border: Border.all(
            color: isUnread
                ? color.withValues(alpha: 0.25)
                : AppColors.darkWith(0.08),
            width: isUnread ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_typeIcon(n.notif_type), size: 14, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark,
                          ),
                        ),
                      ),
                      if (NotificationService.instance.unreadStatus(n.id))
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.body,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.darkWith(0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(n.created_at),
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.darkWith(0.4),
                    ),
                  ),
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
          Icon(
            Icons.notifications_off_outlined,
            size: 48,
            color: AppColors.darkWith(0.15),
          ),
          const SizedBox(height: 12),
          Text(
            'No notifications',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(NotificationItem n) {
    final color = _typeColor(n.notif_type);
    NotificationService.instance.markAsRead(n.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _typeIcon(n.notif_type),
                        size: 20,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _timeAgo(n.created_at),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.darkWith(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.done_all_rounded,
                            size: 12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Read by you',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
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
                  child: Text(
                    n.body,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.darkWith(0.8),
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    '${n.created_at.month}/${n.created_at.day}/${n.created_at.year} · ${n.created_at.hour.toString().padLeft(2, '0')}:${n.created_at.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.darkWith(0.35),
                    ),
                  ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
      case 'critical':
        return AppColors.critical;
      case 'warning':
        return AppColors.warning;
      case 'operational':
      case 'normal':
        return AppColors.normal;
      case 'reminder':
        return AppColors.warningDark;
      default:
        return AppColors.normal;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'critical':
        return Icons.warning_rounded;
      case 'warning':
        return Icons.info_outline;
      case 'operational':
      case 'normal':
        return Icons.check_circle_outline;
      case 'reminder':
        return Icons.notifications_outlined;
      default:
        return Icons.circle;
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
