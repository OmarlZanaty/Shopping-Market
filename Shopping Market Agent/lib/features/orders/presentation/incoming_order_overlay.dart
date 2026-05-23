import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../data/orders_providers.dart';

/// Full-screen overlay shown when a new_order FCM arrives in foreground.
/// 60-second countdown, looping alert sound, large accept/reject buttons.
class IncomingOrderOverlay extends ConsumerStatefulWidget {
  final String orderId;
  final String orderNumber;
  final int itemCount;
  final String customerArea;
  final double total;

  const IncomingOrderOverlay({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.itemCount,
    required this.customerArea,
    required this.total,
  });

  @override
  ConsumerState<IncomingOrderOverlay> createState() => _IncomingOrderOverlayState();
}

class _IncomingOrderOverlayState extends ConsumerState<IncomingOrderOverlay>
    with SingleTickerProviderStateMixin {
  static const int _windowSec = 60;
  late final AnimationController _pulse;
  final AudioPlayer _player = AudioPlayer();
  Timer? _countdown;
  int _secondsLeft = _windowSec;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _startSound();
    _startCountdown();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _player.stop();
    _player.dispose();
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _startSound() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/new_order.mp3'));
    } catch (_) {
      // Sound files may not be bundled in dev — fail silently.
    }
  }

  void _startCountdown() {
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _reject(autoTimeout: true);
      }
    });
  }

  Color get _countdownColor {
    if (_secondsLeft > 30) return AppColors.accentGold;
    if (_secondsLeft > 10) return AppColors.accentOrange;
    return AppColors.errorRed;
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(ordersApiProvider).accept(widget.orderId);
      if (!mounted) return;
      Navigator.of(context).pop('accepted');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل قبول الطلب: $e'),
        backgroundColor: AppColors.errorRed,
      ));
      setState(() => _busy = false);
    }
  }

  Future<void> _reject({bool autoTimeout = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(ordersApiProvider).reject(widget.orderId,
          reason: autoTimeout ? 'timeout' : 'manual_reject');
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop('rejected');
  }

  @override
  Widget build(BuildContext context) {
    final progress = _secondsLeft / _windowSec;
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.92),
      body: SafeArea(
        child: Column(children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.backgroundSecondary,
            valueColor: AlwaysStoppedAnimation(_countdownColor),
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('طلب جديد',
                  style: TextStyle(color: AppColors.accentOrange, fontSize: 14, fontWeight: FontWeight.bold)),
              Text('$_secondsLeft ث',
                  style: TextStyle(color: _countdownColor, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Spacer(),
          ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.05).animate(_pulse),
            child: Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentOrange.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: AppColors.accentOrange.withOpacity(0.4),
                      blurRadius: 50, spreadRadius: 5),
                ],
              ),
              child: const Icon(Icons.shopping_bag, color: AppColors.accentOrange, size: 80),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Text(widget.orderNumber,
                  style: const TextStyle(color: AppColors.accentGold, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Inter')),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat('${widget.itemCount}', 'صنف'),
                _stat('${widget.total.toStringAsFixed(0)} ج.م', 'إجمالي'),
                _stat(widget.customerArea, 'المنطقة', isText: true),
              ]),
            ]),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _accept,
                  icon: const Icon(Icons.check_circle, size: 24),
                  label: const Text('قبول', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.successGreen,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _reject(),
                  icon: const Icon(Icons.cancel, size: 24),
                  label: const Text('رفض', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.errorRed,
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label, {bool isText = false}) => Column(children: [
        Text(value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: isText ? 14 : 16,
              fontFamily: isText ? 'Cairo' : 'Inter',
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]);
}
