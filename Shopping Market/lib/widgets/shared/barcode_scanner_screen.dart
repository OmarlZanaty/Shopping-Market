import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../utils/constants.dart';
import '../../services/api_service.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});
  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController();
  final _api = ApiService();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.midnight,
        title: const Text('مسح الباركود',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) async {
            if (_scanned) return;
            final barcode = capture.barcodes.first.rawValue;
            if (barcode == null) return;
            _scanned = true;
            try {
              final product = await _api.getProductByBarcode(barcode);
              if (product != null && mounted) {
                Navigator.pop(context, product.id);
              }
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('المنتج غير موجود في النظام',
                        style: TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: AppColors.error,
                  ),
                );
                setState(() => _scanned = false);
              }
            }
          },
        ),
        // Scan overlay
        Center(
          child: Container(
            width: 250, height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.coral, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('وجّه الكاميرا نحو الباركود',
                  style: TextStyle(color: Colors.white,
                      fontFamily: 'Cairo', fontSize: 14)),
            ),
          ),
        ),
      ]),
    );
  }
}