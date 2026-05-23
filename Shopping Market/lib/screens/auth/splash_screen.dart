import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Standalone Animated Splash Screen (No external packages required)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;
  late Animation<Offset> _logoSlideAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<Offset> _taglineSlideAnimation;
  late AnimationController _emojiController;
  late Animation<double> _emojiFadeAnimation;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _logoScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoSlideAnimation = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack));
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoController, curve: const Interval(0.4, 1.0, curve: Curves.easeIn)));
    _taglineSlideAnimation = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: _logoController, curve: const Interval(0.6, 1.0, curve: Curves.easeOutCubic)));
    _emojiController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _emojiFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _emojiController, curve: Curves.easeIn));

    _logoController.forward();
    _emojiController.forward();

    // Simulating navigation after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // Replace with your actual home/login route
        context.go('/home');
      }
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE7F0FA), Color(0xFF7BA4D0), Color(0xFF2E5E99), Color(0xFF0D2440)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SlideTransition(
                position: _logoSlideAnimation,
                child: ScaleTransition(
                  scale: _logoScaleAnimation,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, offset: const Offset(0, 15)),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Image.asset(
                        'assets/images/logo.png',  // ← Your logo path
                        width: 110,
                        height: 110,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              FadeTransition(
                opacity: _textFadeAnimation,
                child: const Text(
                  'Shopping Market',
                  style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800),
                ),
              ),
              SlideTransition(
                position: _taglineSlideAnimation,
                child: FadeTransition(
                  opacity: _textFadeAnimation,
                  child: const Text(
                    'FRESH · FAST · SMART',
                    style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 4, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 80),
              FadeTransition(
                opacity: _textFadeAnimation,
                child: const CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
              ),
              const SizedBox(height: 40),
              FadeTransition(
                opacity: _emojiFadeAnimation,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    Text('🍎', style: TextStyle(fontSize: 40)),
                    Text('🥦', style: TextStyle(fontSize: 40)),
                    Text('🥛', style: TextStyle(fontSize: 40)),
                    Text('🛒', style: TextStyle(fontSize: 40)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
