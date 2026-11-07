import 'package:flutter/material.dart';

import '../core/models/track.dart';
import '../theme/app_theme.dart';
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
          onTap: onTap ?? onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Действия с треком',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    if (onFavorite != null)
                      PopupMenuItem(
                          value: onFavorite,
                          child: Text(isFavorite
                              ? 'Убрать из избранного'
                              : 'В избранное')),
                    if (onArtist != null)
                      PopupMenuItem(
                          value: onArtist,
                          child: const Text('Открыть исполнителя')),
                    if (onAlbum != null)
                      PopupMenuItem(
                          value: onAlbum, child: const Text('Открыть альбом')),
                    if (onPlaylist != null)
                      PopupMenuItem(
                          value: onPlaylist,
                          child: const Text('Добавить в плейлист')),
                    if (onRemove != null)
                      PopupMenuItem(
                          value: onRemove, child: const Text('Удалить')),
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
