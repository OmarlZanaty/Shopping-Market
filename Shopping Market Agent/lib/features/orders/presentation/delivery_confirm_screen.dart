import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/formatters.dart';
import '../data/orders_providers.dart';

/// Driver delivery confirmation screen.
/// The agent can either:
///   ✅ Confirm delivery  — enters collected amount + proof photo → marks delivered
///   ❌ Report failure    — picks a reason → cancels the order from out_for_delivery
class DeliveryConfirmScreen extends ConsumerStatefulWidget {
  final String orderId;
  const DeliveryConfirmScreen({super.key, required this.orderId});

  @override
  ConsumerState<DeliveryConfirmScreen> createState() => _DeliveryConfirmScreenState();
}

class _DeliveryConfirmScreenState extends ConsumerState<DeliveryConfirmScreen> {
  final _amount = TextEditingController();
  String? _photoUrl;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  // ── Delivered ─────────────────────────────────────────────────────────────

  Future<void> _submit(double total, String paymentMethod) async {
    final needsAmount = paymentMethod == 'cash' || paymentMethod == 'pos';
    if (needsAmount) {
      final v = double.tryParse(_amount.text);
      if (v == null) {
        _toast('أدخل المبلغ المحصّل', AppColors.errorRed);
        return;
      }
      if ((v - total).abs() > 0.5) {
        final ok = await _confirmMismatch(total, v);
        if (!ok) return;
      }
    }
    if (_photoUrl == null) {
      _toast('صورة الإثبات مطلوبة', AppColors.errorRed);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(ordersApiProvider).delivered(
        widget.orderId,
        amountCollected: needsAmount ? double.tryParse(_amount.text) : null,
        deliveryPhotoUrl: _photoUrl,
      );
      if (!mounted) return;
      _toast('تم تسليم الطلب بنجاح ✅', AppColors.successGreen);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) context.go('/');
      });
    } catch (e) {
      _toast(e.toString(), AppColors.errorRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Not Delivered ─────────────────────────────────────────────────────────

  Future<void> _reportFailure() async {
    final reason = await _pickFailureReason();
    if (reason == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: const Text('تأكيد فشل التوصيل'),
        content: Text('السبب: $reason\n\nسيتم إلغاء الطلب وإبلاغ العميل. هل تريد المتابعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
            child: const Text('نعم، إلغاء الطلب'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(ordersApiProvider).failedDelivery(widget.orderId, reason: reason);
      if (!mounted) return;
      _toast('تم إلغاء الطلب وإبلاغ العميل', AppColors.warning);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) context.go('/');
      });
    } catch (e) {
      _toast(e.toString(), AppColors.errorRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows a bottom sheet with preset failure reasons + custom input.
  Future<String?> _pickFailureReason() async {
    const reasons = [
      'العميل غير متاح على الهاتف',
      'العميل رفض استلام الطلب',
      'العنوان غير صحيح أو غير موجود',
      'ظروف خارجية (حادث، طقس، إلخ)',
    ];
    String? custom;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 16, left: 16, right: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('سبب عدم التسليم',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...reasons.map((r) => ListTile(
                    leading: const Icon(Icons.radio_button_unchecked, color: AppColors.errorRed),
                    title: Text(r),
                    onTap: () => Navigator.pop(ctx, r),
                  )),
              const Divider(),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'سبب آخر...',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                onChanged: (v) => setLocalState(() => custom = v.trim()),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (custom != null && custom!.isNotEmpty)
                      ? () => Navigator.pop(ctx, custom)
                      : null,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
                  child: const Text('تأكيد السبب'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<bool> _confirmMismatch(double expected, double got) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: const Text('المبلغ لا يطابق'),
        content: Text(
          'المطلوب: ${Formatters.price(expected)}\nالمُحصّل: ${Formatters.price(got)}\n\nهل تريد المتابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
    ));
  }

  Future<void> _takePhoto() async {
    final url = await context.push<String>('/camera-proof');
    if (url != null && url.isNotEmpty) setState(() => _photoUrl = url);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('تأكيد التسليم')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentOrange)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (o) {
          final needsAmount = o.paymentMethod == 'cash' || o.paymentMethod == 'pos';
          return ListView(
            padding: const EdgeInsets.all(AppDimensions.paddingH),
            children: [
              // ── Order summary ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.orderNumber,
                      style: const TextStyle(
                        color: AppColors.accentGold, fontSize: 18,
                        fontWeight: FontWeight.bold, fontFamily: 'Inter',
                      )),
                  const SizedBox(height: 8),
                  Text(o.customerName),
                  const SizedBox(height: 4),
                  Text(o.addressFull,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(height: 16),

              // ── Amount collected ────────────────────────────────────────
              if (needsAmount) ...[
                Text('المطلوب تحصيله: ${Formatters.price(o.total)}',
                    style: const TextStyle(
                      color: AppColors.accentOrange, fontSize: 18,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المُحصّل',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Photo proof ─────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _photoUrl == null
                      ? AppColors.warning.withValues(alpha: 0.1)
                      : AppColors.successGreen.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _photoUrl == null ? AppColors.warning : AppColors.successGreen,
                  ),
                  borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
                ),
                child: Column(children: [
                  Icon(
                    _photoUrl == null ? Icons.camera_alt_outlined : Icons.check_circle,
                    color: _photoUrl == null ? AppColors.warning : AppColors.successGreen,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(_photoUrl == null ? 'صورة الإثبات مطلوبة' : 'تم رفع الصورة ✅'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_photoUrl == null ? 'التقاط صورة' : 'إعادة التصوير'),
                  ),
                ]),
              ),
              const SizedBox(height: 24),

              // ── Confirm delivered ───────────────────────────────────────
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _submit(o.total, o.paymentMethod),
                  icon: const Icon(Icons.check_circle_outline),
                  label: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('✅ تأكيد التسليم', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.successGreen),
                ),
              ),
              const SizedBox(height: 12),

              // ── Not delivered ───────────────────────────────────────────
              SizedBox(
                width: double.infinity, height: 52,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _reportFailure,
                  icon: const Icon(Icons.cancel_outlined, color: AppColors.errorRed),
                  label: const Text('❌ لم يتم التسليم',
                      style: TextStyle(color: AppColors.errorRed, fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.errorRed),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}
