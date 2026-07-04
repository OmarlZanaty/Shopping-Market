import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/constants.dart';

/// Opens the Paymob payment URL in the device browser, then shows a
/// confirmation screen inside the app. Pops with `true` when the customer
/// confirms payment, `false` on cancel.
class PaymobWebviewScreen extends StatefulWidget {
  final String iframeUrl;
  final String amountEgp;

  const PaymobWebviewScreen({
    super.key,
    required this.iframeUrl,
    required this.amountEgp,
  });

  @override
  State<PaymobWebviewScreen> createState() => _PaymobWebviewScreenState();
}

class _PaymobWebviewScreenState extends State<PaymobWebviewScreen> {
  bool _launching = false;
  bool _browserOpened = false;

  Future<void> _openBrowser() async {
    setState(() => _launching = true);
    try {
      final uri = Uri.parse(widget.iframeUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) setState(() { _browserOpened = true; _launching = false; });
      } else {
        if (mounted) setState(() => _launching = false);
        _showError();
      }
    } catch (_) {
      if (mounted) setState(() => _launching = false);
      _showError();
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('تعذّر فتح صفحة الدفع', style: TextStyle(fontFamily: 'Cairo')),
      backgroundColor: AppColors.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.midnight,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الدفع الإلكتروني',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w700)),
            Text('المبلغ: ${widget.amountEgp} جنيه',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.gold)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: AppColors.sky.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.credit_card_rounded,
                  color: AppColors.sky, size: 48),
            ),
            const SizedBox(height: 24),

            const Text('الدفع الآمن بالبطاقة',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 22,
                    fontWeight: FontWeight.w800, color: AppColors.textMain),
                textAlign: TextAlign.center),
            const SizedBox(height: 10),

            Text(
              'سيتم فتح صفحة Paymob الآمنة في المتصفح.\n'
              'بعد إتمام الدفع، عُد هنا وأكّد.',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 14,
                  color: AppColors.textMuted, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('المبلغ: ${widget.amountEgp} جنيه',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 18,
                    fontWeight: FontWeight.w800, color: AppColors.gold)),
            const SizedBox(height: 36),

            // Open browser button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _launching ? null : _openBrowser,
                icon: _launching
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.open_in_browser_rounded),
                label: Text(_browserOpened ? 'إعادة فتح صفحة الدفع' : 'فتح صفحة الدفع',
                    style: const TextStyle(fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sky,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Confirm payment button (shown after browser was opened)
            if (_browserOpened)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('تأكيد — اكتملت عملية الدفع',
                      style: TextStyle(fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mint,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),

            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء — أدفع لاحقاً',
                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
