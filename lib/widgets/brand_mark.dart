import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 56,
    this.padding = 8,
    this.glow = true,
    this.background,
  });

  final double size;
  final double padding;
  final bool glow;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            background ?? AppTheme.surfaceRaised,
            AppTheme.surfaceSoft,
          ],
        ),
        border: Border.all(color: AppTheme.strokeSoft),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.24),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Image.asset(
        'ic_launcher_foreground.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
