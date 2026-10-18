import 'package:flutter/material.dart';

import '../core/models/track.dart';
import '../theme/app_theme.dart';
import 'service_chip.dart';
import 'ui_kit.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.index,
    this.onTap,
    this.onPlay,
    this.onFavorite,
    this.onArtist,
    this.onAlbum,
    this.onPlaylist,
    this.onRemove,
    this.isFavorite = false,
    this.isCurrent = false,
  });

  final Track track;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onArtist;
  final VoidCallback? onAlbum;
  final VoidCallback? onPlaylist;
  final VoidCallback? onRemove;
  final bool isFavorite;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isCurrent
              ? [
                  AppTheme.accent.withValues(alpha: 0.22),
                  AppTheme.surfaceRaised.withValues(alpha: 0.92),
                ]
              : [
                  AppTheme.surface.withValues(alpha: 0.98),
                  AppTheme.surfaceSoft.withValues(alpha: 0.88),
                ],
        ),
        border: Border.all(
          color: isCurrent
              ? AppTheme.accent.withValues(alpha: 0.58)
              : AppTheme.stroke,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: isCurrent
                      ? const Icon(
                          Icons.graphic_eq_rounded,
                          color: AppTheme.accent,
                          size: 18,
                        )
                      : Text(
                          index == null ? '' : '${index! + 1}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                ),
                const SizedBox(width: 8),
                UnmuteArtwork(imageUrl: track.image, size: 54, radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: isCurrent
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                ),
                      ),
                      const SizedBox(height: 3),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: onArtist,
                        child: Text(
                          track.artist.isEmpty
                              ? 'Неизвестный артист'
                              : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    decoration: onArtist == null
                                        ? TextDecoration.none
                                        : TextDecoration.underline,
                                    decorationColor: AppTheme.textMuted,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (track.source.trim().isNotEmpty)
                            ServiceChip(label: track.source),
                          if ((track.albumTitle ?? '').trim().isNotEmpty)
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: onAlbum,
                              child: ServiceChip(
                                label: track.albumTitle!,
                                icon: Icons.album_rounded,
                              ),
                            ),
                          if (!track.hasPlayableUrl)
                            const ServiceChip(
                              label: 'Нет превью',
                              icon: Icons.block_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (onFavorite != null)
                      _ActionButton(
                        icon: isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: const Color(0xFFFF708C),
                        tooltip: 'В избранное',
                        onPressed: onFavorite,
                      ),
                    if (onArtist != null)
                      _ActionButton(
                        icon: Icons.person_outline_rounded,
                        tooltip: 'Открыть артиста',
                        onPressed: onArtist,
                      ),
                    if (onAlbum != null)
                      _ActionButton(
                        icon: Icons.album_outlined,
                        tooltip: 'Открыть альбом',
                        onPressed: onAlbum,
                      ),
                    if (onPlaylist != null)
                      _ActionButton(
                        icon: Icons.playlist_add_rounded,
                        tooltip: 'Добавить в плейлист',
                        onPressed: onPlaylist,
                      ),
                    if (onRemove != null)
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Удалить',
                        onPressed: onRemove,
                      ),
                    if (onPlay != null)
                      _ActionButton(
                        icon: Icons.play_arrow_rounded,
                        color: Colors.white,
                        filled: true,
                        tooltip: 'Слушать',
                        onPressed: onPlay,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppTheme.textSecondary,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: filled
                ? AppTheme.accent.withValues(alpha: 0.94)
                : AppTheme.surfaceMuted.withValues(alpha: 0.72),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
