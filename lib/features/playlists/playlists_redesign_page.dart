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
import '../../widgets/ui_kit.dart';
import 'playlist_details_redesign_page.dart';

class PlaylistsRedesignPage extends StatefulWidget {
  const PlaylistsRedesignPage({
    super.key,
    required this.authService,
    required this.playlistService,
    this.playerController,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  final AuthService authService;
  final PlaylistService playlistService;
  final PlayerController? playerController;
  final ValueChanged<Track>? onOpenAlbum;
  final ValueChanged<ArtistSummary>? onOpenArtist;

  @override
  State<PlaylistsRedesignPage> createState() => _PlaylistsRedesignPageState();
}

class _PlaylistsRedesignPageState extends State<PlaylistsRedesignPage> {
  bool _loading = true;
  String? _error;
  List<PlaylistSummary> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _token() => widget.authService.getSavedToken();

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
          _error = 'Сначала войди в аккаунт, чтобы открыть плейлисты';
        });
        return;
      }

      final data = await widget.playlistService.listPlaylists(token);

      if (!mounted) return;
      setState(() {
        _items = data;
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

  Future<void> _createPlaylist() async {
    final titleController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Новый плейлист'),
          content: TextField(
            controller: titleController,
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
    final title = titleController.text.trim();
    if (title.isEmpty) return;

    final token = await _token();
    if (token == null || token.isEmpty) return;

    try {
      await widget.playlistService.createPlaylist(token: token, title: title);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать плейлист: $e')),
      );
    }
  }

  Future<void> _addPlaylistByLink() async {
    final titleController = TextEditingController();
    final linkController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Импорт по ссылке'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linkController,
                  decoration: const InputDecoration(
                    labelText: 'Ссылка на плейлист',
                    hintText: 'https://...',
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
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final title = titleController.text.trim();
    final link = linkController.text.trim();
    if (title.isEmpty || link.isEmpty) return;

    final token = await _token();
    if (token == null || token.isEmpty) return;

    try {
      await widget.playlistService.addPlaylist(
        token: token,
        title: title,
        link: link,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  Future<void> _renamePlaylist(PlaylistSummary item) async {
    final controller = TextEditingController(text: item.title);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Переименовать плейлист'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Название',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final title = controller.text.trim();
    if (title.isEmpty) return;

    final token = await _token();
    if (token == null || token.isEmpty) return;

    try {
      await widget.playlistService.updatePlaylist(
        token: token,
        playlistId: item.playlistId,
        title: title,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переименовать плейлист: $e')),
      );
    }
  }

  Future<void> _deletePlaylist(PlaylistSummary item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Удалить плейлист?'),
          content: Text(
              'Плейлист "${item.title}" будет удалён без возможности восстановления.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final token = await _token();
    if (token == null || token.isEmpty) return;

    try {
      await widget.playlistService.deletePlaylist(
        token: token,
        playlistId: item.playlistId,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить плейлист: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: 'Плейлисты',
            subtitle:
                'Curated collections, imports and library editing with a cleaner premium layout.',
            trailing: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MetricPill(
                  label: 'Коллекции',
                  value: '${_items.length}',
                  icon: Icons.queue_music_rounded,
                ),
                OutlinedButton.icon(
                  onPressed: _addPlaylistByLink,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('По ссылке'),
                ),
                ElevatedButton.icon(
                  onPressed: _createPlaylist,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Создать'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: () {
              if (_loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if ((_error ?? '').isNotEmpty) {
                return ErrorState(message: _error!, onRetry: _load);
              }
              if (_items.isEmpty) {
                return const EmptyState(
                  title: 'Плейлистов пока нет',
                  subtitle:
                      'Создай первый плейлист или импортируй его по ссылке, чтобы собрать свою библиотеку.',
                  icon: Icons.queue_music_rounded,
                );
              }

              return ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return PremiumPanel(
                    padding: const EdgeInsets.all(18),
                    radius: 24,
                    child: Row(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.accent.withValues(alpha: 0.92),
                                AppTheme.accent2.withValues(alpha: 0.88),
                              ],
                            ),
                          ),
                          child: const Icon(Icons.library_music_rounded,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${item.source.isEmpty ? 'local' : item.source} • ${item.trackCount} треков',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          children: [
                            IconButton(
                              onPressed: () => _renamePlaylist(item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PlaylistDetailsRedesignPage(
                                      authService: widget.authService,
                                      playlistService: widget.playlistService,
                                      playlist: item,
                                      playerController: widget.playerController,
                                      onOpenAlbum: widget.onOpenAlbum,
                                      onOpenArtist: widget.onOpenArtist,
                                    ),
                                  ),
                                );
                                await _load();
                              },
                              icon: const Icon(Icons.arrow_forward_rounded),
                            ),
                            IconButton(
                              onPressed: () => _deletePlaylist(item),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            }(),
          ),
        ],
      ),
    );
  }
}
