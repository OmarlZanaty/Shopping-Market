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

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;

    // Try rawValue first, fall back to displayValue; always trim whitespace.
    final raw = capture.barcodes.first.rawValue?.trim() ??
        capture.barcodes.first.displayValue?.trim();
    if (raw == null || raw.isEmpty) return;

    _scanned = true;

    // Look up the product by barcode.
    final product = await _api.getProductByBarcode(raw);

    if (!mounted) return;

    if (product != null) {
      // Return the raw barcode string so the caller can do its own lookup
      // (avoids passing a UUID back as a "barcode").
      Navigator.pop(context, raw);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المنتج غير موجود في النظام',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Reset so the user can try scanning another barcode.
      setState(() => _scanned = false);
    }
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
          onDetect: _onDetect,
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