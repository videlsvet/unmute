import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/controllers/player_controller.dart';
import '../../core/models/artist.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/playlist_service.dart';
import '../../widgets/app_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/service_chip.dart';
import '../../widgets/track_tile.dart';

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
              title: const Text('Импорт треков текстом'),
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

  @override
  Widget build(BuildContext context) {
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
