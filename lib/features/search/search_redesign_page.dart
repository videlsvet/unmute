import 'dart:async';

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

enum _SearchTab { all, tracks, artists }

class SearchRedesignPage extends StatefulWidget {
  const SearchRedesignPage({
    super.key,
    required this.musicService,
    required this.authService,
    required this.playerController,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  final MusicService musicService;
  final AuthService authService;
  final PlayerController playerController;
  final ValueChanged<Track>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<SearchRedesignPage> createState() => _SearchRedesignPageState();
}

class _SearchRedesignPageState extends State<SearchRedesignPage> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final PlaylistService _playlistService = PlaylistService();

  final List<Track> _tracks = [];
  final List<ArtistSummary> _artists = [];
  final List<String> _recentQueries = [];

  Timer? _debounce;
  String _service = 'yandex';
  String _activeQuery = '';
  _SearchTab _tab = _SearchTab.all;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  String? _error;
  Set<String> _favoriteIds = {};

  static const List<String> _popularHints = [
    'Daft Punk',
    'Radiohead',
    'Fred again..',
    'Massive Attack',
    'Justice',
  ];

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
      setState(() => _favoriteIds = {});
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

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 360), _search);
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
          _tracks
            ..clear()
            ..addAll(result.tracks);
          _artists
            ..clear()
            ..addAll(result.artists);
          _rememberQuery(query);
        } else {
          _tracks.addAll(result.tracks);
        }
        _hasMore = result.hasMore;
        _nextOffset = result.nextOffset;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
    });
  }

  void _rememberQuery(String query) {
    _recentQueries.remove(query);
    _recentQueries.insert(0, query);
    if (_recentQueries.length > 6) {
      _recentQueries.removeRange(6, _recentQueries.length);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 250) {
      _search(reset: false);
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

  void _openArtist(ArtistSummary artist) {
    widget.onOpenArtist?.call(artist);
  }

  void _openAlbum(Track track) {
    final albumId = (track.albumId ?? '').trim();
    if (albumId.isEmpty || widget.onOpenAlbum == null) {
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

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: EdgeInsets.zero,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchHero(
            controller: _queryController,
            service: _service,
            loading: _loading,
            resultCount: _tracks.length + _artists.length,
            onChanged: _scheduleSearch,
            onSubmitted: (_) => _search(),
            onSearchPressed: _loading ? null : _search,
            onServiceChanged: (value) {
              if (value == null) return;
              setState(() => _service = value);
              if (_activeQuery.isNotEmpty) {
                _search();
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
            child: _SearchTabs(
              tab: _tab,
              onChanged: (tab) => setState(() => _tab = tab),
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if ((_error ?? '').isNotEmpty) {
      return EmptyStateWidget(
        title: 'Поиск не удался',
        subtitle: _error!,
        icon: Icons.error_outline_rounded,
        action: OutlinedButton.icon(
          onPressed: _search,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Повторить'),
        ),
      );
    }

    if (_activeQuery.isEmpty) {
      return _SearchDiscoveryState(
        recentQueries: _recentQueries,
        popularHints: _popularHints,
        onSelect: (value) {
          _queryController.text = value;
          _search();
        },
      );
    }

    if (_loading) {
      return const _SearchSkeleton();
    }

    final showTracks = _tab == _SearchTab.all || _tab == _SearchTab.tracks;
    final showArtists = _tab == _SearchTab.all || _tab == _SearchTab.artists;

    if (_tracks.isEmpty && _artists.isEmpty) {
      return const EmptyStateWidget(
        title: 'Ничего не найдено',
        subtitle:
            'Попробуйте сократить запрос, сменить источник или выбрать одну из подсказок.',
        icon: Icons.music_off_rounded,
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      children: [
        if (showArtists && _artists.isNotEmpty) ...[
          SectionHeader(
            title: 'Артисты',
            subtitle: 'Откройте профиль артиста и перейдите к его трекам.',
            onSeeAll: () => setState(() => _tab = _SearchTab.artists),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 226,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final artist = _artists[index];
                return MediaCard(
                  title: artist.artistName,
                  subtitle: artist.source,
                  imageUrl: artist.image,
                  circle: true,
                  onTap: widget.onOpenArtist == null
                      ? null
                      : () => _openArtist(artist),
                  onPlay: widget.onOpenArtist == null
                      ? null
                      : () => _openArtist(artist),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (showTracks) ...[
          SectionHeader(
            title: 'Треки',
            subtitle:
                '${_tracks.length} результатов: слушайте, сохраняйте и открывайте альбомы.',
            onSeeAll: () => setState(() => _tab = _SearchTab.tracks),
          ),
          const SizedBox(height: 14),
          ..._tracks.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PremiumTrackRow(
                    track: entry.value,
                    index: entry.key,
                    isCurrent: widget.playerController.currentTrack?.id ==
                        entry.value.id,
                    isFavorite: _favoriteIds.contains(entry.value.id),
                    onFavorite: () => _toggleFavorite(entry.value),
                    onArtist: widget.onOpenArtist != null &&
                            entry.value.artist.trim().isNotEmpty
                        ? (artist) => _openArtist(
                              ArtistSummary(
                                artistName: artist.artistName,
                                source: artist.source.isEmpty
                                    ? _service
                                    : artist.source,
                                artistId: artist.artistId,
                              ),
                            )
                        : null,
                    onAlbum: () => _openAlbum(entry.value),
                    onPlaylist: () => _addToPlaylist(entry.value),
                    onPlay: entry.value.hasPlayableUrl
                        ? () => widget.playerController.playTracks(
                              _tracks,
                              startIndex: entry.key,
                            )
                        : null,
                  ),
                ),
              ),
        ],
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _SearchHero extends StatelessWidget {
  const _SearchHero({
    required this.controller,
    required this.service,
    required this.loading,
    required this.resultCount,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSearchPressed,
    required this.onServiceChanged,
  });

  final TextEditingController controller;
  final String service;
  final bool loading;
  final int resultCount;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onSearchPressed;
  final ValueChanged<String?> onServiceChanged;

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
            AppTheme.accent.withValues(alpha: 0.22),
            AppTheme.surfaceRaised.withValues(alpha: 0.92),
            AppTheme.surface.withValues(alpha: 0.98),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Search',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 6),
                    Text('Поиск музыки',
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 8),
                    Text(
                      'Треки, альбомы, артисты и плейлисты из подключённых источников.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              _HeroMetric(label: 'Результаты', value: '$resultCount'),
              _HeroMetric(label: 'Источник', value: service),
            ],
          ),
          const SizedBox(height: 20),
          PremiumSurface(
            padding: const EdgeInsets.all(12),
            radius: AppTheme.radiusLg,
            color: AppTheme.surfaceMuted.withValues(alpha: 0.42),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final search = PremiumSearchBar(
                  controller: controller,
                  hint: 'Искать треки, артистов, альбомы...',
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                );
                final controls = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: service,
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(16),
                      items: const [
                        DropdownMenuItem(
                          value: 'yandex',
                          child: ServiceDropdownItem(source: 'yandex'),
                        ),
                        DropdownMenuItem(
                          value: 'vkmusic',
                          child: ServiceDropdownItem(source: 'vkmusic'),
                        ),
                        DropdownMenuItem(
                          value: 'soundcloud',
                          child: ServiceDropdownItem(source: 'soundcloud'),
                        ),
                        DropdownMenuItem(
                          value: 'spotify',
                          child: ServiceDropdownItem(source: 'spotify'),
                        ),
                      ],
                      onChanged: onServiceChanged,
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: onSearchPressed,
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Найти'),
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    children: [
                      search,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: controls),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 12),
                    controls,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTabs extends StatelessWidget {
  const _SearchTabs({required this.tab, required this.onChanged});

  final _SearchTab tab;
  final ValueChanged<_SearchTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_SearchTab.all, 'Все'),
      (_SearchTab.tracks, 'Треки'),
      (_SearchTab.artists, 'Артисты'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        final selected = tab == item.$1;
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(item.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.18)
                  : AppTheme.surfaceMuted.withValues(alpha: 0.44),
              border: Border.all(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.5)
                    : AppTheme.stroke,
              ),
            ),
            child:
                Text(item.$2, style: Theme.of(context).textTheme.labelMedium),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _SearchDiscoveryState extends StatelessWidget {
  const _SearchDiscoveryState({
    required this.recentQueries,
    required this.popularHints,
    required this.onSelect,
  });

  final List<String> recentQueries;
  final List<String> popularHints;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final recent = recentQueries.isEmpty ? const ['Daft Punk'] : recentQueries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      children: [
        EmptyStateWidget(
          title: 'Начните с поиска',
          subtitle:
              'Введите артиста, трек или альбом. Подсказки ниже помогут быстро проверить выдачу.',
          icon: Icons.travel_explore_rounded,
          action: OutlinedButton.icon(
            onPressed: () => onSelect('Daft Punk'),
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Попробовать пример'),
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeader(title: 'Недавние запросы'),
        const SizedBox(height: 12),
        _HintWrap(
            items: recent, icon: Icons.history_rounded, onSelect: onSelect),
        const SizedBox(height: 18),
        const SectionHeader(title: 'Популярные подсказки'),
        const SizedBox(height: 12),
        _HintWrap(
            items: popularHints,
            icon: Icons.local_fire_department_rounded,
            onSelect: onSelect),
      ],
    );
  }
}

class _HintWrap extends StatelessWidget {
  const _HintWrap({
    required this.items,
    required this.icon,
    required this.onSelect,
  });

  final List<String> items;
  final IconData icon;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((query) {
        return OutlinedButton.icon(
          onPressed: () => onSelect(query),
          icon: Icon(icon),
          label: Text(query),
        );
      }).toList(growable: false),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().toLowerCase();
    final looksLikeService = {
      'yandex',
      'vkmusic',
      'soundcloud',
      'spotify',
      'local',
      'unknown',
    }.contains(normalized);

    return PremiumSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      radius: AppTheme.radiusLg,
      color: Colors.black.withValues(alpha: 0.2),
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (looksLikeService)
            ServiceChip(label: value)
          else
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Column(
        children: [
          LoadingSkeleton(height: 64),
          SizedBox(height: 10),
          LoadingSkeleton(height: 64),
          SizedBox(height: 10),
          LoadingSkeleton(height: 64),
        ],
      ),
    );
  }
}
