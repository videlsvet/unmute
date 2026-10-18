import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/controllers/player_controller.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/playlist_service.dart';

class PlaylistDetailsPage extends StatefulWidget {
  const PlaylistDetailsPage({
    super.key,
    required this.authService,
    required this.playlistService,
    required this.playlist,
    this.playerController,
  });

  final AuthService authService;
  final PlaylistService playlistService;
  final PlaylistSummary playlist;
  final PlayerController? playerController;

  @override
  State<PlaylistDetailsPage> createState() => _PlaylistDetailsPageState();
}

class _PlaylistDetailsPageState extends State<PlaylistDetailsPage> {
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
                        DropdownMenuItem(value: 'yandex', child: Text('Yandex')),
                        DropdownMenuItem(value: 'vkmusic', child: Text('VK Music')),
                        DropdownMenuItem(value: 'soundcloud', child: Text('SoundCloud')),
                        DropdownMenuItem(value: 'spotify', child: Text('Spotify')),
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
        setState(() {
          _progress = progress;
        });

        if (progress.isDone) {
          _progressTimer?.cancel();
          await _load();
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090B10),
        title: Text(widget.playlist.title),
      ),
      body: Padding(
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
                    Expanded(
                      child: Text(
                        widget.playlist.title,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _importText,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Импорт'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Обновить'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Источник: ${widget.playlist.source.isEmpty ? 'local' : widget.playlist.source}',
                  style: const TextStyle(color: Colors.white60),
                ),
                if (_progress != null && _progress!.isRunning) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _progress!.total <= 0 ? null : _progress!.done / _progress!.total,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Импорт: ${_progress!.done}/${_progress!.total} • ${_progress!.current}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 18),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ((_error ?? '').isNotEmpty)
                          ? Center(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            )
                          : _tracks.isEmpty
                              ? const Center(
                                  child: Text(
                                    'В плейлисте пока нет треков',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : ListView.separated(
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
                                          spacing: 4,
                                          children: [
                                            if (widget.playerController != null)
                                              IconButton(
                                                onPressed: track.hasPlayableUrl
                                                    ? () => widget.playerController!.playTrack(track)
                                                    : null,
                                                icon: const Icon(Icons.play_arrow_rounded),
                                                color: Colors.white,
                                              ),
                                            IconButton(
                                              onPressed: () => _removeTrack(track),
                                              icon: const Icon(Icons.delete_outline_rounded),
                                              color: Colors.white70,
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
      ),
    );
  }
}