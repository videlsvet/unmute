import 'package:flutter/material.dart';

import '../../core/controllers/player_controller.dart';
import '../../core/models/artist.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/music_service.dart';
import '../../core/services/playlist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/premium_components.dart';
import '../../widgets/service_chip.dart';
import '../../widgets/ui_kit.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.musicService,
    required this.authService,
    required this.playerController,
    required this.service,
    required this.albumId,
    this.ownerId,
    this.accessKey,
    this.onBack,
    this.onOpenArtist,
  });

  final MusicService musicService;
  final AuthService authService;
  final PlayerController playerController;
  final String service;
  final String albumId;
  final String? ownerId;
  final String? accessKey;
  final VoidCallback? onBack;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final PlaylistService _playlistService = PlaylistService();

  bool _loading = true;
  String? _error;
  AlbumResult? _result;
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadFavorites() async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) {
      _favoriteIds = {};
      return;
    }
    try {
      final items = await widget.authService.listFavorites(token);
      _favoriteIds = items.map((e) => e.id).toSet();
    } catch (_) {
      _favoriteIds = {};
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadFavorites();
      final result = await widget.musicService.loadAlbum(
        service: widget.service,
        albumId: widget.albumId,
        ownerId: widget.ownerId,
        accessKey: widget.accessKey,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite(Track track) async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Войдите в аккаунт, чтобы сохранять избранное')),
      );
      return;
    }

    try {
      if (_favoriteIds.contains(track.id)) {
        await widget.authService.removeLike(token: token, trackId: track.id);
        if (!mounted) return;
        setState(() => _favoriteIds.remove(track.id));
      } else {
        await widget.authService.likeTrack(token: token, track: track);
        if (!mounted) return;
        setState(() => _favoriteIds.add(track.id));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка избранного: $e')),
      );
    }
  }

  Future<void> _addToPlaylist(Track track) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AddToPlaylistDialog(
        authService: widget.authService,
        playlistService: _playlistService,
        track: track,
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Трек добавлен в плейлист')),
      );
    }
  }

  Future<void> _playTrack(Track track) async {
    final tracks = _result?.tracks ?? const <Track>[];
    final index = tracks.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      await widget.playerController.playTracks(tracks, startIndex: index);
    } else {
      await widget.playerController.playTrack(track);
    }
  }

  Future<void> _playAll() async {
    final result = _result;
    if (result == null) return;
    final firstPlayable = result.tracks.cast<Track?>().firstWhere(
          (t) => t != null && t.hasPlayableUrl,
          orElse: () => null,
        );
    if (firstPlayable != null) {
      await _playTrack(firstPlayable);
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  ArtistSummary? _primaryArtist(AlbumResult result) {
    for (final track in result.tracks) {
      final name = track.artist.trim();
      if (name.isNotEmpty) {
        return ArtistSummary(
          artistName: name,
          source: track.source.trim().isEmpty ? result.source : track.source,
          artistId: track.artistId,
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if ((_error ?? '').isNotEmpty) {
      return EmptyStateWidget(
        title: 'Не удалось открыть альбом',
        subtitle: _error!,
        icon: Icons.error_outline_rounded,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Повторить'),
        ),
      );
    }

    final result = _result;
    if (result == null) {
      return const EmptyStateWidget(
        title: 'Альбом не найден',
        subtitle: 'Ответ по альбому пустой или недоступен для этого источника.',
        icon: Icons.album_outlined,
      );
    }

    final primaryArtist = _primaryArtist(result);

    return PremiumSurface(
      padding: EdgeInsets.zero,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AlbumHero(
            result: result,
            primaryArtist: primaryArtist,
            onBack: _handleBack,
            onRefresh: _load,
            onPlay: _playAll,
            onOpenArtist: primaryArtist == null || widget.onOpenArtist == null
                ? null
                : () => widget.onOpenArtist!(primaryArtist),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Row(
              children: [
                Expanded(
                  child: _AlbumStat(
                    label: 'Источник',
                    value: result.source.isEmpty ? 'unknown' : result.source,
                    icon: Icons.radio_rounded,
                    isService: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AlbumStat(
                    label: 'Треки',
                    value: '${result.tracks.length}',
                    icon: Icons.music_note_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AlbumStat(
                    label: 'Год',
                    value: result.year?.toString() ?? 'Не указан',
                    icon: Icons.calendar_today_rounded,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
            child: SectionHeader(
              title: 'Треклист',
              subtitle:
                  'Запускайте треки, сохраняйте избранное и открывайте артиста прямо из списка.',
              onSeeAll: () {},
            ),
          ),
          Expanded(
            child: result.tracks.isEmpty
                ? const EmptyStateWidget(
                    title: 'Треки не найдены',
                    subtitle:
                        'Этот альбом не вернул доступных для воспроизведения треков.',
                    icon: Icons.album_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                    itemCount: result.tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final track = result.tracks[index];
                      final canOpenArtist = widget.onOpenArtist != null &&
                          track.artist.trim().isNotEmpty;
                      return PremiumTrackRow(
                        track: track,
                        index: index,
                        isCurrent: widget.playerController.currentTrack?.id ==
                            track.id,
                        isFavorite: _favoriteIds.contains(track.id),
                        onPlay: track.hasPlayableUrl
                            ? () => _playTrack(track)
                            : null,
                        onFavorite: () => _toggleFavorite(track),
                        onArtist: canOpenArtist
                            ? (artist) => widget.onOpenArtist!(artist)
                            : null,
                        onPlaylist: () => _addToPlaylist(track),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlbumHero extends StatelessWidget {
  const _AlbumHero({
    required this.result,
    required this.primaryArtist,
    required this.onBack,
    required this.onRefresh,
    required this.onPlay,
    required this.onOpenArtist,
  });

  final AlbumResult result;
  final ArtistSummary? primaryArtist;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onPlay;
  final VoidCallback? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXl)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withValues(alpha: 0.26),
            AppTheme.surfaceRaised.withValues(alpha: 0.92),
            AppTheme.surface.withValues(alpha: 0.97),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          PremiumIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Назад',
            onTap: onBack,
          ),
          const SizedBox(width: 16),
          UnmuteArtwork(
            imageUrl: result.image,
            size: 178,
            radius: AppTheme.radiusXl,
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Album', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Text(
                  result.title,
                  style: Theme.of(context).textTheme.displayLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (primaryArtist != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: onOpenArtist,
                    icon: const Icon(Icons.person_outline_rounded),
                    label: Text(primaryArtist!.artistName),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Слушать всё'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Обновить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.favorite_border_rounded),
                      label: const Text('Сохранить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Поделиться'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumStat extends StatelessWidget {
  const _AlbumStat({
    required this.label,
    required this.value,
    required this.icon,
    this.isService = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isService;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.all(14),
      radius: AppTheme.radiusLg,
      color: AppTheme.surfaceMuted.withValues(alpha: 0.42),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent2, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 3),
                if (isService)
                  ServiceChip(label: value)
                else
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
