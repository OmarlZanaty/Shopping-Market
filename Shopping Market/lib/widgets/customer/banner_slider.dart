import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';

class BannerSlider extends StatefulWidget {
  final List<BannerModel> banners;
  const BannerSlider({super.key, required this.banners});
  @override State<BannerSlider> createState() => _BannerSliderState();
}

class _BannerSliderState extends State<BannerSlider> {
  final _controller = PageController();
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 140,
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.banners.length,
          itemBuilder: (_, i) {
            final b = widget.banners[i];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.coral, Color(0xFFea6009)]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(children: [
                if (b.imageUrl.isNotEmpty)
                  ClipRRect(borderRadius: BorderRadius.circular(18),
                    child: CachedNetworkImage(imageUrl: b.imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                      errorWidget: (_, __, ___) => const SizedBox())),
                Positioned(left: 16, top: 0, bottom: 0, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(100)),
                      child: Text('عرض خاص', style: TextStyle(color: AppColors.coral, fontSize: 8, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
                    const SizedBox(height: 6),
                    Text(b.titleAr, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                    Text(b.subtitleAr, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontFamily: 'Cairo')),
                  ],
                )),
              ]),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      SmoothPageIndicator(controller: _controller, count: widget.banners.length,
        effect: WormEffect(dotHeight: 5, dotWidth: 5, activeDotColor: AppColors.coral, dotColor: AppColors.sky.withOpacity(0.3))),
    ]);
  }
}
