import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'service_chip.dart';

class ArtistCard extends StatelessWidget {
  const ArtistCard({
    super.key,
    required this.name,
    required this.source,
    this.imageUrl,
    this.onTap,
  });

  final String name;
  final String source;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          width: 212,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF172136), Color(0xFF121826)],
            ),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.strokeSoft),
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accent2],
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: (imageUrl ?? '').trim().isEmpty
                    ? const Icon(Icons.person_rounded, color: Colors.white)
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person_rounded, color: Colors.white),
                      ),
              ),
              const Spacer(),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ServiceChip(label: source.isEmpty ? 'источник неизвестен' : source),
            ],
          ),
        ),
      ),
    );
  }
}
