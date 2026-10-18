import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Animated layered radial glow pulsing to the beat and rhythm of music,
/// ported from Wave's DiscBeatGlow with Unmute color harmony.
class DiscBeatGlow extends StatefulWidget {
  const DiscBeatGlow({
    super.key,
    required this.child,
    this.isPlaying = false,
    this.level = 0.5,
    this.beatTick = 0,
    this.palette = defaultPalette,
    this.glowSize = 280,
  });

  final Widget child;
  final bool isPlaying;
  final double level;
  final int beatTick;
  final List<Color> palette;
  final double glowSize;

  static const List<Color> defaultPalette = [
    Color(0xFFE50914), // Unmute Red
    Color(0xFFFF2E56), // Vibrant Neon Red
    Color(0xFF7CF7FF), // Neon Cyan
    Color(0xFFE600FF), // Neon Magenta
    Color(0xFFFF2E88), // Deep Pink
    Color(0xFF00E5FF), // Electric Blue
    Color(0xFF7CFFB2), // Mint Green
    Color(0xFFFFE27A), // Gold Yellow
    Color(0xFF9D4EDD), // Deep Violet
    Color(0xFFFF7A00), // Tangerine
  ];

  @override
  State<DiscBeatGlow> createState() => _DiscBeatGlowState();
}

class _DiscBeatGlowState extends State<DiscBeatGlow>
    with TickerProviderStateMixin {
  late final AnimationController _breatheController;
  late final Animation<double> _breatheAnimation;

  late final AnimationController _colorController;
  late Color _currentColor;
  late Color _targetColor;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _currentColor = widget.palette[_random.nextInt(widget.palette.length)];
    _targetColor = _currentColor;

    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _breatheAnimation = Tween<double>(begin: 0.97, end: 1.04).animate(
      CurvedAnimation(
        parent: _breatheController,
        curve: Curves.easeInOutSine,
      ),
    );

    if (widget.isPlaying) {
      _breatheController.repeat(reverse: true);
    }

    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
        setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant DiscBeatGlow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _breatheController.repeat(reverse: true);
      } else {
        _breatheController.animateTo(0.0,
            duration: const Duration(milliseconds: 400));
      }
    }

    if (widget.beatTick != oldWidget.beatTick ||
        (widget.isPlaying && !oldWidget.isPlaying)) {
      _advanceGlowColor();
    }
  }

  void _advanceGlowColor() {
    final candidates =
        widget.palette.where((c) => c != _targetColor).toList();
    final next = candidates.isNotEmpty
        ? candidates[_random.nextInt(candidates.length)]
        : widget.palette[_random.nextInt(widget.palette.length)];

    _currentColor = Color.lerp(_currentColor, _targetColor, _colorController.value) ?? _targetColor;
    _targetColor = next;
    _colorController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor =
        Color.lerp(_currentColor, _targetColor, _colorController.value) ??
            _targetColor;

    final effectiveLevel =
        widget.isPlaying ? widget.level.clamp(0.2, 1.0) : 0.08;
    final intensity =
        (0.12 + effectiveLevel * 0.58).clamp(0.08, 0.72);
    final scale = 0.92 + effectiveLevel * 0.18;

    return AnimatedBuilder(
      animation: _breatheAnimation,
      builder: (context, _) {
        final breathe = widget.isPlaying ? _breatheAnimation.value : 1.0;
        final outerSize = widget.glowSize * scale * breathe;
        final innerSize = widget.glowSize * 0.82 * scale * breathe;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer blurred radial glow
            Opacity(
              opacity: intensity,
              child: Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      activeColor.withValues(alpha: 0.75),
                      activeColor.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // Inner intensified glow
            Opacity(
              opacity: (intensity * 0.85).clamp(0.0, 1.0),
              child: Container(
                width: innerSize,
                height: innerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      activeColor.withValues(alpha: 0.70),
                      activeColor.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),

            // Center child (vinyl disc)
            widget.child,
          ],
        );
      },
    );
  }
}

/// The rotating vinyl disc from Wave with vinyl grooves, spinning animation,
/// and interactive center action.
class MyWaveDisc extends StatefulWidget {
  const MyWaveDisc({
    super.key,
    required this.spin,
    this.artworkUrl,
    this.size = 210,
    this.enabled = true,
    this.onPlayClick,
  });

  final bool spin;
  final String? artworkUrl;
  final double size;
  final bool enabled;
  final VoidCallback? onPlayClick;

  @override
  State<MyWaveDisc> createState() => _MyWaveDiscState();
}

class _MyWaveDiscState extends State<MyWaveDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );

    if (widget.spin) {
      _spinController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MyWaveDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spin != oldWidget.spin) {
      if (widget.spin) {
        _spinController.repeat();
      } else {
        _spinController.stop();
      }
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return GestureDetector(
      onTap: widget.enabled ? widget.onPlayClick : null,
      child: AnimatedBuilder(
        animation: _spinController,
        builder: (context, _) {
          return Transform.rotate(
            angle: widget.spin ? _spinController.value * 2 * math.pi : 0.0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0F0B0E),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Vinyl grooves custom painting
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _VinylGroovesPainter(),
                      ),
                    ),

                    // Center Wave artwork if available
                    Image.asset(
                      'service_icons/mywave.png',
                      width: size * 0.92,
                      height: size * 0.92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _DefaultWaveCenter(size: size),
                    ),

                    // Subtle vinyl specular glare
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.08),
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.06),
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.08),
                            ],
                            stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Center spindle hole with glass button
                    Container(
                      width: size * 0.36,
                      height: size * 0.36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF140F13).withValues(alpha: 0.88),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.28),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          widget.spin
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: size * 0.18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DefaultWaveCenter extends StatelessWidget {
  const _DefaultWaveCenter({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.85,
      height: size * 0.85,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Color(0xFF261219),
            Color(0xFF160910),
            Color(0xFF0C0508),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.waves_rounded,
          size: size * 0.35,
          color: AppTheme.accent2.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (var r = maxRadius * 0.42; r < maxRadius * 0.94; r += 3.8) {
      paint.color = Colors.white.withValues(alpha: 0.04);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
