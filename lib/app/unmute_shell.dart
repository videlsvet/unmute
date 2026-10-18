import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controllers/player_controller.dart';
import '../core/models/artist.dart';
import '../core/models/track.dart';
import '../core/services/auth_service.dart';
import '../core/services/music_service.dart';
import '../core/services/playlist_service.dart';
import '../core/services/profile_service.dart';
import '../core/services/wave_service.dart';
import '../features/album/album_page.dart';
import '../features/artist/artist_page.dart';
import '../features/favorites/favorites_redesign_page.dart';
import '../features/playlists/playlists_redesign_page.dart';
import '../features/profile/auth_redesign_page.dart';
import '../features/profile/profile_page.dart';
import '../features/search/search_redesign_page.dart';
import '../features/wave/wave_page.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/player_bar.dart';
import '../widgets/premium_components.dart';
import 'home_page.dart';

enum AppSection {
  home,
  search,
  favorites,
  playlists,
  artists,
  albums,
  radio,
  settings,
  profile,
}

enum _ShellRouteType { album, artist }

class _ShellRoute {
  const _ShellRoute.album({
    required this.service,
    required this.albumId,
    this.ownerId,
    this.accessKey,
  })  : type = _ShellRouteType.album,
        artistId = null,
        artistName = null;

  const _ShellRoute.artist({
    required this.service,
    this.artistId,
    this.artistName,
  })  : type = _ShellRouteType.artist,
        albumId = null,
        ownerId = null,
        accessKey = null;

  final _ShellRouteType type;
  final String service;
  final String? albumId;
  final String? ownerId;
  final String? accessKey;
  final String? artistId;
  final String? artistName;
}

class UnmuteShell extends StatefulWidget {
  const UnmuteShell({
    super.key,
    this.initialToken,
    this.initialFavorites = const [],
  });

  final String? initialToken;
  final List<Track> initialFavorites;

  @override
  State<UnmuteShell> createState() => _UnmuteShellState();
}

class _UnmuteShellState extends State<UnmuteShell> {
  final AuthService _authService = AuthService();
  final MusicService _musicService = MusicService();
  final PlaylistService _playlistService = PlaylistService();
  final ProfileService _profileService = ProfileService();
  final FocusNode _focusNode = FocusNode(debugLabel: 'unmute-shell');

  late final PlayerController _playerController;
  late final WaveProfileStore _waveStore;
  late final WaveGenerator _waveGenerator;
  late final WaveController _waveController;

  AppSection _section = AppSection.home;
  String? _token;
  List<Track> _favorites = const [];
  List<_ShellRoute> _detailStack = const [];

  @override
  void initState() {
    super.initState();
    _playerController = PlayerController();
    _playerController.prepareTrackForPlayback = _prepareTrackForPlayback;

    _waveStore = WaveProfileStore();
    _waveGenerator = WaveGenerator(
      musicService: _musicService,
      store: _waveStore,
    );
    _waveController = WaveController(
      generator: _waveGenerator,
      store: _waveStore,
    );

    _playerController.addListener(_onPlayerStateChanged);
    _token = widget.initialToken;
    _favorites = List<Track>.unmodifiable(widget.initialFavorites);
  }

  void _onPlayerStateChanged() {
    _waveController.onPlayerTick(_playerController);
  }

  Future<Track> _prepareTrackForPlayback(Track track) async {
    final source = track.source.trim().toLowerCase();
    if (source != 'yandex') return track;

    final token = _token ?? await _authService.getSavedToken();
    if (token == null || token.isEmpty) return track;

    final freshUrl = await _authService.getFreshFavoriteStream(
      token: token,
      trackId: track.id,
    );
    return track.copyWith(preview: freshUrl);
  }

  Future<void> _loadToken() async {
    final token = await _authService.getSavedToken();
    if (!mounted) return;
    setState(() => _token = token);
  }

