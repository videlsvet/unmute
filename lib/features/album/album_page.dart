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

  Future<void> _toggleFavoriteAll(AlbumResult result) async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Войдите в аккаунт, чтобы сохранять избранное')),
      );
      return;
    }

    final allFav = result.tracks.isNotEmpty &&
        result.tracks.every((t) => _favoriteIds.contains(t.id));

    try {
      if (allFav) {
        for (final t in result.tracks) {
          if (_favoriteIds.contains(t.id)) {
            await widget.authService.removeLike(token: token, trackId: t.id);
          }
        }
        if (!mounted) return;
        setState(() {
          for (final t in result.tracks) {
            _favoriteIds.remove(t.id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Альбом удален из избранного')),
        );
      } else {
        for (final t in result.tracks) {
          if (!_favoriteIds.contains(t.id)) {
            await widget.authService.likeTrack(token: token, track: t);
          }
        }
        if (!mounted) return;
        setState(() {
          for (final t in result.tracks) {
            _favoriteIds.add(t.id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Альбом добавлен в избранное')),
        );
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

  String _formatTrackCount(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$count треков';
    if (mod10 == 1) return '$count трек';
    if (mod10 >= 2 && mod10 <= 4) return '$count трека';
    return '$count треков';
  }

  void _showTrackActions(Track track) {
    final isFav = _favoriteIds.contains(track.id);
    final canOpenArtist = widget.onOpenArtist != null &&
        track.artist.trim().isNotEmpty;
    final primaryArtist = _result != null ? _primaryArtist(_result!) : null;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF181818),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: AppTheme.surfaceRaised,
                      child: (track.image ?? _result?.image ?? '').isNotEmpty
                          ? Image.network(
                              track.image ?? _result!.image!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white70,
                              ),
                            )
                          : const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white70,
                            ),
                    ),
                  ),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const Divider(color: Colors.white12, height: 20),
                ListTile(
                  leading: Icon(
                    isFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFav ? AppTheme.accent : Colors.white,
                  ),
                  title: Text(
                    isFav ? 'Удалить из избранного' : 'Добавить в избранное',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleFavorite(track);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.playlist_add_rounded,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Добавить в плейлист',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _addToPlaylist(track);
                  },
                ),
                if (canOpenArtist)
                  ListTile(
                    leading: const Icon(
                      Icons.person_outline_rounded,
                      color: Colors.white,
                    ),
                    title: Text(
                      'Перейти к артисту (${track.artist})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      final artistSummary = ArtistSummary(
                        artistName: track.artist.trim(),
                        source: track.source.trim().isEmpty
                            ? (_result?.source ?? '')
                            : track.source,
                        artistId: track.artistId ??
                            (track.artist.trim() == primaryArtist?.artistName
                                ? primaryArtist?.artistId
                                : null),
                      );
                      widget.onOpenArtist?.call(artistSummary);
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.album_outlined,
                    color: Colors.white,
                  ),
                  title: Text(
                    'Альбом (${_result?.title ?? 'Альбом'})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAlbumActions(AlbumResult result) {
    final primaryArtist = _primaryArtist(result);
    final canOpenArtist = primaryArtist != null && widget.onOpenArtist != null;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF181818),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: AppTheme.surfaceRaised,
                      child: (result.image ?? '').isNotEmpty
                          ? Image.network(
                              result.image!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.album_rounded,
                                color: Colors.white70,
                              ),
                            )
                          : const Icon(
                              Icons.album_rounded,
                              color: Colors.white70,
                            ),
                    ),
                  ),
                  title: Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    primaryArtist?.artistName ?? result.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const Divider(color: Colors.white12, height: 20),
                if (canOpenArtist)
                  ListTile(
                    leading: const Icon(
                      Icons.person_outline_rounded,
                      color: Colors.white,
                    ),
                    title: Text(
                      'Перейти к артисту (${primaryArtist.artistName})',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onOpenArtist!(primaryArtist);
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Обновить альбом',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _load();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobile(
    BuildContext context,
    AlbumResult result,
    ArtistSummary? primaryArtist,
  ) {
    return AnimatedBuilder(
      animation: widget.playerController,
      builder: (context, _) {
        final currentTrackId = widget.playerController.currentTrack?.id;
        final isPlaying = widget.playerController.isPlaying;
        final isCurrentAlbumPlaying = isPlaying &&
            result.tracks.any((t) => t.id == currentTrackId);
        final allFavorited = result.tracks.isNotEmpty &&
            result.tracks.every((t) => _favoriteIds.contains(t.id));

        final subtitleParts = <String>[];
        if (result.year != null) {
          subtitleParts.add('${result.year}');
        }
        subtitleParts.add(_formatTrackCount(result.tracks.length));
        if (result.source.trim().isNotEmpty) {
          subtitleParts.add(result.source);
        }
        final subtitle = subtitleParts.join(' • ');

        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            tooltip: 'Назад',
                            onPressed: _handleBack,
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.55),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: UnmuteArtwork(
                              imageUrl: result.image,
                              size: 200,
                              radius: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        result.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (primaryArtist != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: widget.onOpenArtist == null
                              ? null
                              : () => widget.onOpenArtist!(primaryArtist),
                          child: Text(
                            primaryArtist.artistName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              allFavorited
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: allFavorited
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                              size: 26,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            tooltip: allFavorited
                                ? 'Удалить из избранного'
                                : 'В избранное',
                            onPressed: () => _toggleFavoriteAll(result),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: AppTheme.textSecondary,
                              size: 24,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            tooltip: 'Действия',
                            onPressed: () => _showAlbumActions(result),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: widget.playerController.shuffleEnabled
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                              size: 26,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            tooltip: 'Перемешать',
                            onPressed: () {
                              widget.playerController.toggleShuffle();
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () {
                              if (isCurrentAlbumPlaying) {
                                widget.playerController.togglePlayPause();
                              } else {
                                _playAll();
                              }
                            },
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.accent,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accent
                                        .withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isCurrentAlbumPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 32,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (result.tracks.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                    child: EmptyStateWidget(
                      title: 'Треки не найдены',
                      subtitle:
                          'Этот альбом не вернул доступных для воспроизведения треков.',
                      icon: Icons.album_outlined,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = result.tracks[index];
                        final isCurrent = currentTrackId == track.id;
                        final isTrackPlaying = isCurrent && isPlaying;
                        return _MobileTrackRow(
                          track: track,
                          isCurrent: isCurrent,
                          isPlaying: isTrackPlaying,
                          duration: isCurrent
                              ? widget.playerController.duration
                              : null,
                          onTap: track.hasPlayableUrl
                              ? () => _playTrack(track)
                              : null,
                          onMore: () => _showTrackActions(track),
                        );
                      },
                      childCount: result.tracks.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
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
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    if (isMobile) {
      return _buildMobile(context, result, primaryArtist);
    }

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

class _MobileTrackRow extends StatelessWidget {
  const _MobileTrackRow({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onMore,
    this.duration,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback onMore;
  final Duration? duration;

  String? get _formattedDuration {
    final d = duration;
    if (d == null || d <= Duration.zero) return null;
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final playable = track.hasPlayableUrl;
    final durationStr = _formattedDuration;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? AppTheme.accent
                            : (playable ? Colors.white : Colors.white38),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist.isNotEmpty ? track.artist : track.source,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                Icon(
                  isPlaying
                      ? Icons.graphic_eq_rounded
                      : Icons.pause_rounded,
                  color: AppTheme.accent,
                  size: 18,
                ),
              ],
              if (durationStr != null) ...[
                const SizedBox(width: 10),
                Text(
                  durationStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                splashRadius: 20,
                onPressed: onMore,
              ),
            ],
          ),
        ),
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
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('АЛЬБОМ',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Text(result.title,
              style: compact
                  ? Theme.of(context).textTheme.displaySmall
                  : Theme.of(context).textTheme.displayLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (primaryArtist != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
                onPressed: onOpenArtist,
                icon: const Icon(Icons.person_outline_rounded),
                label: Text(primaryArtist!.artistName)),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ElevatedButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Слушать всё')),
            OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Обновить')),
          ]),
        ],
      );
      return Container(
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: const BoxDecoration(color: AppTheme.surface),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PremiumIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Назад',
            onTap: onBack,
          ),
          SizedBox(height: compact ? 18 : 10),
          if (compact) ...[
            Center(
                child: UnmuteArtwork(
                    imageUrl: result.image,
                    size: 218,
                    radius: AppTheme.radiusMd)),
            const SizedBox(height: 22),
            details,
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              UnmuteArtwork(
                  imageUrl: result.image,
                  size: 178,
                  radius: AppTheme.radiusMd),
              const SizedBox(width: 24),
              Expanded(child: details),
            ]),
        ]),
      );
    });
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
