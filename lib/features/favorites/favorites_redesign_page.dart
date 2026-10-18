import 'package:flutter/material.dart';

import '../../core/controllers/player_controller.dart';
import '../../core/models/artist.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/playlist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/premium_components.dart';
import '../../widgets/service_chip.dart';

enum _FavoritesSort { recent, title, artist }

class FavoritesRedesignPage extends StatefulWidget {
  const FavoritesRedesignPage({
    super.key,
    required this.authService,
    required this.playerController,
    this.initialTracks = const [],
    this.onTracksChanged,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  final AuthService authService;
  final PlayerController playerController;
  final List<Track> initialTracks;
  final ValueChanged<List<Track>>? onTracksChanged;
  final ValueChanged<Track>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<FavoritesRedesignPage> createState() => _FavoritesRedesignPageState();
}

class _FavoritesRedesignPageState extends State<FavoritesRedesignPage> {
  final PlaylistService _playlistService = PlaylistService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _gridMode = false;
  String? _error;
  List<Track> _tracks = const [];
  String _sourceFilter = 'all';
  _FavoritesSort _sort = _FavoritesSort.recent;

  @override
  void initState() {
    super.initState();
    _tracks = List<Track>.unmodifiable(widget.initialTracks);
    _loading = widget.initialTracks.isEmpty;
    _load();
  }

  @override
  void didUpdateWidget(covariant FavoritesRedesignPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameTrackIds(oldWidget.initialTracks, widget.initialTracks)) {
      setState(() {
        _tracks = List<Track>.unmodifiable(widget.initialTracks);
        _loading = _tracks.isEmpty;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _tracks.isEmpty;
      _error = null;
    });

    try {
      final token = await widget.authService.getSavedToken();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Войдите в аккаунт, чтобы открыть избранное';
        });
        return;
      }

      final result = await widget.authService.listFavorites(token);
      if (!mounted) return;
      setState(() {
        _tracks = List<Track>.unmodifiable(result);
        _loading = false;
      });
      widget.onTracksChanged?.call(_tracks);
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
      await widget.authService.removeLike(token: token, trackId: track.id);
      setState(() {
        _tracks = _tracks
            .where((item) => item.id != track.id)
            .toList(growable: false);
      });
      widget.onTracksChanged?.call(_tracks);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить из избранного: $e')),
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
          widget.onTracksChanged?.call(_tracks);
        }
      }

      final updatedTracks = _visibleTracks
          .map((t) => t.id == track.id ? playableTrack : t)
          .toList(growable: false);
      final index = updatedTracks.indexWhere((t) => t.id == playableTrack.id);
      if (index >= 0) {
        await widget.playerController
            .playTracks(updatedTracks, startIndex: index);
      } else {
        await widget.playerController.playTrack(playableTrack);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка воспроизведения: $e')),
      );
    }
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

  Future<void> _importFavoritesText() async {
    final textController = TextEditingController();
    String service = 'vkmusic';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Импорт в избранное'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: service,
                      isExpanded: true,
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
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() => service = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      minLines: 10,
                      maxLines: 14,
                      decoration: const InputDecoration(
                          hintText: 'Один трек на строку'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Импортировать'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final text = textController.text.trim();
    if (text.isEmpty) return;

    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) return;

    try {
      var offset = 0;
      var done = false;
      while (!done) {
        final result = await _playlistService.importTextToFavorites(
          token: token,
          text: text,
          service: service,
          offset: offset,
          batchSize: 2,
        );
        done = result.done;
        offset = result.nextOffset;
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Импорт в избранное завершён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  List<Track> get _visibleTracks {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _tracks.where((track) {
      final matchesSource =
          _sourceFilter == 'all' || track.source == _sourceFilter;
      final matchesQuery = query.isEmpty ||
          track.title.toLowerCase().contains(query) ||
          track.artist.toLowerCase().contains(query) ||
          (track.albumTitle ?? '').toLowerCase().contains(query);
      return matchesSource && matchesQuery;
    }).toList(growable: false);

    final list = [...filtered];
    switch (_sort) {
      case _FavoritesSort.recent:
        break;
      case _FavoritesSort.title:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _FavoritesSort.artist:
        list.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
    }
    return list;
  }

  bool _sameTrackIds(List<Track> a, List<Track> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTracks = _visibleTracks;
    final uniqueSources = {
      'all',
      ..._tracks
          .map((track) => track.source)
          .where((source) => source.trim().isNotEmpty),
    }.toList(growable: false);

    return PremiumSurface(
      padding: EdgeInsets.zero,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryHero(
            total: _tracks.length,
            visible: visibleTracks.length,
            onRefresh: _load,
            onImport: _importFavoritesText,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
            child: _LibraryToolbar(
              searchController: _searchController,
              sort: _sort,
              gridMode: _gridMode,
              onSearchChanged: (_) => setState(() {}),
              onSortChanged: (value) {
                if (value == null) return;
                setState(() => _sort = value);
              },
              onToggleView: () => setState(() => _gridMode = !_gridMode),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: uniqueSources.map((source) {
                return FilterChipButton(
                  label: source == 'all' ? 'Все источники' : source,
                  selected: _sourceFilter == source,
                  onTap: () => setState(() => _sourceFilter = source),
                );
              }).toList(growable: false),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (_loading) {
                  return const _LibrarySkeleton();
                }
                if ((_error ?? '').isNotEmpty) {
                  return EmptyStateWidget(
                    title: 'Медиатека недоступна',
                    subtitle: _error!,
                    icon: Icons.lock_outline_rounded,
                    action: OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Повторить'),
                    ),
                  );
                }
                if (_tracks.isEmpty) {
                  return const EmptyStateWidget(
                    title: 'Избранное пока пустое',
                    subtitle:
                        'Ставьте лайки в поиске, и треки появятся в этой медиатеке.',
                    icon: Icons.favorite_border_rounded,
                  );
                }
                if (visibleTracks.isEmpty) {
                  return const EmptyStateWidget(
                    title: 'Ничего не найдено',
                    subtitle:
                        'Измените поисковый запрос, источник или сортировку.',
                    icon: Icons.filter_alt_off_rounded,
                  );
                }
                return _gridMode
                    ? _buildGrid(visibleTracks)
                    : _buildList(visibleTracks);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Track> visibleTracks) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      itemCount: visibleTracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final track = visibleTracks[index];
        return PremiumTrackRow(
          track: track,
          index: index,
          isCurrent: widget.playerController.currentTrack?.id == track.id,
          isFavorite: true,
          onFavorite: () => _removeTrack(track),
          onArtist:
              widget.onOpenArtist != null && track.artist.trim().isNotEmpty
                  ? (artist) => widget.onOpenArtist!(artist)
                  : null,
          onAlbum: () => _openAlbum(track),
          onPlaylist: () => _addToPlaylist(track),
          onPlay: () => _playTrack(track),
          onRemove: () => _removeTrack(track),
        );
      },
    );
  }

  Widget _buildGrid(List<Track> visibleTracks) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      itemCount: visibleTracks.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 246,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final track = visibleTracks[index];
        return MediaCard(
          title: track.title,
          subtitle: track.artist.isEmpty ? track.source : track.artist,
          imageUrl: track.image,
          onPlay: () => _playTrack(track),
        );
      },
    );
  }
}

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({
    required this.total,
    required this.visible,
    required this.onRefresh,
    required this.onImport,
  });

  final int total;
  final int visible;
  final VoidCallback onRefresh;
  final VoidCallback onImport;

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
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              gradient: const LinearGradient(
                  colors: [AppTheme.accent, AppTheme.accentWarm]),
              boxShadow: AppTheme.premiumShadow(alpha: 0.16),
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 34),
          ),
          SizedBox(
            width: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Library', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Text('Избранное',
                    style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 8),
                Text(
                  '$total сохранено • $visible отображается',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.playlist_add_check_rounded),
            label: const Text('Импорт'),
          ),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Обновить'),
          ),
        ],
      ),
    );
  }
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.searchController,
    required this.sort,
    required this.gridMode,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onToggleView,
  });

  final TextEditingController searchController;
  final _FavoritesSort sort;
  final bool gridMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_FavoritesSort?> onSortChanged;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.all(12),
      radius: AppTheme.radiusLg,
      color: AppTheme.surfaceMuted.withValues(alpha: 0.42),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final search = PremiumSearchBar(
            controller: searchController,
            hint: 'Фильтр по треку, артисту или альбому',
            onChanged: onSearchChanged,
          );
          final controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<_FavoritesSort>(
                value: sort,
                borderRadius: BorderRadius.circular(16),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                      value: _FavoritesSort.recent, child: Text('Недавние')),
                  DropdownMenuItem(
                      value: _FavoritesSort.title, child: Text('По названию')),
                  DropdownMenuItem(
                      value: _FavoritesSort.artist, child: Text('По артисту')),
                ],
                onChanged: onSortChanged,
              ),
              const SizedBox(width: 8),
              PremiumIconButton(
                icon: gridMode
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
                tooltip: gridMode ? 'Список' : 'Сетка',
                onTap: onToggleView,
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
    );
  }
}

class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalizedLabel = label.trim().toLowerCase();
    final showServiceIcon = normalizedLabel.isNotEmpty &&
        normalizedLabel != 'all' &&
        normalizedLabel != 'все источники' &&
        normalizedLabel != 'р’сђ рёсѓс‚рѕс‡рѕрёрєрё';

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showServiceIcon) ...[
              ServiceIcon(source: label, size: 15),
              const SizedBox(width: 7),
            ],
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Column(
        children: [
          LoadingSkeleton(height: 58),
          SizedBox(height: 10),
          LoadingSkeleton(height: 58),
          SizedBox(height: 10),
          LoadingSkeleton(height: 58),
          SizedBox(height: 10),
          LoadingSkeleton(height: 58),
        ],
      ),
    );
  }
}
