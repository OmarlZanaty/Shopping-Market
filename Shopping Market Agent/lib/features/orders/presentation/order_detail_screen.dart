import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_badge.dart';
import '../data/order_models.dart';
import '../data/orders_providers.dart';

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentOrange)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (order) => RefreshIndicator(
          color: AppColors.accentOrange,
          onRefresh: () async => ref.refresh(orderDetailProvider(orderId).future),
          child: ListView(
            padding: const EdgeInsets.all(AppDimensions.paddingH),
            children: [
              _headerCard(order),
              const SizedBox(height: 12),
              _customerCard(context, ref, order),
              const SizedBox(height: 12),
              _itemsCard(context, order),
              const SizedBox(height: 12),
              _paymentCard(order),
              if (order.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _notesCard(order),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: orderAsync.maybeWhen(
        data: (o) => _ActionBar(order: o),
        orElse: () => null,
      ),
    );
  }

  Widget _headerCard(OrderModel o) => Container(
        padding: const EdgeInsets.all(AppDimensions.cardInner),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          boxShadow: const [AppDimensions.cardGlow],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(o.orderNumber, style: const TextStyle(
                color: AppColors.accentGold, fontSize: 20,
                fontWeight: FontWeight.bold, fontFamily: 'Inter',
              )),
            ),
            StatusBadge(o.status),
          ]),
          const SizedBox(height: 8),
          Text(Formatters.relativeTime(o.createdAt), style: AppTypography.smallLabel),
          if (o.branchName != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.store, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(o.branchName!, style: AppTypography.smallLabel),
            ]),
          ],
        ]),
      );

  Widget _customerCard(BuildContext context, WidgetRef ref, OrderModel o) => Container(
        padding: const EdgeInsets.all(AppDimensions.cardInner),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('بيانات العميل', style: AppTypography.sectionHeader),
            const Spacer(),
            IconButton(
              onPressed: () => _shareCustomerData(context, ref, o),
              icon: const Icon(Icons.share, color: AppColors.accentOrange),
              tooltip: 'مشاركة',
            ),
          ]),
          const SizedBox(height: 8),
          _row(Icons.person_outline, o.customerName),
          _row(Icons.phone_outlined, o.customerPhone, onTap: () async {
            final uri = Uri.parse('tel:${o.customerPhone}');
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          }),
          _row(Icons.location_on_outlined, o.addressFull),
          if (o.lat != null && o.lng != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(
                      'https://www.google.com/maps/dir/?api=1&destination=${o.lat},${o.lng}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('فتح في الخرائط'),
              ),
            ),
          ],
        ]),
      );

  Widget _row(IconData icon, String text, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: AppTypography.body.copyWith(
                    decoration: onTap != null ? TextDecoration.underline : null,
                    color: onTap != null ? AppColors.accentOrange : AppColors.textPrimary,
                  )),
            ),
          ]),
        ),
      );

  Widget _itemsCard(BuildContext context, OrderModel o) =>
      Container(
        padding: const EdgeInsets.all(AppDimensions.cardInner),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('الأصناف', style: AppTypography.sectionHeader),
            const Spacer(),
            Text('${o.itemCount}', style: AppTypography.smallLabel),
          ]),
          const SizedBox(height: 8),
          ...o.items.map((it) => _itemRow(it)),
          // Show picking button whenever the order is in an active preparation stage.
          if (o.status == 'accepted' || o.status == 'preparing') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => GoRouter.of(context).push('/picking/${o.id}'),
                icon: const Icon(Icons.checklist),
                label: const Text('بدء تجميع الطلب'),
              ),
            ),
          ],
        ]),
      );

  Widget _itemRow(OrderItemModel it) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(8),
              image: it.imageUrl != null
                  ? DecorationImage(image: NetworkImage(it.imageUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: it.imageUrl == null
                ? const Icon(Icons.image, color: AppColors.textSecondary, size: 18)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.nameAr, style: AppTypography.body),
              if (it.barcode != null)
                Text(it.barcode!, style: AppTypography.smallLabel.copyWith(fontFamily: 'Inter')),
            ]),
          ),
          Text(it.isWeighed ? it.qtyLabel(it.requestedQty) : '${it.requestedQty.toStringAsFixed(0)} قطعة',
              style: AppTypography.body),
        ]),
      );

  Widget _paymentCard(OrderModel o) => Container(
        padding: const EdgeInsets.all(AppDimensions.cardInner),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('الدفع', style: AppTypography.sectionHeader),
          const SizedBox(height: 8),
          _kvRow('الطريقة', _paymentLabel(o.paymentMethod)),
          _kvRow('الإجمالي', Formatters.price(o.total)),
          _kvRow('رسوم التوصيل', Formatters.price(o.deliveryFee)),
          if (o.paymentMethod == 'cash' || o.paymentMethod == 'pos') ...[
            const Divider(height: 24, color: AppColors.divider),
            Row(children: [
              const Expanded(
                child: Text('المبلغ المطلوب تحصيله',
                    style: TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.bold)),
              ),
              Text(Formatters.price(o.total),
                  style: AppTypography.moneyLarge.copyWith(color: AppColors.accentOrange)),
            ]),
          ],
        ]),
      );

  String _paymentLabel(String m) {
    switch (m) {
      case 'cash':           return 'كاش عند الاستلام';
      case 'pos':            return 'كارت عند الاستلام';
      case 'online':         return 'دفع أونلاين';
      case 'wallet':         return 'محفظة';
      case 'loyalty_points': return 'نقاط';
      default:               return m;
    }
  }

  Widget _kvRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: AppTypography.smallLabel)),
          Text(v, style: AppTypography.body),
        ]),
      );

  Widget _notesCard(OrderModel o) => Container(
        padding: const EdgeInsets.all(AppDimensions.cardInner),
        decoration: BoxDecoration(
          color: AppColors.accentGold.withOpacity(0.1),
          border: Border.all(color: AppColors.accentGold, width: 1),
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.sticky_note_2, color: AppColors.accentGold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ملاحظات العميل',
                  style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(o.notes, style: const TextStyle(color: AppColors.accentGold)),
            ]),
          ),
        ]),
      );

  Future<void> _shareCustomerData(BuildContext context, WidgetRef ref, OrderModel o) async {
    final mapsUrl = (o.lat != null && o.lng != null)
        ? 'https://www.google.com/maps/search/?api=1&query=${o.lat},${o.lng}'
        : '';
    final text = '''اسم العميل: ${o.customerName}
رقم التليفون: ${o.customerPhone}
العنوان: ${o.addressFull}
${mapsUrl.isNotEmpty ? "اللوكيشن: $mapsUrl\n" : ""}رقم الأوردر: ${o.orderNumber}''';
    await Share.share(text);
    try {
      await ref.read(ordersApiProvider).logAction(o.id, 'customer_data_shared');
    } catch (_) {}
  }
}

