import 'package:flutter/material.dart';
import '../core/models/playlist.dart';
import '../core/models/track.dart';
import '../core/services/auth_service.dart';
import '../core/services/playlist_service.dart';

class AddToPlaylistDialog extends StatefulWidget {
  const AddToPlaylistDialog({
    super.key,
    required this.authService,
    required this.playlistService,
    required this.track,
  });

  final AuthService authService;
  final PlaylistService playlistService;
  final Track track;

  @override
  State<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<AddToPlaylistDialog> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<PlaylistSummary> _playlists = const [];

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

      final items = await widget.playlistService.listPlaylists(token);

      if (!mounted) return;
      setState(() {
        _playlists = items;
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

  Future<void> _addToPlaylist(PlaylistSummary playlist) async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.playlistService.addTrackToPlaylist(
        token: token,
        playlistId: playlist.playlistId,
        track: widget.track,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  Future<void> _createPlaylistAndAdd() async {
    final controller = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131722),
          title: const Text('Новый плейлист'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Название плейлиста',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Создать'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final title = controller.text.trim();
    if (title.isEmpty) return;

    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final playlistId = await widget.playlistService.createPlaylist(
        token: token,
        title: title,
      );

      await widget.playlistService.addTrackToPlaylist(
        token: token,
        playlistId: playlistId,
        track: widget.track,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF131722),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 560
            ? double.maxFinite
            : 520,
        child: _loading
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : (_error ?? '').isNotEmpty
                ? SizedBox(
                    height: 160,
                    child: Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_playlists.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Плейлистов пока нет',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _playlists.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final playlist = _playlists[index];
                              return Material(
                                color: const Color(0xFF1A1F2B),
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: _submitting ? null : () => _addToPlaylist(playlist),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.queue_music_rounded, color: Colors.white70),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                playlist.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${playlist.trackCount} треков',
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      if ((_error ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _createPlaylistAndAdd,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add_rounded),
                          label: const Text('Создать новый плейлист'),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}