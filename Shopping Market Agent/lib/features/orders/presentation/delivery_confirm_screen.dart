import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/formatters.dart';
import '../data/orders_providers.dart';

/// Driver delivery confirmation. Required: amount collected if COD/POS,
/// plus delivery proof photo. Photo upload is delegated to the camera flow.
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

  Future<void> _submit(double total, String paymentMethod) async {
    final needsAmount = paymentMethod == 'cash' || paymentMethod == 'pos';
    if (needsAmount) {
      final v = double.tryParse(_amount.text);
      if (v == null) {
        _toast('أدخل المبلغ المحصّل', AppColors.errorRed);
        return;
      }
      if ((v - total).abs() > 0.5) {
        // ±0.5 EGP tolerance for rounding.
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
      _toast('تم تسليم الطلب بنجاح', AppColors.successGreen);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) context.go('/');
      });
    } catch (e) {
      _toast(e.toString(), AppColors.errorRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    // Push the camera proof screen; it returns the uploaded S3 URL.
    final url = await Navigator.of(context).pushNamed<String>('/camera-proof');
    if (url != null) setState(() => _photoUrl = url);
  }

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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _photoUrl == null
                      ? AppColors.warning.withOpacity(0.1)
                      : AppColors.successGreen.withOpacity(0.1),
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
                  Text(_photoUrl == null
                      ? 'صورة الإثبات مطلوبة'
                      : 'تم رفع الصورة'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_photoUrl == null ? 'التقاط صورة' : 'إعادة التصوير'),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _submit(o.total, o.paymentMethod),
                  icon: const Icon(Icons.check),
                  label: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('تأكيد التسليم', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.successGreen),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
