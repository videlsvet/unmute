import 'package:flutter/material.dart';

import '../../core/controllers/player_controller.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/music_service.dart';
import '../../core/services/playlist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/premium_components.dart';
import '../../widgets/service_chip.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.musicService,
    required this.authService,
    required this.playerController,
    required this.service,
    this.artistId,
    this.artistName,
    this.onBack,
    this.onOpenAlbum,
  });

  final MusicService musicService;
  final AuthService authService;
  final PlayerController playerController;
  final String service;
  final String? artistId;
  final String? artistName;
  final VoidCallback? onBack;
  final ValueChanged<Track>? onOpenAlbum;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  final PlaylistService _playlistService = PlaylistService();

  bool _loading = true;
  String? _error;
  ArtistResult? _result;
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
      final result = await widget.musicService.loadArtist(
        service: widget.service,
        artistId: widget.artistId,
        artistName: widget.artistName,
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
        const SnackBar(content: Text('Войдите в аккаунт, чтобы сохранять треки')),
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

  void _openAlbum(Track track) {
    final albumId = (track.albumId ?? '').trim();
    if (albumId.isEmpty || widget.onOpenAlbum == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Альбом для этого трека недоступен')),
      );
      return;
    }
    widget.onOpenAlbum!(track);
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

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if ((_error ?? '').isNotEmpty) {
      return EmptyStateWidget(
        title: 'Не удалось открыть артиста',
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
        title: 'Артист не найден',
        subtitle: 'Источник не вернул данные по этому артисту.',
        icon: Icons.mic_external_off_rounded,
      );
    }

    return PremiumSurface(
      padding: EdgeInsets.zero,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArtistHero(
            result: result,
            onBack: _handleBack,
            onRefresh: _load,
            onPlay: result.tracks.isEmpty
                ? null
                : () => widget.playerController.playTracks(result.tracks, startIndex: 0),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Источник',
                    value: result.source.isEmpty ? 'unknown' : result.source,
                    icon: Icons.radio_rounded,
                    isService: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Треки',
                    value: '${result.tracks.length}',
                    icon: Icons.music_note_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: _StatCard(
                    label: 'Профиль',
                    value: 'Artist page',
                    icon: Icons.auto_awesome_rounded,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
            child: SectionHeader(
              title: 'Популярные треки',
              subtitle: 'Быстрый запуск, лайки, плейлисты и переход к альбомам.',
              onSeeAll: () {},
            ),
          ),
          Expanded(
            child: result.tracks.isEmpty
                ? const EmptyStateWidget(
                    title: 'Треки не найдены',
                    subtitle: 'Источник не вернул доступных треков для этого артиста.',
                    icon: Icons.music_off_rounded,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                    itemCount: result.tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final track = result.tracks[index];
                      final canOpenAlbum =
                          widget.onOpenAlbum != null && (track.albumId ?? '').trim().isNotEmpty;
                      return PremiumTrackRow(
                        track: track,
                        index: index,
                        isCurrent: widget.playerController.currentTrack?.id == track.id,
                        isFavorite: _favoriteIds.contains(track.id),
                        onFavorite: () => _toggleFavorite(track),
                        onAlbum: canOpenAlbum ? () => _openAlbum(track) : null,
                        onPlaylist: () => _addToPlaylist(track),
                        onPlay: track.hasPlayableUrl
                            ? () => widget.playerController.playTracks(
                                  result.tracks,
                                  startIndex: index,
                                )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ArtistHero extends StatelessWidget {
  const _ArtistHero({
    required this.result,
    required this.onBack,
    required this.onRefresh,
    required this.onPlay,
  });

  final ArtistResult result;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withValues(alpha: 0.24),
            AppTheme.surfaceRaised.withValues(alpha: 0.9),
            AppTheme.surface.withValues(alpha: 0.96),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _BackButton(onPressed: onBack),
          const SizedBox(width: 16),
          _ArtistAvatar(imageUrl: result.image, radius: 82),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Artist', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Text(
                  result.name,
                  style: Theme.of(context).textTheme.displayLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SourceBadge(source: result.source),
                    _InfoPill('${result.tracks.length} треков'),
                    const _InfoPill('Top tracks'),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Слушать'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Обновить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.favorite_border_rounded),
                      label: const Text('Подписаться'),
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

class _ArtistAvatar extends StatelessWidget {
  const _ArtistAvatar({required this.imageUrl, required this.radius});

  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfaceMuted,
        border: Border.all(color: AppTheme.strokeSoft, width: 1.5),
        boxShadow: AppTheme.premiumShadow(alpha: 0.12),
      ),
      clipBehavior: Clip.antiAlias,
      child: (imageUrl ?? '').trim().isEmpty
          ? Center(child: BrandMark(size: radius, padding: 10, glow: false))
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: BrandMark(size: radius, padding: 10, glow: false),
              ),
            ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PremiumIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: 'Назад',
      onTap: onPressed,
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return ServiceChip(label: source.isEmpty ? 'unknown' : source);
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
