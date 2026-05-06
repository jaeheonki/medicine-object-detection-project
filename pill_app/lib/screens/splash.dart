import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashScreen(),
  ));
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  static const Color primaryColor = Color(0xFF3629B7);

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _waveController;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _waveAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _waveAnim = CurvedAnimation(parent: _waveController, curve: Curves.easeOut);

    _waveController.forward();
    _fadeController.forward();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _slideController.forward();
    });

    // ✅ 2.5초 후 홈화면으로 전환
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HomeScreen(
              onResults: (results) {},
            ),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          // 하단 흰색 물결
          AnimatedBuilder(
            animation: _waveAnim,
            builder: (_, __) {
              final waveTop = size.height * (0.45 + (1 - _waveAnim.value) * 0.55);
              return Positioned(
                top: waveTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomPaint(
                  painter: _WavePainter(),
                  size: Size(size.width, size.height - waveTop),
                ),
              );
            },
          ),

          // 로고 + 텍스트
          Positioned(
            top: size.height * 0.29,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // 45도 기울어진 알약 로고
                    Transform.rotate(
                      angle: -0.785,
                      child: const _PillIcon(size: 58),
                    ),
                    const SizedBox(height: 16),

                    // '이게' — 흰색 볼드
                    const Text(
                      '이게',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),

                    // '머약' — 검정 볼드
                    const Text(
                      '머약',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 알약 아이콘
class _PillIcon extends StatelessWidget {
  final double size;
  const _PillIcon({this.size = 48});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PillPainter(),
    );
  }
}

class _PillPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.05, h * 0.25, w * 0.9, h * 0.5),
      Radius.circular(h * 0.25),
    );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * 0.5, h));
    canvas.drawRRect(pillRect, Paint()..color = const Color(0xFFFAFAFA));
    canvas.restore();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(w * 0.5, 0, w * 0.5, h));
    canvas.drawRRect(pillRect, Paint()..color = const Color(0xFF3BA4EF));
    canvas.restore();

    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PillPainter old) => false;
}

// 물결 배경
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    final path = Path();
    path.moveTo(0, size.height * 0.2);
    path.quadraticBezierTo(
      size.width * 0.5, -size.height * 0.15,
      size.width, size.height * 0.2,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}
