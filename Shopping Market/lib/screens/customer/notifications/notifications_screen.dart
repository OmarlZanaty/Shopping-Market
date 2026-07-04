import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/api_service.dart';
import '../../../utils/constants.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getMyNotifications();
      if (mounted) setState(() { _items = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _marking = true);
    try {
      await _api.markAllNotificationsRead();
      if (mounted) {
        setState(() {
          _items = _items.map((n) => {...n, 'is_read': true}).toList();
          _marking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _marking = false);
    }
  }

  int get _unreadCount => _items.where((n) => n['is_read'] != true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── AppBar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.midnight,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(children: [
              const Text('الإشعارات',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  )),
              if (_unreadCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.coral,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            ]),
            actions: [
              if (_unreadCount > 0)
                TextButton(
                  onPressed: _marking ? null : _markAllRead,
                  child: _marking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text(
                          'قراءة الكل',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                ),
              const SizedBox(width: 8),
            ],
          ),

          // ── Content ──────────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.coral),
              ),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(child: _emptyState())
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _NotificationTile(
                  data: _items[i],
                  onTap: () => _handleTap(_items[i]),
                ),
                childCount: _items.length,
              ),
            ),
        ],
      ),
    );
  }

  void _handleTap(Map<String, dynamic> data) {
    // Mark individual as read locally
    final idx = _items.indexOf(data);
    if (idx >= 0 && data['is_read'] != true) {
      setState(() => _items[idx] = {...data, 'is_read': true});
    }
    // Navigate to relevant screen based on notification type
    final type    = data['type']?.toString() ?? '';
    final orderId = data['order_id']?.toString() ?? data['data']?['order_id']?.toString() ?? '';
    if (orderId.isNotEmpty) {
      Navigator.pop(context);
      context.push('/orders/$orderId');
    }
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: AppColors.ice,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_off_outlined,
                  color: AppColors.coral, size: 46),
            ),
            const SizedBox(height: 20),
            const Text(
              'لا توجد إشعارات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ستظهر هنا إشعارات طلباتك والعروض',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Cairo',
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Single notification tile
// ══════════════════════════════════════════════════════════════════════════════
class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _NotificationTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRead   = data['is_read'] == true;
    final type     = data['type']?.toString() ?? '';
    final title    = data['title_ar']?.toString() ?? data['title']?.toString() ?? 'إشعار';
    final body     = data['body_ar']?.toString()  ?? data['body']?.toString()  ?? '';
    final dateStr  = data['created_at']?.toString() ?? '';

    final icon  = _iconFor(type);
    final color = _colorFor(type);

    DateTime? date;
    try { date = DateTime.parse(dateStr).toLocal(); } catch (_) {}

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : AppColors.coral.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isRead ? AppColors.border : AppColors.coral.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.midnight.withOpacity(isRead ? 0.04 : 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon container
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                ]),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (date != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _formatDate(date),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: AppColors.textMuted.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60)  return 'الآن';
    if (diff.inMinutes < 60)  return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours   < 24)  return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays    < 7)   return 'منذ ${diff.inDays} يوم';
    if (diff.inDays    < 30)  return 'منذ ${(diff.inDays / 7).floor()} أسبوع';
    return 'منذ ${(diff.inDays / 30).floor()} شهر';
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'order_status':      return Icons.local_shipping_rounded;
      case 'price_change':      return Icons.price_change_rounded;
      case 'substitute':        return Icons.swap_horiz_rounded;
      case 'item_added':        return Icons.add_shopping_cart_rounded;
      case 'quantity_change':   return Icons.edit_rounded;
      case 'stock_available':   return Icons.inventory_2_rounded;
      case 'promotion':         return Icons.local_offer_rounded;
      default:                  return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'order_status':      return AppColors.sapphire;
      case 'price_change':
      case 'quantity_change':   return AppColors.gold;
      case 'substitute':        return AppColors.watermelon;
      case 'item_added':        return AppColors.mint;
      case 'stock_available':   return AppColors.mint;
      case 'promotion':         return AppColors.coral;
      default:                  return AppColors.coral;
    }
  }
}
