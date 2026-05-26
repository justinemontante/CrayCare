import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/notification_item.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _ns = NotificationService.instance;
  String _activeFilter = 'all';

  List<NotificationItem> get _filtered {
    final all = _ns.notifications;
    if (_activeFilter == 'all') return all;
    return all.where((n) => n.typeString == _activeFilter).toList();
  }

  int get _unreadCount => _ns.unreadCount;
  int get _criticalCount => _ns.criticalCount;

  @override
  void initState() {
    super.initState();
    _ns.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _ns.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildFilterRow(),
          Divider(height: 1, color: AppColors.darkWith(0.06)),
          if (_filtered.isEmpty)
            Expanded(child: _buildEmptyState())
          else
            Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_criticalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.critical.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_rounded, size: 11, color: AppColors.critical),
                      const SizedBox(width: 3),
                      Text(
                        '$_criticalCount critical',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.critical,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              if (_unreadCount > 0)
                Text(
                  '$_unreadCount unread',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    const filters = ['all', 'critical', 'warning', 'operational', 'reminders'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isActive = _activeFilter == f;
            final count = f == 'all'
                ? _ns.notifications.length
                : _ns.notifications.where((n) => n.typeString == f).length;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _activeFilter = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : AppColors.darkWith(0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive ? AppColors.primary : AppColors.darkWith(0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f == 'all' ? 'All' : '${f[0].toUpperCase()}${f.substring(1)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : AppColors.darkWith(0.6),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white.withValues(alpha: 0.2) : AppColors.darkWith(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isActive ? Colors.white : AppColors.darkWith(0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(
                entry.key,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkWith(0.5),
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
    final color = _typeColor(n.typeString);
    return GestureDetector(
      onTap: () {
        if (n.unread) {
          _ns.markRead(n);
          setState(() {});
        }
        _showDetail(n);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkWith(0.08)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                color: color,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_typeIcon(n.typeString), size: 16, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    n.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: n.unread ? FontWeight.w700 : FontWeight.w600,
                                      color: AppColors.dark,
                                    ),
                                  ),
                                ),
                                if (n.unread)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(left: 6),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              n.message,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.darkWith(0.6),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _timeAgo(n.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.darkWith(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_off_outlined, size: 48, color: AppColors.darkWith(0.12)),
          const SizedBox(height: 14),
          Text(
            'No notifications',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
          ),
          const SizedBox(height: 4),
          Text(
            'You\'re all caught up!',
            style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.3)),
          ),
        ],
      ),
    );
  }

  void _showDetail(NotificationItem n) {
    final color = _typeColor(n.typeString);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.darkWith(0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_typeIcon(n.typeString), size: 22, color: color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _timeAgo(n.timestamp),
                            style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.4)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    n.message,
                    style: TextStyle(fontSize: 13, color: AppColors.darkWith(0.8), height: 1.5),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
      case 'operational': return AppColors.subtitleText;
      case 'reminder': return AppColors.primary;
      default: return AppColors.subtitleText;
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
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
