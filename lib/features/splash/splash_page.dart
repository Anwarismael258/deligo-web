import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';
import '../onboarding/onboarding_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  bool _showPoweredBy = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );
    _goNext();
  }

  Future<void> _goNext() async {
    // This shared Flutter flow is deliberately used by APK and Chrome alike.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _showPoweredBy = false);
    _controller
      ..reset()
      ..forward();
    await Future.delayed(const Duration(milliseconds: 1200));
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    if (!mounted) return;
    final navigator = GoRouter.of(context);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      navigator.go('/home');
      return;
    }

    final preferences = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 8),
    );
    final onboardingCompleted =
        preferences.getBool(OnboardingPage.completedStorageKey) ?? false;
    if (!onboardingCompleted) {
      navigator.go('/onboarding');
      return;
    }

    final profile = await AppRouter.getProfile(user.id).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        debugPrint(
          'Splash: timeout ao carregar perfil; usando destino cliente.',
        );
        return null;
      },
    );
    if (!mounted) return;
    final role = profile?['role']?.toString() ?? 'client';
    final kycStatus = profile?['kyc_status']?.toString();
    navigator.go(
      AppRouter.destinationForRole(
        role,
        kycStatus: kycStatus,
        emailConfirmed: true,
        phoneVerificationRequired: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppColors.primaryRed,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _SplashGlowPainter(_controller.value),
                    );
                  },
                ),
              ),
            ),
            if (_showPoweredBy)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        'Uma plataforma do ecossistema — DeliGo Triunfal, LDA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.3,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Tecnologia moçambicana.',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              )
            else
              Positioned.fill(
                child: ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: Image.asset(
                      'assets/1000162336.png',
                      fit: BoxFit.contain,
                      semanticLabel: 'Splash oficial do DeliGo',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SplashGlowPainter extends CustomPainter {
  final double progress;

  _SplashGlowPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();

    paint.shader =
        RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.03),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromCircle(
            center: center,
            radius: size.width * (0.28 + (progress * 0.06)),
          ),
        );

    canvas.drawCircle(center, size.width * (0.30 + (progress * 0.04)), paint);
  }

  @override
  bool shouldRepaint(covariant _SplashGlowPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
