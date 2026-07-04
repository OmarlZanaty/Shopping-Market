import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';

class BannerSlider extends StatefulWidget {
  final List<BannerModel> banners;
  final Function(BannerModel)? onBannerTap;
  final VoidCallback? onShopNow;
  const BannerSlider({super.key, required this.banners, this.onBannerTap, this.onShopNow});

  @override
  State<BannerSlider> createState() => _BannerSliderState();
}

class _BannerSliderState extends State<BannerSlider> {
  final _ctrl = PageController(viewportFraction: 0.92);
  int _current = 0;
  Timer? _timer;

  // Fallback gradient banners when API returns none
  static const _fallback = [
    _FallbackBanner('🛒 عروض اليوم', 'خصومات تصل لـ 50٪', AppColors.coralGradient),
    _FallbackBanner('⚡ عروض فلاش', 'لفترة محدودة فقط', LinearGradient(
      colors: [Color(0xFF1A1A2E), Color(0xFF2D2D4E)],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    )),
    _FallbackBanner('🎁 منتجات جديدة', 'اكتشف أحدث الوصولات', AppColors.mintGradient),
  ];

  List<dynamic> get _items => widget.banners.isNotEmpty ? widget.banners : _fallback;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _items.isEmpty) return;
      final next = (_current + 1) % _items.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 190,
        child: PageView.builder(
          controller: _ctrl,
          itemCount: _items.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (_, i) {
            final item = _items[i];
            return AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale: i == _current ? 1.0 : 0.95,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.coral.withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: item is BannerModel
                    ? GestureDetector(
                        onTap: () => widget.onBannerTap?.call(item),
                        child: _NetworkBannerCard(item),
                      )
                    : _FallbackBannerCard(
                        item as _FallbackBanner,
                        onShopNow: widget.onShopNow,
                      ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      // Animated indicator dots
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_items.length, (i) {
          final active = i == _current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? AppColors.coral : AppColors.coral.withOpacity(0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    ]);
  }
}

// ── Network banner from API ────────────────────────────────────────────────────
class _NetworkBannerCard extends StatelessWidget {
  final BannerModel b;
  const _NetworkBannerCard(this.b);

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(fit: StackFit.expand, children: [
          // Background image
          b.imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: b.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    decoration: const BoxDecoration(gradient: AppColors.coralGradient),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    decoration: const BoxDecoration(gradient: AppColors.coralGradient),
                  ),
                )
              : Container(decoration: const BoxDecoration(gradient: AppColors.coralGradient)),

          // Dark gradient overlay (bottom)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC1A1A2E), Colors.transparent],
                stops: [0.0, 0.6],
              ),
            ),
          ),

          // Text content (bottom)
          Positioned(
            bottom: 16, left: 18, right: 18,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (b.titleAr.isNotEmpty)
                Text(b.titleAr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                      shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                    )),
              if (b.subtitleAr.isNotEmpty)
                Text(b.subtitleAr,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontFamily: 'Cairo',
                    )),
            ]),
          ),

          // "عرض خاص" chip (top-right)
          Positioned(
            top: 14, right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.gold, AppColors.coral]),
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text('عرض خاص',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                  )),
            ),
          ),
        ]),
      );
}

// ── Fallback banner (no API data) ─────────────────────────────────────────────
class _FallbackBannerCard extends StatelessWidget {
  final _FallbackBanner b;
  final VoidCallback? onShopNow;
  const _FallbackBannerCard(this.b, {this.onShopNow});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(gradient: b.gradient),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                  )),
              const SizedBox(height: 6),
              Text(b.subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  )),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onShopNow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                  ),
                  child: const Text('تسوق الآن',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo',
                      )),
                ),
              ),
            ],
          ),
        ),
      );
}

class _FallbackBanner {
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  const _FallbackBanner(this.title, this.subtitle, this.gradient);
}
