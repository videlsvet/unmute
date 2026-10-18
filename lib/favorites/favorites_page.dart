import 'package:flutter/material.dart';
import '../../core/controllers/player_controller.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/music_service.dart';
import '../../core/services/playlist_service.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../features/album/album_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    required this.authService,
    required this.playerController,
  });

  final AuthService authService;
  final PlayerController playerController;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final PlaylistService _playlistService = PlaylistService();
  final MusicService _musicService = MusicService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Track> _tracks = const [];
  String _searchQuery = '';

  List<Track> get _filteredTracks {
    if (_searchQuery.isEmpty) return _tracks;
    final q = _searchQuery.toLowerCase();
    return _tracks
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await widget.authService.getSavedToken();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Сначала войди в аккаунт';
        });
        return;
      }

      final result = await widget.authService.listFavorites(token);

      if (!mounted) return;
      setState(() {
        _tracks = result;
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

  Future<void> _removeTrack(Track track) async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) return;

    try {
      await widget.authService.removeLike(
        token: token,
        trackId: track.id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Удаление из избранного: $e')),
      );
    }
  }

  Future<void> _playTrack(Track track) async {
    final token = await widget.authService.getSavedToken();

    try {
      Track playableTrack = track;
      final source = track.source.trim().toLowerCase();

      if (token != null && token.isNotEmpty && source == 'yandex') {
        final freshUrl = await widget.authService.getFreshFavoriteStream(
          token: token,
          trackId: track.id,
        );
        playableTrack = track.copyWith(preview: freshUrl);

        if (mounted) {
          setState(() {
            _tracks = _tracks
                .map((t) => t.id == track.id ? playableTrack : t)
                .toList(growable: false);
          });
        }
      }

      await widget.playerController.playTrack(playableTrack);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка воспроизведения: $e')),
      );
    }
  }

  Future<void> _openAlbum(Track track) async {
    final albumId = (track.albumId ?? '').trim();
    if (albumId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У трека нет album_id')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumPage(
          musicService: _musicService,
          authService: widget.authService,
          playerController: widget.playerController,
          service: track.source,
          albumId: albumId,
          ownerId: track.ownerId,
          accessKey: track.accessKey,
        ),
      ),
    );

    await _load();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if ((_error ?? '').isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredTracks;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF232838)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFB3261E),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Избранное',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(width: 10),
                  if (_tracks.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF232838),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_tracks.length}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white54,
                    tooltip: 'Обновить',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Search bar ───────────────────────────────────────
              if (_tracks.isNotEmpty) ...[
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Поиск по избранному…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1A1F2B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Track list ───────────────────────────────────────
              if (_tracks.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_border, color: Colors.white24, size: 56),
                        SizedBox(height: 12),
                        Text(
                          'Избранное пустое',
                          style: TextStyle(color: Colors.white38, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'Ничего не найдено по «$_searchQuery»',
                      style: const TextStyle(color: Colors.white38, fontSize: 15),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final track = filtered[index];
                      return _TrackCard(
                        track: track,
                        index: index,
                        onPlay: () => _playTrack(track),
                        onAlbum: () => _openAlbum(track),
                        onPlaylist: () => _addToPlaylist(track),
                        onRemove: () => _removeTrack(track),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable track card ──────────────────────────────────────────────────────

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.index,
    required this.onPlay,
    required this.onAlbum,
    required this.onPlaylist,
    required this.onRemove,
  });

  final Track track;
  final int index;
  final VoidCallback onPlay;
  final VoidCallback onAlbum;
  final VoidCallback onPlaylist;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232838)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48,
                height: 48,
                color: const Color(0xFF232838),
                child: (track.image ?? '').trim().isEmpty
                    ? const Icon(Icons.music_note,
                        color: Colors.white38, size: 22)
                    : Image.network(
                        track.image!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.music_note,
                            color: Colors.white38,
                            size: 22),
                      ),
              ),
            ),
          ],
        ),
        title: Text(
          track.title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artist,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _TrackActions(
          onPlay: onPlay,
          onAlbum: onAlbum,
          onPlaylist: onPlaylist,
          onRemove: onRemove,
        ),
      ),
    );
  }
}

class _TrackActions extends StatelessWidget {
  const _TrackActions({
    required this.onPlay,
    required this.onAlbum,
    required this.onPlaylist,
    required this.onRemove,
  });

  final VoidCallback onPlay;
  final VoidCallback onAlbum;
  final VoidCallback onPlaylist;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(
          icon: Icons.album_outlined,
          tooltip: 'Открыть альбом',
          onPressed: onAlbum,
        ),
        _ActionIcon(
          icon: Icons.playlist_add_rounded,
          tooltip: 'В плейлист',
          onPressed: onPlaylist,
        ),
        _ActionIcon(
          icon: Icons.play_circle_filled_rounded,
          tooltip: 'Слушать',
          color: Colors.white,
          onPressed: onPlay,
          size: 28,
        ),
        _ActionIcon(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Удалить',
          color: Colors.white38,
          onPressed: onRemove,
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = Colors.white54,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: size),
        ),
      ),
    );
  }
}