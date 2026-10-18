import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/playlist_service.dart';
import '../../core/models/playlist.dart';
import 'playlist_details_page.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    super.key,
    required this.authService,
    required this.playlistService,
  });

  final AuthService authService;
  final PlaylistService playlistService;

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
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
          _error = 'Сначала войди в аккаунт';
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
          backgroundColor: const Color(0xFF131722),
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
        SnackBar(content: Text('Создание: $e')),
      );
    }
  }

  Future<void> _renamePlaylist(PlaylistSummary item) async {
    final controller = TextEditingController(text: item.title);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131722),
          title: const Text('Переименовать'),
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
        SnackBar(content: Text('Переименование: $e')),
      );
    }
  }

  Future<void> _deletePlaylist(PlaylistSummary item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131722),
          title: const Text('Удалить плейлист?'),
          content: Text('Будет удалён плейлист "${item.title}"'),
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
        SnackBar(content: Text('Удаление: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if ((_error ?? '').isNotEmpty) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

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
              Row(
                children: [
                  Text('Плейлисты', style: Theme.of(context).textTheme.displaySmall),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _createPlaylist,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Создать'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_items.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Плейлистов пока нет',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F2B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          title: Text(
                            item.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${item.source.isEmpty ? 'local' : item.source} • ${item.trackCount} треков',
                            style: const TextStyle(color: Colors.white60),
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed: () => _renamePlaylist(item),
                                icon: const Icon(Icons.edit_outlined),
                                color: Colors.white70,
                              ),
                              IconButton(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PlaylistDetailsPage(
                                        authService: widget.authService,
                                        playlistService: widget.playlistService,
                                        playlist: item,
                                      ),
                                    ),
                                  );
                                  await _load();
                                },
                                icon: const Icon(Icons.arrow_forward_rounded),
                                color: Colors.white,
                              ),
                              IconButton(
                                onPressed: () => _deletePlaylist(item),
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
    );
  }
}