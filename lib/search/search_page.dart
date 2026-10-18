import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_api.dart';

class UnmuteSearchController extends ChangeNotifier {
  UnmuteSearchController({
    required this.api,
    required this.authApi,
    required this.onPlayTrack,
    this.service = 'yandex',
  });

  final SearchApi api;
  final AuthApi authApi;
  final Future<void> Function(TrackResponse track) onPlayTrack;
  final String service;

  static const _historyKey = 'query_history';

  final TextEditingController queryController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<String> searchHistory = [];
  List<ArtistSearchHit> artistHits = [];
  List<TrackResponse> tracks = [];
  Set<String> favoriteIds = {};

  bool loading = false;
  bool loadingMore = false;
  bool hasMore = false;
  bool _initialized = false;

  int nextOffset = 0;
  String activeSearchQuery = '';
  String? error;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadSearchHistory();
    await refreshFavorites();
    scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    queryController.dispose();
    super.dispose();
  }

  Future<void> refreshFavorites() async {
    try {
      final token = await authApi.getSavedToken();
      if (token == null || token.isEmpty) {
        favoriteIds = {};
        notifyListeners();
        return;
      }

      final items = await authApi.listFavorites(token);
      favoriteIds = items.map((e) => e.id ?? '').where((e) => e.isNotEmpty).toSet();
      notifyListeners();
    } catch (_) {}
  }

  bool isFavorite(TrackResponse track) {
    final id = track.id ?? '';
    if (id.isEmpty) return false;
    return favoriteIds.contains(id);
  }

  Future<void> toggleFavorite(TrackResponse track) async {
    final token = await authApi.getSavedToken();
    if (token == null || token.isEmpty) {
      error = 'Сначала войди в аккаунт';
      notifyListeners();
      return;
    }

    final id = track.id ?? '';
    if (id.isEmpty) {
      error = 'У трека нет id';
      notifyListeners();
      return;
    }

    try {
      if (favoriteIds.contains(id)) {
        await authApi.removeLike(token: token, trackId: id);
        favoriteIds.remove(id);
      } else {
        await authApi.likeTrack(token: token, track: track);
        favoriteIds.add(id);
      }
      notifyListeners();
    } catch (e) {
      error = 'Избранное: $e';
      notifyListeners();
    }
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);

    if (raw == null || raw.isEmpty) {
      searchHistory = [];
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        searchHistory = decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        searchHistory = [];
      }
    } catch (_) {
      searchHistory = [];
    }

    notifyListeners();
  }

  Future<void> _saveSearchHistory(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final updated = [...searchHistory];
    updated.removeWhere((e) => e.toLowerCase() == query.toLowerCase());
    updated.insert(0, query);

    searchHistory = updated.take(20).toList();
    await prefs.setString(_historyKey, jsonEncode(searchHistory));
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    searchHistory = [];
    notifyListeners();
  }

  List<TrackResponse> _dedupeTracks(
    List<TrackResponse> existing,
    List<TrackResponse> add,
  ) {
    final keys = existing
        .map((t) => '${t.title ?? ''}|${t.artist ?? ''}|${t.id ?? ''}')
        .toSet();

    final result = [...existing];

    for (final t in add) {
      final key = '${t.title ?? ''}|${t.artist ?? ''}|${t.id ?? ''}';
      if (!keys.contains(key)) {
        keys.add(key);
        result.add(t);
      }
    }

    return result;
  }

  Future<void> performSearch([String? queryOverride]) async {
    final q = (queryOverride ?? queryController.text).trim();
    if (q.isEmpty) return;

    loading = true;
    error = null;
    hasMore = false;
    nextOffset = 0;
    artistHits = [];
    tracks = [];
    activeSearchQuery = q;
    notifyListeners();

    try {
      final page = await api.searchTracksPage(
        service: service,
        query: q,
        limit: 40,
        offset: 0,
      );

      final validTracks = page.tracks.where((t) => (t.error ?? '').isEmpty).toList();

      tracks = validTracks;
      artistHits = page.artists;
      hasMore = page.hasMore;
      nextOffset = page.nextOffset ?? validTracks.length;

      await _saveSearchHistory(q);
    } catch (t) {
      error = 'Ошибка: $t';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreSearch() async {
    final q = activeSearchQuery.trim();
    if (q.isEmpty || !hasMore || loading || loadingMore) return;

    loadingMore = true;
    error = null;
    notifyListeners();

    try {
      final page = await api.searchTracksPage(
        service: service,
        query: q,
        limit: 40,
        offset: nextOffset,
      );

      final add = page.tracks.where((t) => (t.error ?? '').isEmpty).toList();

      if (add.isEmpty) {
        hasMore = false;
      } else {
        tracks = _dedupeTracks(tracks, add);
        hasMore = page.hasMore;
        nextOffset = page.nextOffset ?? (nextOffset + add.length);
      }
    } catch (t) {
      error = 'Подгрузка: $t';
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      loadMoreSearch();
    }
  }

  void applyHistoryQuery(String value) {
    queryController.text = value;
    queryController.selection = TextSelection.fromPosition(
      TextPosition(offset: value.length),
    );
    performSearch(value);
  }

  Future<void> removeHistoryItem(String value) async {
    searchHistory.removeWhere((e) => e.toLowerCase() == value.toLowerCase());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(searchHistory));
    notifyListeners();
  }

  Future<void> playTrack(TrackResponse track) async {
    await onPlayTrack(track);
  }

  void openArtist(ArtistSearchHit artist) {
    debugPrint('OPEN ARTIST: ${artist.artistName}');
  }

  void openAlbum(TrackResponse track) {
    debugPrint('OPEN ALBUM: ${track.albumId}');
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.controller,
  });

  final UnmuteSearchController controller;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  UnmuteSearchController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.init();
    controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: const Color(0xFF0F1115),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Поиск',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller.queryController,
                        onSubmitted: (_) => controller.performSearch(),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Искать треки, артистов, альбомы...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.search, color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF181B22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF2A2F3A)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF2A2F3A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE53935),
                              width: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: controller.loading ? null : () => controller.performSearch(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: controller.loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Найти'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 16, 20),
                    child: _HistoryPanel(controller: controller),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 28, 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141820),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFF252A35)),
                      ),
                      child: controller.error != null
                          ? Center(
                              child: Text(
                                controller.error!,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.redAccent,
                                ),
                              ),
                            )
                          : controller.loading && controller.tracks.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : _ResultsView(controller: controller),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.controller});
  final UnmuteSearchController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141820),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF252A35)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'История поиска',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (controller.searchHistory.isNotEmpty)
                TextButton(
                  onPressed: controller.clearHistory,
                  child: const Text('Очистить'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.searchHistory.isEmpty)
            const Text(
              'История пока пустая',
              style: TextStyle(color: Colors.white60),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: controller.searchHistory.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = controller.searchHistory[index];
                  return Material(
                    color: const Color(0xFF1B1F27),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => controller.applyHistoryQuery(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.history, color: Colors.white70, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: () => controller.removeHistoryItem(item),
                              icon: const Icon(Icons.close, size: 18),
                              color: Colors.white54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.controller});
  final UnmuteSearchController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.activeSearchQuery.isEmpty) {
      return const Center(
        child: Text(
          'Начни вводить запрос',
          style: TextStyle(color: Colors.white60, fontSize: 16),
        ),
      );
    }

    if (controller.tracks.isEmpty && !controller.loading) {
      return const Center(
        child: Text(
          'Ничего не найдено',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return ListView(
      controller: controller.scrollController,
      padding: const EdgeInsets.all(18),
      children: [
        if (controller.artistHits.isNotEmpty) ...[
          const Text(
            'Артисты',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: controller.artistHits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final artist = controller.artistHits[index];
                return _ArtistCard(
                  artist: artist,
                  onTap: () => controller.openArtist(artist),
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
        const SizedBox(height: 14),
        ...controller.tracks.map(
          (track) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TrackTile(
              track: track,
              isFavorite: controller.isFavorite(track),
              onFavorite: () => controller.toggleFavorite(track),
              onPlay: () => controller.playTrack(track),
              onOpenAlbum: () => controller.openAlbum(track),
            ),
          ),
        ),
        if (controller.loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.artist,
    required this.onTap,
  });

  final ArtistSearchHit artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B1F27),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 190,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ArtistAvatar(imageUrl: artist.image),
              const Spacer(),
              Text(
                artist.artistName ?? 'Без имени',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                artist.source ?? '',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistAvatar extends StatelessWidget {
  const _ArtistAvatar({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').trim();

    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFFE53935),
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isFavorite,
    required this.onFavorite,
    required this.onPlay,
    required this.onOpenAlbum,
  });

  final TrackResponse track;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;
  final VoidCallback onOpenAlbum;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1F27),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: _TrackCover(imageUrl: track.image),
        title: Text(
          track.title ?? 'Без названия',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          track.artist ?? '',
          style: const TextStyle(color: Colors.white60),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              onPressed: onFavorite,
              icon: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              ),
              color: const Color(0xFFE53935),
              tooltip: 'Избранное',
            ),
            IconButton(
              onPressed: onOpenAlbum,
              icon: const Icon(Icons.album_outlined),
              color: Colors.white70,
              tooltip: 'Открыть альбом',
            ),
            IconButton(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              color: Colors.white,
              tooltip: 'Слушать',
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackCover extends StatelessWidget {
  const _TrackCover({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        color: const Color(0xFF2A2F3A),
        child: url.isEmpty
            ? const Icon(Icons.music_note, color: Colors.white70)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Icon(Icons.music_note, color: Colors.white70);
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
      ),
    );
  }
}