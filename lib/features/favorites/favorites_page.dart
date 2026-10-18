import 'package:flutter/material.dart';
import '../../core/controllers/player_controller.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/music_service.dart';
import '../../core/services/playlist_service.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../album/album_page.dart';

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

  bool _loading = true;
  String? _error;
  List<Track> _tracks = const [];

  @override
  void initState() {
    super.initState();
    _load();
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
    final albumService =
        track.source.trim().isEmpty ? 'yandex' : track.source;
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
          service: albumService,
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
        child: Text(
          _error!,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
      );
    }

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
              Row(
                children: [
                  Text(
                    'Избранное',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _load,
                    child: const Text('Обновить'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_tracks.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Избранное пустое',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final track = _tracks[index];

                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F2B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: 54,
                              height: 54,
                              color: const Color(0xFF232838),
                              child: (track.image ?? '').trim().isEmpty
                                  ? const Icon(
                                      Icons.music_note,
                                      color: Colors.white70,
                                    )
                                  : Image.network(
                                      track.image!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) {
                                        return const Icon(
                                          Icons.music_note,
                                          color: Colors.white70,
                                        );
                                      },
                                    ),
                            ),
                          ),
                          title: Text(
                            track.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            track.artist,
                            style: const TextStyle(color: Colors.white60),
                          ),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                onPressed: () => _openAlbum(track),
                                icon: const Icon(Icons.album_outlined),
                                color: Colors.white70,
                                tooltip: 'Открыть альбом',
                              ),
                              IconButton(
                                onPressed: () => _addToPlaylist(track),
                                icon: const Icon(Icons.playlist_add_rounded),
                                color: Colors.white70,
                                tooltip: 'В плейлист',
                              ),
                              IconButton(
                                onPressed: () => _playTrack(track),
                                icon: const Icon(Icons.play_arrow_rounded),
                                color: Colors.white,
                                tooltip: 'Слушать',
                              ),
                              IconButton(
                                onPressed: () => _removeTrack(track),
                                icon: const Icon(Icons.delete_outline_rounded),
                                color: Colors.white70,
                                tooltip: 'Удалить из избранного',
                              ),
                            ],
                          ),
                        ),
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
