import 'package:flutter/material.dart';
import '../../core/controllers/player_controller.dart';
import '../../core/models/artist.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/music_service.dart';
import '../../core/services/playlist_service.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../album/album_page.dart';
import '../artist/artist_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.musicService,
    required this.authService,
    required this.playerController,
  });

  final MusicService musicService;
  final AuthService authService;
  final PlayerController playerController;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PlaylistService _playlistService = PlaylistService();

  final List<Track> _tracks = [];
  final List<ArtistSummary> _artists = [];

  String _service = 'yandex';
  String _activeQuery = '';
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  String? _error;
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _favoriteIds = {};
      });
      return;
    }

    try {
      final favorites = await widget.authService.listFavorites(token);
      if (!mounted) return;
      setState(() {
        _favoriteIds = favorites.map((e) => e.id).toSet();
      });
    } catch (_) {}
  }

  Future<void> _search({bool reset = true}) async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _activeQuery = query;
        _tracks.clear();
        _artists.clear();
        _nextOffset = 0;
        _hasMore = false;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final result = await widget.musicService.search(
        service: _service,
        query: query,
        limit: 40,
        offset: reset ? 0 : _nextOffset,
      );

      if (!mounted) return;

      setState(() {
        if (reset) {
          _tracks.addAll(result.tracks);
          _artists.addAll(result.artists);
        } else {
          _tracks.addAll(result.tracks);
        }
        _hasMore = result.hasMore;
        _nextOffset = result.nextOffset;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) return;
    final p = _scrollController.position;
    if (p.pixels >= p.maxScrollExtent - 250) {
      _search(reset: false);
    }
  }

  Future<void> _toggleFavorite(Track track) async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала войди в аккаунт')),
      );
      return;
    }

    try {
      if (_favoriteIds.contains(track.id)) {
        await widget.authService.removeLike(token: token, trackId: track.id);
        if (!mounted) return;
        setState(() {
          _favoriteIds.remove(track.id);
        });
      } else {
        await widget.authService.likeTrack(token: token, track: track);
        if (!mounted) return;
        setState(() {
          _favoriteIds.add(track.id);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Избранное: $e')),
      );
    }
  }

  Future<void> _openArtist(ArtistSummary artist) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistPage(
          musicService: widget.musicService,
          authService: widget.authService,
          playerController: widget.playerController,
          service: artist.source.isEmpty ? _service : artist.source,
          artistId: artist.artistId,
          artistName: artist.artistName,
        ),
      ),
    );
    await _loadFavorites();
  }

  Future<void> _openAlbum(Track track) async {
    final albumId = (track.albumId ?? '').trim();
    final albumService = track.source.trim().isEmpty ? _service : track.source;
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
          musicService: widget.musicService,
          authService: widget.authService,
          playerController: widget.playerController,
          service: albumService,
          albumId: albumId,
          ownerId: track.ownerId,
          accessKey: track.accessKey,
        ),
      ),
    );
    await _loadFavorites();
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
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              Text('Поиск', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: 'Искать треки, артистов, альбомы...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _service,
                    dropdownColor: const Color(0xFF1A1F2B),
                    borderRadius: BorderRadius.circular(16),
                    items: const [
                      DropdownMenuItem(value: 'yandex', child: Text('Yandex')),
                      DropdownMenuItem(value: 'vkmusic', child: Text('VK Music')),
                      DropdownMenuItem(value: 'soundcloud', child: Text('SoundCloud')),
                      DropdownMenuItem(value: 'spotify', child: Text('Spotify')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _service = value;
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _search,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Найти'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if ((_error ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              Expanded(
                child: _activeQuery.isEmpty
                    ? const Center(
                        child: Text(
                          'Начни поиск',
                          style: TextStyle(color: Colors.white60, fontSize: 16),
                        ),
                      )
                    : ListView(
                        controller: _scrollController,
                        children: [
                          if (_artists.isNotEmpty) ...[
                            const Text(
                              'Артисты',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _artists.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final artist = _artists[index];
                                  return Material(
                                    color: const Color(0xFF1A1F2B),
                                    borderRadius: BorderRadius.circular(20),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () => _openArtist(artist),
                                      child: Container(
                                        width: 190,
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              radius: 26,
                                              backgroundColor: const Color(0xFFB3261E),
                                              backgroundImage: (artist.image ?? '').trim().isNotEmpty
                                                  ? NetworkImage(artist.image!)
                                                  : null,
                                              child: (artist.image ?? '').trim().isEmpty
                                                  ? const Icon(Icons.person, color: Colors.white)
                                                  : null,
                                            ),
                                            const Spacer(),
                                            Text(
                                              artist.artistName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              artist.source,
                                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],
                          const Text(
                            'Треки',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_tracks.isEmpty && !_loading)
                            const Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: Center(
                                child: Text(
                                  'Ничего не найдено',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ..._tracks.map(
                            (track) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
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
                                          ? const Icon(Icons.music_note, color: Colors.white70)
                                          : Image.network(
                                              track.image!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) {
                                                return const Icon(Icons.music_note, color: Colors.white70);
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
                                        onPressed: () => _toggleFavorite(track),
                                        icon: Icon(
                                          _favoriteIds.contains(track.id)
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                        ),
                                        color: const Color(0xFFB3261E),
                                        tooltip: 'Избранное',
                                      ),
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
                                        onPressed: track.hasPlayableUrl
                                            ? () => widget.playerController.playTrack(track)
                                            : null,
                                        icon: const Icon(Icons.play_arrow_rounded),
                                        color: Colors.white,
                                        tooltip: 'Слушать',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
