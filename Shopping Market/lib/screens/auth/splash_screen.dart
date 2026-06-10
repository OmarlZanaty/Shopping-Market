import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/secure_storage_keys.dart';
import '../../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Animation controllers ─────────────────────────────────────────────────
  late final AnimationController _logoCtrl;
  late final AnimationController _contentCtrl;

  late final Animation<double>  _logoScale;
  late final Animation<Offset>  _logoSlide;
  late final Animation<double>  _textFade;
  late final Animation<Offset>  _taglineSlide;
  late final Animation<double>  _ringScale;
  late final Animation<double>  _bottomFade;

  bool _navigated = false; // guard — only navigate once

  @override
  void initState() {
    super.initState();

    // Force dark status bar for full immersion
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // Logo entrance
    _logoCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100),
    );
    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.4), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _ringScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // Text & bottom content
    _contentCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl, curve: Curves.easeIn),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.3), end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentCtrl,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    ));
    _bottomFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentCtrl,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    // Start animations sequentially
    _logoCtrl.forward().then((_) => _contentCtrl.forward());

    // Navigate after minimum display time
    Future.delayed(const Duration(milliseconds: 2800), _navigate);
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    if (!mounted || _navigated) return;
    _navigated = true;

    final prefs = await SharedPreferences.getInstance();
    final seen  = prefs.getBool(SecureStorageKeys.onboardingSeen) ?? false;

    if (!mounted) return;

    if (!seen) {
      context.go('/onboarding');
      return;
    }

    final auth = context.read<AuthProvider>();
    // Wait for auth to fully resolve — event-driven, no blind sleep
    if (auth.status == AuthStatus.unknown) {
      await _awaitAuthResolution(auth);
      if (!mounted) return;
    }

    if (auth.isAuthenticated) {
      final unlocked = await _biometricGate();
      if (!mounted) return;
      if (unlocked) {
        context.go('/home');
      } else {
        // User explicitly refused the fingerprint — fall back to login.
        context.go('/login');
      }
    } else {
      context.go('/login');
    }
  }

  /// Asks for fingerprint/biometric before entering the app.
  /// Returns true when unlocked. Devices without biometrics (or with none
  /// enrolled) skip the gate so the user is never locked out.
  Future<bool> _biometricGate() async {
    final localAuth = LocalAuthentication();
    try {
      final supported = await localAuth.isDeviceSupported();
      final canCheck = await localAuth.canCheckBiometrics;
      if (!supported || !canCheck) return true;
      final enrolled = await localAuth.getAvailableBiometrics();
      if (enrolled.isEmpty) return true;

      for (var attempt = 0; attempt < 3; attempt++) {
        final ok = await localAuth.authenticate(
          localizedReason: 'اضغط ببصمتك للدخول إلى التطبيق',
          options: const AuthenticationOptions(
            biometricOnly: false, // allow device PIN/pattern fallback
            stickyAuth: true,
          ),
        );
        if (ok) return true;
      }
      return false;
    } catch (_) {
      // Plugin/platform error (e.g. emulator) — don't lock the user out.
      return true;
    }
  }

  /// Listens to [AuthProvider] and completes as soon as status leaves
  /// [AuthStatus.unknown].  Falls back after 10 s in case the server never
  /// responds (e.g. no network), so the user still gets to the login screen.
  Future<void> _awaitAuthResolution(AuthProvider auth) {
    if (auth.status != AuthStatus.unknown) return Future.value();

    final completer = Completer<void>();

    void listener() {
      if (auth.status != AuthStatus.unknown) {
        auth.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    }

    auth.addListener(listener);

    // Safety timeout — removes the listener and unblocks navigation
    Future.delayed(const Duration(seconds: 10), () {
      auth.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    });

    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.3),
            radius: 1.2,
            colors: [
              Color(0xFF2D2D4E), // warm dark center
              Color(0xFF1A1A2E), // deep dark edges
            ],
          ),
        ),
        child: SafeArea(
          child: Column(children: [

            // ── Logo + glow ring ─────────────────────────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Outer glow ring
                    ScaleTransition(
                      scale: _ringScale,
                      child: Container(
                        width: 180, height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFFFF8C00).withOpacity(0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Center(
                          // Logo card
                          child: SlideTransition(
                            position: _logoSlide,
                            child: ScaleTransition(
                              scale: _logoScale,
                              child: Container(
                                width: 130, height: 130,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A2E),
                                  borderRadius: BorderRadius.circular(36),
                                  border: Border.all(
                                    color: const Color(0xFFFF8C00).withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF8C00).withOpacity(0.35),
                                      blurRadius: 40,
                                      spreadRadius: 4,
                                      offset: const Offset(0, 12),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 30,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(22),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // App name
                    FadeTransition(
                      opacity: _textFade,
                      child: const Text(
                        'Shopping',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    FadeTransition(
                      opacity: _textFade,
                      child: const Text(
                        'Market',
                        style: TextStyle(
                          color: Color(0xFFFF8C00),
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                          letterSpacing: 1,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Tagline
                    SlideTransition(
                      position: _taglineSlide,
                      child: FadeTransition(
                        opacity: _textFade,
                        child: const Text(
                          'FRESH  ·  FAST  ·  SMART',
                          style: TextStyle(
                            color: Color(0xFFFFB800),
                            fontSize: 11,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom: loading bar + emojis ─────────────────────────────────
            FadeTransition(
              opacity: _bottomFade,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
                child: Column(children: [
                  // Emoji row
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text('🍎', style: TextStyle(fontSize: 28)),
                      Text('🥦', style: TextStyle(fontSize: 28)),
                      Text('🥛', style: TextStyle(fontSize: 28)),
                      Text('🛒', style: TextStyle(fontSize: 28)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Loading bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      backgroundColor: Color(0xFF2D2D4E),
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8C00)),
                      minHeight: 3,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
