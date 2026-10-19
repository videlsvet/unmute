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

  void _playShuffled(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final shuffled = List<Track>.from(tracks)..shuffle();
    widget.playerController.playTracks(shuffled, startIndex: 0);
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

    final isMobile = MediaQuery.sizeOf(context).width < 720;

    if (isMobile) {
      return AnimatedBuilder(
        animation: widget.playerController,
        builder: (context, _) {
          final isPlaying = widget.playerController.isPlaying &&
              widget.playerController.currentTrack != null &&
              result.tracks.any(
                (t) => t.id == widget.playerController.currentTrack?.id,
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MobileArtistHeader(
                result: result,
                isPlaying: isPlaying,
                onBack: _handleBack,
                onPlay: result.tracks.isEmpty
                    ? null
                    : () {
                        if (isPlaying) {
                          widget.playerController.togglePlayPause();
                        } else {
                          widget.playerController.playTracks(
                            result.tracks,
                            startIndex: 0,
                          );
                        }
                      },
                onShuffle: result.tracks.isEmpty
                    ? null
                    : () => _playShuffled(result.tracks),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  'Популярные треки',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: result.tracks.isEmpty
                    ? const EmptyStateWidget(
                        title: 'Треки не найдены',
                        subtitle:
                            'Источник не вернул доступных треков для этого артиста.',
                        icon: Icons.music_off_rounded,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: result.tracks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final track = result.tracks[index];
                          final canOpenAlbum = widget.onOpenAlbum != null &&
                              (track.albumId ?? '').trim().isNotEmpty;
                          return _MobileArtistTrackRow(
                            track: track,
                            isCurrent: widget.playerController.currentTrack?.id ==
                                track.id,
                            isFavorite: _favoriteIds.contains(track.id),
                            onPlay: track.hasPlayableUrl
                                ? () => widget.playerController.playTracks(
                                      result.tracks,
                                      startIndex: index,
                                    )
                                : null,
                            onFavorite: () => _toggleFavorite(track),
                            onPlaylist: () => _addToPlaylist(track),
                            onAlbum:
                                canOpenAlbum ? () => _openAlbum(track) : null,
                          );
                        },
                      ),
              ),
            ],
          );
        },
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

class _MobileArtistHeader extends StatelessWidget {
  const _MobileArtistHeader({
    required this.result,
    required this.isPlaying,
    required this.onBack,
    required this.onPlay,
    required this.onShuffle,
  });

  final ArtistResult result;
  final bool isPlaying;
  final VoidCallback onBack;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  Widget _buildFallback() {
    return Container(
      color: AppTheme.surfaceMuted,
      child: const Center(
        child: BrandMark(size: 72, padding: 14, glow: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 240,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if ((result.image ?? '').trim().isNotEmpty)
                Image.network(
                  result.image!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildFallback(),
                )
              else
                _buildFallback(),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.35, 0.72, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onBack,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: Text(
                  result.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${result.tracks.length} треков',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (result.source.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        result.source,
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.shuffle_rounded),
                color: Colors.white70,
                iconSize: 26,
                tooltip: 'Перемешать',
                onPressed: onShuffle,
              ),
              const SizedBox(width: 8),
              Material(
                color: AppTheme.accent,
                shape: const CircleBorder(),
                elevation: 6,
                shadowColor: AppTheme.accent.withValues(alpha: 0.35),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPlay,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileArtistTrackRow extends StatelessWidget {
  const _MobileArtistTrackRow({
    required this.track,
    required this.isCurrent,
    required this.isFavorite,
    required this.onPlay,
    required this.onFavorite,
    required this.onPlaylist,
    this.onAlbum,
  });

  final Track track;
  final bool isCurrent;
  final bool isFavorite;
  final VoidCallback? onPlay;
  final VoidCallback onFavorite;
  final VoidCallback onPlaylist;
  final VoidCallback? onAlbum;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: (track.image ?? '').trim().isEmpty
                      ? Container(
                          color: AppTheme.surfaceMuted,
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Colors.white60,
                            size: 20,
                          ),
                        )
                      : Image.network(
                          track.image!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.surfaceMuted,
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white60,
                              size: 20,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? AppTheme.accent
                            : (track.hasPlayableUrl
                                ? Colors.white
                                : Colors.white54),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? AppTheme.accent : Colors.white60,
                  size: 20,
                ),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip:
                    isFavorite ? 'Удалить из избранного' : 'В избранное',
                onPressed: onFavorite,
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white60,
                  size: 20,
                ),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Ещё',
                color: AppTheme.surfaceRaised,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                onSelected: (value) {
                  if (value == 'playlist') {
                    onPlaylist();
                  } else if (value == 'album') {
                    onAlbum?.call();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'playlist',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_add_rounded,
                            size: 20, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          'Добавить в плейлист',
                          style: TextStyle(color: Colors.white, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                  if (onAlbum != null)
                    const PopupMenuItem<String>(
                      value: 'album',
                      child: Row(
                        children: [
                          Icon(Icons.album_outlined,
                              size: 20, color: Colors.white),
                          SizedBox(width: 12),
                          Text(
                            'Открыть альбом',
                            style:
                                TextStyle(color: Colors.white, fontSize: 13.5),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
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
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ИСПОЛНИТЕЛЬ', style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Text(result.name, style: compact ? Theme.of(context).textTheme.displaySmall : Theme.of(context).textTheme.displayLarge,
            maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _SourceBadge(source: result.source),
            _InfoPill('${result.tracks.length} треков'),
          ]),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ElevatedButton.icon(onPressed: onPlay, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Слушать')),
            OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Обновить')),
          ]),
        ],
      );
      return Container(
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: const BoxDecoration(color: AppTheme.surface),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _BackButton(onPressed: onBack),
          SizedBox(height: compact ? 18 : 10),
          if (compact) ...[
            Center(child: _ArtistAvatar(imageUrl: result.image, radius: 76)),
            const SizedBox(height: 22),
            details,
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _ArtistAvatar(imageUrl: result.image, radius: 82),
              const SizedBox(width: 24),
              Expanded(child: details),
            ]),
        ]),
      );
    });
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
