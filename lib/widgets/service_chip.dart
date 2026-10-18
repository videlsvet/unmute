import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ServiceChip extends StatelessWidget {
  const ServiceChip({
    super.key,
    required this.label,
    this.icon,
    this.showLabel,
  });

  final String label;
  final IconData? icon;
  final bool? showLabel;

  @override
  Widget build(BuildContext context) {
    final service = ServiceVisuals.fromSource(label);
    final shouldShowLabel = showLabel ?? service.assetPath == null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: shouldShowLabel ? 8 : 6,
          vertical: 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (service.assetPath != null)
              _ServiceImage(assetPath: service.assetPath!, size: 14)
            else if (icon != null) ...[
              Icon(icon, size: 12, color: AppTheme.textSecondary),
            ],
            if (shouldShowLabel) ...[
              if (service.assetPath != null || icon != null)
                const SizedBox(width: 5),
              Text(
                service.displayLabel,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ServiceDropdownItem extends StatelessWidget {
  const ServiceDropdownItem({
    super.key,
    required this.source,
    this.compact = true,
  });

  final String source;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final service = ServiceVisuals.fromSource(source);
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (service.assetPath != null)
          _ServiceImage(assetPath: service.assetPath!, size: 18)
        else
          Icon(
            Icons.radio_rounded,
            size: 16,
            color: AppTheme.textSecondary,
          ),
        const SizedBox(width: 8),
        Text(service.displayLabel),
      ],
    );
  }
}

class ServiceIcon extends StatelessWidget {
  const ServiceIcon({
    super.key,
    required this.source,
    this.size = 16,
  });

  final String source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final service = ServiceVisuals.fromSource(source);
    if (service.assetPath == null) {
      return Icon(
        Icons.radio_rounded,
        size: size,
        color: AppTheme.textSecondary,
      );
    }
    return _ServiceImage(assetPath: service.assetPath!, size: size);
  }
}

class ServiceVisuals {
  const ServiceVisuals({
    required this.source,
    required this.displayLabel,
    required this.assetPath,
  });

  final String source;
  final String displayLabel;
  final String? assetPath;

  static ServiceVisuals fromSource(String rawSource) {
    final normalized = rawSource.trim().toLowerCase();
    switch (normalized) {
      case 'yandex':
      case 'yandexmusic':
      case 'yandex music':
        return const ServiceVisuals(
          source: 'yandex',
          displayLabel: 'Yandex Music',
          assetPath: 'service_icons/yandexmusic.jpg',
        );
      case 'vkmusic':
      case 'vk':
      case 'vk music':
        return const ServiceVisuals(
          source: 'vkmusic',
          displayLabel: 'VK Music',
          assetPath: 'service_icons/vkmusic.png',
        );
      case 'soundcloud':
        return const ServiceVisuals(
          source: 'soundcloud',
          displayLabel: 'SoundCloud',
          assetPath: 'service_icons/soundcloud.jpg',
        );
      case 'spotify':
        return const ServiceVisuals(
          source: 'spotify',
          displayLabel: 'Spotify',
          assetPath: null,
        );
      default:
        return ServiceVisuals(
          source: normalized,
          displayLabel: rawSource.trim().isEmpty ? 'unknown' : rawSource,
          assetPath: null,
        );
    }
  }
}

class _ServiceImage extends StatelessWidget {
  const _ServiceImage({
    required this.assetPath,
    required this.size,
  });

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.radio_rounded,
          size: size,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