  Future<void> _refreshFavorites() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() => _favorites = const []);
      return;
    }

    try {
      final favorites = await _authService.listFavorites(token);
      if (!mounted) return;
      setState(() => _favorites = List<Track>.unmodifiable(favorites));
    } catch (_) {}
  }

  bool _isFavoriteTrack(Track? track) {
    if (track == null) return false;
    return _favorites.any((item) => item.id == track.id);
  }

  Future<void> _toggleFavoriteTrack(Track track) async {
    final token = _token ?? await _authService.getSavedToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите в аккаунт, чтобы управлять избранным'),
        ),
      );
      return;
    }

    try {
      if (_isFavoriteTrack(track)) {
        await _authService.removeLike(token: token, trackId: track.id);
        if (!mounted) return;
        setState(() {
          _favorites = _favorites
              .where((item) => item.id != track.id)
              .toList(growable: false);
        });
      } else {
        await _authService.likeTrack(token: token, track: track);
        if (!mounted) return;
        setState(() {
          _favorites = [
            track,
            ..._favorites.where((item) => item.id != track.id),
          ];
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка избранного: $e')),
      );
    }
  }

  Future<void> _handleLoggedIn() async {
    await _loadToken();
    await _refreshFavorites();
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    setState(() {
      _token = null;
      _favorites = const [];
      _section = AppSection.search;
      _detailStack = const [];
    });
  }

  void _setSection(AppSection section) {
    setState(() {
      _section = section;
      _detailStack = const [];
    });
  }

  void _openAlbumFromTrack(Track track) {
    final albumId = (track.albumId ?? '').trim();
    if (albumId.isEmpty) return;
    setState(() {
      _detailStack = [
        ..._detailStack,
        _ShellRoute.album(
          service: track.source.trim().isEmpty ? 'yandex' : track.source,
          albumId: albumId,
          ownerId: track.ownerId,
          accessKey: track.accessKey,
        ),
      ];
    });
  }

  void _openArtist(ArtistSummary artist) {
    if (artist.artistName.trim().isEmpty &&
        (artist.artistId ?? '').trim().isEmpty) {
      return;
    }
    setState(() {
      _detailStack = [
        ..._detailStack,
        _ShellRoute.artist(
          service: artist.source.trim().isEmpty ? 'yandex' : artist.source,
          artistId: artist.artistId,
          artistName: artist.artistName,
        ),
      ];
    });
  }

  void _popDetail() {
    if (_detailStack.isEmpty) return;
    setState(
        () => _detailStack = _detailStack.sublist(0, _detailStack.length - 1));
  }

  Widget _buildMainBody() {
    switch (_section) {
      case AppSection.home:
        return HomePage(
          authService: _authService,
          playlistService: _playlistService,
          playerController: _playerController,
          waveController: _waveController,
          initialFavorites: _favorites,
          onOpenSearch: () => _setSection(AppSection.search),
          onOpenFavorites: () => _setSection(AppSection.favorites),
          onOpenPlaylists: () => _setSection(AppSection.playlists),
          onOpenWave: () => _setSection(AppSection.radio),
        );
      case AppSection.search:
        return SearchRedesignPage(
          musicService: _musicService,
          authService: _authService,
          playerController: _playerController,
          onOpenAlbum: _openAlbumFromTrack,
          onOpenArtist: _openArtist,
        );
      case AppSection.favorites:
        return FavoritesRedesignPage(
          authService: _authService,
          playerController: _playerController,
          initialTracks: _favorites,
          onTracksChanged: (tracks) {
            setState(() => _favorites = List<Track>.unmodifiable(tracks));
          },
          onOpenAlbum: _openAlbumFromTrack,
          onOpenArtist: _openArtist,
        );
      case AppSection.playlists:
        return PlaylistsRedesignPage(
          authService: _authService,
          playlistService: _playlistService,
          playerController: _playerController,
          onOpenAlbum: _openAlbumFromTrack,
          onOpenArtist: _openArtist,
        );
      case AppSection.profile:
        return _token == null
            ? AuthRedesignPage(
                authService: _authService, onLoggedIn: _handleLoggedIn)
            : ProfilePage(
                token: _token!,
                authService: _authService,
                profileService: _profileService,
                onLogout: _logout,
              );
      case AppSection.artists:
        return _ComingSoonPage(
          title: 'Исполнители',
          subtitle:
              'Персональная витрина артистов будет собираться из поиска и библиотеки.',
          icon: Icons.mic_external_on_rounded,
          action: () => _setSection(AppSection.search),
        );
      case AppSection.albums:
        return _ComingSoonPage(
          title: 'Альбомы',
          subtitle:
              'Альбомная коллекция откроется отсюда. Сейчас альбомы доступны из поиска и треков.',
          icon: Icons.album_rounded,
          action: () => _setSection(AppSection.search),
        );
      case AppSection.radio:
        return WavePage(
          waveController: _waveController,
          playerController: _playerController,
          authService: _authService,
          isFavoriteTrack: _isFavoriteTrack,
          onToggleFavorite: _toggleFavoriteTrack,
          onOpenArtist: _openArtist,
          onOpenAlbum: _openAlbumFromTrack,
        );
      case AppSection.settings:
        return _ComingSoonPage(
          title: 'Настройки',
          subtitle:
              'Звук, горячие клавиши, источники и внешний вид будут жить здесь.',
          icon: Icons.tune_rounded,
          action: () => _setSection(AppSection.profile),
        );
    }
  }

  Widget _buildBody() {
    if (_detailStack.isEmpty) return _buildMainBody();
    final route = _detailStack.last;
    switch (route.type) {
      case _ShellRouteType.album:
        return AlbumPage(
          musicService: _musicService,
          authService: _authService,
          playerController: _playerController,
          service: route.service,
          albumId: route.albumId!,
          ownerId: route.ownerId,
          accessKey: route.accessKey,
          onBack: _popDetail,
          onOpenArtist: _openArtist,
        );
      case _ShellRouteType.artist:
        return ArtistPage(
          musicService: _musicService,
          authService: _authService,
          playerController: _playerController,
          service: route.service,
          artistId: route.artistId,
          artistName: route.artistName,
          onBack: _popDetail,
          onOpenAlbum: _openAlbumFromTrack,
        );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _playerController.removeListener(_onPlayerStateChanged);
    _playerController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _playerController,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final isMobile = width < 720;
        final collapsedSidebar = width < 1120;
        final showRightPanel = width >= 1280;

        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _SearchIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
                _NextTrackIntent(),
            SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                _PreviousTrackIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _playerController.togglePlayPause();
                  return null;
                },
              ),
              _SearchIntent: CallbackAction<_SearchIntent>(
                onInvoke: (_) {
                  _setSection(AppSection.search);
                  return null;
                },
              ),
              _NextTrackIntent: CallbackAction<_NextTrackIntent>(
                onInvoke: (_) {
                  _playerController.playNext();
                  return null;
                },
              ),
              _PreviousTrackIntent: CallbackAction<_PreviousTrackIntent>(
                onInvoke: (_) {
                  _playerController.playPrevious();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              focusNode: _focusNode,
              child: Scaffold(
                body: DynamicGradientBackground(
                  artwork: _playerController.currentTrack?.image,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!isMobile)
                                AppSidebar(
                                  current: _section,
                                  onChanged: _setSection,
                                  isAuthorized: _token != null,
                                  collapsed: collapsedSidebar,
                                ),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    isMobile ? 0 : 16,
                                    isMobile ? 0 : 16,
                                    showRightPanel ? 14 : (isMobile ? 0 : 16),
                                    isMobile ? 0 : 10,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 260),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeOutCubic,
                                    child: KeyedSubtree(
                                      key: ValueKey(
                                        _detailStack.isEmpty
                                            ? 'section:${_section.name}'
                                            : '${_detailStack.last.type.name}:${_detailStack.length}',
                                      ),
                                      child: _buildBody(),
                                    ),
                                  ),
                                ),
                              ),
                              if (showRightPanel)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 16, 16, 10),
                                  child: RightNowPlayingPanel(
                                    controller: _playerController,
                                    isFavorite: _isFavoriteTrack(
                                      _playerController.currentTrack,
                                    ),
                                    onToggleFavorite: (track) =>
                                        _toggleFavoriteTrack(track),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        BottomPlayerBar(
                          controller: _playerController,
                          isFavoriteTrack: _isFavoriteTrack,
                          onToggleFavorite: (track) =>
                              _toggleFavoriteTrack(track),
                        ),
                        if (isMobile)
                          _MobileBottomNavBar(
                            current: _section,
                            onChanged: _setSection,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileBottomNavBar extends StatelessWidget {
  const _MobileBottomNavBar({
    required this.current,
    required this.onChanged,
  });

  final AppSection current;
  final ValueChanged<AppSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      (AppSection.home, 'Главная', Icons.home_rounded),
      (AppSection.radio, 'Волна', Icons.waves_rounded),
      (AppSection.search, 'Поиск', Icons.search_rounded),
      (AppSection.favorites, 'Избранное', Icons.favorite_rounded),
      (AppSection.profile, 'Профиль', Icons.person_rounded),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF140F12).withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.6,
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items.map((item) {
            final active = current == item.$1;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChanged(item.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.$3,
                      size: 24,
                      color: active ? AppTheme.accent2 : Colors.white.withValues(alpha: 0.45),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _NextTrackIntent extends Intent {
  const _NextTrackIntent();
}

class _PreviousTrackIntent extends Intent {
  const _PreviousTrackIntent();
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.action,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      title: title,
      subtitle: subtitle,
      icon: icon,
      action: ElevatedButton.icon(
        onPressed: action,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text('Перейти дальше'),
      ),
    );
  }
}
