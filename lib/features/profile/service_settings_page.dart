import 'package:flutter/material.dart';
import '../../core/models/profile.dart';
import '../../core/services/profile_service.dart';

class ServiceSettingsPage extends StatefulWidget {
  const ServiceSettingsPage(
      {super.key, required this.token, required this.service});
  final String token;
  final ProfileService service;
  @override
  State<ServiceSettingsPage> createState() => _ServiceSettingsPageState();
}

class _ServiceSettingsPageState extends State<ServiceSettingsPage> {
  final _fields = List.generate(5, (_) => TextEditingController());
  final _visible = <int>{};
  bool _loading = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final keys = await widget.service.getKeys(widget.token);
      if (!mounted) return;
      final values = [
        keys.spotifyId,
        keys.spotifySecret,
        keys.soundcloudId,
        keys.yandexToken,
        keys.vkMusicToken
      ];
      for (var i = 0; i < values.length; i++) {
        _fields[i].text = values[i];
      }
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Не удалось загрузить настройки';
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.saveKeys(
          token: widget.token,
          keys: ServiceKeys(
              spotifyId: _fields[0].text.trim(),
              spotifySecret: _fields[1].text.trim(),
              soundcloudId: _fields[2].text.trim(),
              yandexToken: _fields[3].text.trim(),
              vkMusicToken: _fields[4].text.trim()));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить настройки')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child:
              TextButton(onPressed: _load, child: Text('$_error. Повторить')));
    }
    const labels = [
      'Spotify Client ID',
      'Spotify Client Secret',
      'SoundCloud Client ID',
      'Яндекс Музыка — токен',
      'VK Музыка — токен'
    ];
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 24),
      Text('Музыкальные сервисы',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Ключи доступа для подключения ваших сервисов.'),
      const SizedBox(height: 24),
      for (var i = 0; i < labels.length; i++)
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
                controller: _fields[i],
                obscureText: !_visible.contains(i),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                    labelText: labels[i],
                    suffixIcon: IconButton(
                        tooltip: _visible.contains(i) ? 'Скрыть' : 'Показать',
                        icon: Icon(_visible.contains(i)
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(() {
                              if (!_visible.add(i)) _visible.remove(i);
                            }))))),
      FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Сохраняем…' : 'Сохранить')),
    ]);
  }
}
