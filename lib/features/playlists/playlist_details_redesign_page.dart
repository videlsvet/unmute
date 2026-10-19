import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/controllers/player_controller.dart';
import '../../core/models/artist.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/playlist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/service_chip.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/ui_kit.dart';

class PlaylistDetailsRedesignPage extends StatefulWidget {
  const PlaylistDetailsRedesignPage({
    super.key,
    required this.authService,
    required this.playlistService,
    required this.playlist,
    this.playerController,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  final AuthService authService;
  final PlaylistService playlistService;
  final PlaylistSummary playlist;
  final PlayerController? playerController;
  final ValueChanged<Track>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<PlaylistDetailsRedesignPage> createState() =>
      _PlaylistDetailsRedesignPageState();
}

class _PlaylistDetailsRedesignPageState
    extends State<PlaylistDetailsRedesignPage> {
  bool _loading = true;
  String? _error;
  List<Track> _tracks = const [];
  Timer? _progressTimer;
  ImportProgress? _progress;

  Future<String?> _token() => widget.authService.getSavedToken();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _token();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Сначала войди в аккаунт';
        });
        return;
      }

      final items = await widget.playlistService.listPlaylistTracks(
        token: token,
        playlistId: widget.playlist.playlistId,
      );

      if (!mounted) return;
      setState(() {
        _tracks = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _removeTrack(Track track) async {
    final token = await _token();
    if (token == null || token.isEmpty) return;

    try {
      await widget.playlistService.removeTrackFromPlaylist(
        token: token,
        playlistId: widget.playlist.playlistId,
        trackId: track.id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Удаление трека: $e')),
      );
    }
  }

  Future<void> _importText() async {
    final textController = TextEditingController();
    String service = 'vkmusic';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131722),
              title: const Text('Импорт треков текстом'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: service,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1F2B),
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
                      minLines: 6,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        hintText: 'Каждый трек с новой строки',
                      ),
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

    final token = await _token();
    if (token == null || token.isEmpty) return;

    try {
      await widget.playlistService.importPlaylistText(
        token: token,
        playlistId: widget.playlist.playlistId,
        text: text,
        service: service,
      );
      _startProgressPolling();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Импорт запущен')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импорт: $e')),
      );
    }
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final token = await _token();
      if (token == null || token.isEmpty) return;

      try {
        final progress = await widget.playlistService.getPlaylistImportProgress(
          token: token,
          playlistId: widget.playlist.playlistId,
        );

        if (!mounted) return;
        setState(() => _progress = progress);

        if (progress.isDone) {
          _progressTimer?.cancel();
          await _load();
        }
      } catch (_) {}
    });
  }

  void _openAlbum(Track track) {
    final albumId = (track.albumId ?? '').trim();
    final onOpenAlbum = widget.onOpenAlbum;
    if (albumId.isEmpty || onOpenAlbum == null) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    onOpenAlbum(track);
  }

  void _openArtist(Track track) {
    final artistName = track.artist.trim();
    final onOpenArtist = widget.onOpenArtist;
    if (artistName.isEmpty || onOpenArtist == null) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    onOpenArtist(
      ArtistSummary(
        artistName: artistName,
        source:
            track.source.trim().isEmpty ? widget.playlist.source : track.source,
        artistId: track.artistId,
      ),
    );
  }

  Future<void> _playAll() async {
    if (_tracks.isEmpty || widget.playerController == null) return;
    final firstPlayable = _tracks.indexWhere((t) => t.hasPlayableUrl);
    if (firstPlayable >= 0) {
      await widget.playerController!.playTracks(
        _tracks,
        startIndex: firstPlayable,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    if (isMobile) {
      return _buildMobile(context);
    }
    return _buildDesktop(context);
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 30),
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.upload_file_rounded, size: 22),
                    tooltip: 'Импорт треков',
                    onPressed: _importText,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 22),
                    tooltip: 'Обновить',
                    onPressed: _load,
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: () {
                if (_loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if ((_error ?? '').isNotEmpty) {
                  return ErrorState(message: _error!, onRetry: _load);
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Centered artwork/icon box
                    Center(
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.accent.withValues(alpha: 0.92),
                              AppTheme.accent2.withValues(alpha: 0.88),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.3),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.library_music_rounded,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    Text(
                      widget.playlist.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    Text(
                      '${widget.playlist.source.isEmpty ? 'local' : widget.playlist.source} • ${_tracks.length} треков',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Actions Row: Shuffle & Play button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.playerController != null)
                          IconButton(
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: widget.playerController!.shuffleEnabled
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                            ),
                            onPressed: () {
                              setState(() {
                                widget.playerController!.toggleShuffle();
                              });
                            },
                          ),
                        const SizedBox(width: 8),
                        Container(
                          width: 50,
                          height: 50,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accent,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                            onPressed: _tracks.isEmpty ? null : _playAll,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Import progress
                    if (_progress != null && _progress!.isRunning) ...[
                      LinearProgressIndicator(
                        value: _progress!.total <= 0
                            ? null
                            : _progress!.done / _progress!.total,
                        backgroundColor: Colors.white12,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Импорт: ${_progress!.done}/${_progress!.total} • ${_progress!.current}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Empty or track list
                    if (_tracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: EmptyState(
                          title: 'В плейлисте пока нет треков',
                          subtitle: 'Добавь их вручную или импортируй текстом.',
                          icon: Icons.library_music_outlined,
                        ),
                      )
                    else
                      ...List.generate(_tracks.length, (index) {
                        final track = _tracks[index];
                        final isCurrent =
                            widget.playerController?.currentTrack?.id ==
                                track.id;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isCurrent
                                ? AppTheme.accent.withValues(alpha: 0.12)
                                : Colors.transparent,
                          ),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: UnmuteArtwork(
                              imageUrl: track.image,
                              size: 44,
                              radius: 8,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent
                                    ? AppTheme.accent
                                    : Colors.white,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              track.artist.isEmpty
                                  ? 'Неизвестный исполнитель'
                                  : track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            onTap: widget.playerController != null &&
                                    track.hasPlayableUrl
                                ? () => widget.playerController!.playTracks(
                                      _tracks,
                                      startIndex: index,
                                    )
                                : null,
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: AppTheme.textSecondary,
                                size: 20,
                              ),
                              color: const Color(0xFF1E2330),
                              onSelected: (val) {
                                switch (val) {
                                  case 'artist':
                                    _openArtist(track);
                                    break;
                                  case 'album':
                                    _openAlbum(track);
                                    break;
                                  case 'remove':
                                    _removeTrack(track);
                                    break;
                                }
                              },
                              itemBuilder: (_) => [
                                if (widget.onOpenArtist != null &&
                                    track.artist.trim().isNotEmpty)
                                  const PopupMenuItem(
                                    value: 'artist',
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_outline_rounded,
                                            size: 18),
                                        SizedBox(width: 10),
                                        Text('К исполнителю'),
                                      ],
                                    ),
                                  ),
                                if (widget.onOpenAlbum != null &&
                                    (track.albumId ?? '').trim().isNotEmpty)
                                  const PopupMenuItem(
                                    value: 'album',
                                    child: Row(
                                      children: [
                                        Icon(Icons.album_outlined, size: 18),
                                        SizedBox(width: 10),
                                        Text('К альбому'),
                                      ],
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded,
                                          color: Colors.redAccent, size: 18),
                                      SizedBox(width: 10),
                                      Text(
                                        'Удалить из плейлиста',
                                        style:
                                            TextStyle(color: Colors.redAccent),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 32),
                  ],
                );
              }(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppHeader(
                  title: widget.playlist.title,
                  subtitle:
                      'Источник: ${widget.playlist.source.isEmpty ? 'local' : widget.playlist.source}',
                  trailing: Wrap(
                    spacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _importText,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Импорт'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Обновить'),
                      ),
                    ],
                  ),
                ),
                if (_progress != null && _progress!.isRunning) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: _progress!.total <= 0
                        ? null
                        : _progress!.done / _progress!.total,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Импорт: ${_progress!.done}/${_progress!.total} • ${_progress!.current}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 20),
                Expanded(
                  child: () {
                    if (_loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if ((_error ?? '').isNotEmpty) {
                      return ErrorState(message: _error!, onRetry: _load);
                    }
                    if (_tracks.isEmpty) {
                      return const EmptyState(
                        title: 'В плейлисте пока нет треков',
                        subtitle: 'Добавь их вручную или импортируй текстом.',
                        icon: Icons.library_music_outlined,
                      );
                    }
                    return ListView.separated(
                      itemCount: _tracks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final track = _tracks[index];
                        return TrackTile(
                          track: track,
                          index: index,
                          isCurrent:
                              widget.playerController?.currentTrack?.id ==
                                  track.id,
                          onPlay: widget.playerController != null &&
                                  track.hasPlayableUrl
                              ? () => widget.playerController!.playTracks(
                                    _tracks,
                                    startIndex: index,
                                  )
                              : null,
                          onArtist: widget.onOpenArtist != null &&
                                  track.artist.trim().isNotEmpty
                              ? () => _openArtist(track)
                              : null,
                          onAlbum: widget.onOpenAlbum != null &&
                                  (track.albumId ?? '').trim().isNotEmpty
                              ? () => _openAlbum(track)
                              : null,
                          onRemove: () => _removeTrack(track),
                        );
                      },
                    );
                  }(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
