import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/storage/secure_storage_keys.dart';

/// 3-slide onboarding shown only once. Sets onboarding_seen flag on completion.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _idx = 0;

  static const _slides = [
    _Slide(
      title: 'أهلاً بك في Shopping Market',
      body: 'كل احتياجاتك اليومية بنقرة واحدة، وتوصيل سريع لباب بيتك.',
      emoji: '🛒',
    ),
    _Slide(
      title: 'عروض حصرية كل يوم',
      body: 'وفّر مع الخصومات اليومية واكسب نقاط مع كل طلب.',
      emoji: '💸',
    ),
    _Slide(
      title: 'تتبع طلبك مباشرة',
      body: 'شاهد طلبك يصل خطوة بخطوة على الخريطة المباشرة.',
      emoji: '📦',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SecureStorageKeys.onboardingSeen, true);
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _finish, child: const Text('تخطي')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _idx = i),
                itemBuilder: (_, i) => _slideWidget(_slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final isActive = i == _idx;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.accentOrange : AppColors.textSecondary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingH),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_idx == _slides.length - 1) {
                      _finish();
                    } else {
                      _page.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(_idx == _slides.length - 1 ? 'ابدأ' : 'التالي'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slideWidget(_Slide s) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(s.emoji, style: const TextStyle(fontSize: 96)),
          const SizedBox(height: 32),
          Text(
            s.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            s.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  final String title;
  final String body;
  final String emoji;
  const _Slide({required this.title, required this.body, required this.emoji});
}