class _ActionBar extends ConsumerWidget {
  final OrderModel order;
  const _ActionBar({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(ordersApiProvider);

    Future<void> run(Future<void> Function() op, String successMsg) async {
      try {
        await op();
        ref.refresh(orderDetailProvider(order.id));
        ref.invalidate(ordersListProvider); // refresh all tabs
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMsg),
          backgroundColor: AppColors.successGreen,
        ));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.errorRed,
        ));
      }
    }

    Widget btn(String text, Color color, VoidCallback onTap) => SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color),
            onPressed: onTap,
            child: Text(text, style: const TextStyle(fontSize: 16)),
          ),
        );

    /// Simple confirm-delivery dialog — no photo, no amount entry.
    Future<void> confirmDelivered() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: const Text('تأكيد التسليم'),
          content: Text('هل تم تسليم الطلب ${order.orderNumber} للعميل؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لا'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.successGreen),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('نعم، تم التسليم'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      try {
        await api.delivered(order.id);
        if (!context.mounted) return;
        // Invalidate BEFORE navigating so ref is still bound to a live widget.
        ref.invalidate(ordersListProvider);
        ref.invalidate(orderDetailProvider(order.id));
        context.go('/');
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.errorRed,
        ));
      }
    }

    final actions = <Widget>[];

    // Single-agent flow: same person handles the entire lifecycle.
    switch (order.status) {
      case 'new':
        actions.add(btn('✅ قبول الطلب', AppColors.successGreen,
            () => run(() => api.accept(order.id), 'تم قبول الطلب')));
      case 'accepted':
        actions.add(btn('📋 بدء التحضير', AppColors.accentOrange,
            () => run(() => api.startPreparing(order.id), 'بدأ التحضير')));
      case 'preparing':
        actions.add(btn('🛵 الطلب جاهز للتوصيل', AppColors.accentOrange,
            () => run(() => api.markReady(order.id), 'الطلب جاهز وخرج للتوصيل')));
      case 'out_for_delivery':
        actions.add(btn('📦 تأكيد التسليم', AppColors.successGreen, confirmDelivered));
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
  }
}
