import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models/profile.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/profile_service.dart';
import '../../core/services/wave_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage(
      {super.key,
      required this.token,
      required this.authService,
      required this.profileService,
      required this.onLogout,
      required this.onSettings});
  final String token;
  final AuthService authService;
  final ProfileService profileService;
  final Future<void> Function() onLogout;
  final VoidCallback onSettings;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile? _profile;
  List<String> _artists = [];
  bool _uploading = false;
  String? _error;
  final _store = WaveProfileStore();
  final _modalInputs = <TextEditingController>[];
  @override
  void dispose() {
    for (final input in _modalInputs) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.profileService.getProfile(widget.token);
      final artists = await _store.favoriteArtists();
      if (mounted) {
        setState(() {
          _profile = profile;
          _artists = artists;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось загрузить профиль');
    }
  }

  Future<void> _photo() async {
    if (_uploading) return;
    try {
      final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 640,
          maxHeight: 640,
          imageQuality: 80,
          requestFullMetadata: false);
      if (photo == null || !mounted) return;
      setState(() => _uploading = true);
      final bytes = await photo.readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) {
        throw Exception('Выберите фото меньше 3 МБ');
      }
      final mime = photo.mimeType ??
          (photo.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      final url = await widget.profileService.updateAvatar(
          token: widget.token,
          avatarUrl: 'data:$mime;base64,${base64Encode(bytes)}');
      if (mounted) {
        setState(() => _profile = Profile(
            nickname: _profile!.nickname,
            avatarUrl:
                '$url${url.contains('?') ? '&' : '?'}v=${DateTime.now().millisecondsSinceEpoch}'));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Не удалось обновить фото. Проверьте доступ к фотографиям и попробуйте ещё раз.')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editArtists() async {
    final selected = List<String>.of(_artists);
    final input = TextEditingController();
    _modalInputs.add(input);
    final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(builder: (context, update) {
              void add(String value) {
                final name = value.trim();
                if (name.isNotEmpty &&
                    selected.length < 12 &&
                    !selected
                        .any((s) => s.toLowerCase() == name.toLowerCase())) {
                  update(() => selected.add(name));
                }
                input.clear();
              }

              return Padding(
                  padding: EdgeInsets.fromLTRB(
                      24, 8, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text('Кто на вашей частоте?',
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        const Text(
                            'Выберите до 12 исполнителей. Волна подстроится под вас.'),
                        const SizedBox(height: 20),
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: selected
                                .map((name) => InputChip(
                                    label: Text(name),
                                    onDeleted: () =>
                                        update(() => selected.remove(name))))
                                .toList()),
                        const SizedBox(height: 16),
                        TextField(
                            controller: input,
                            maxLength: 80,
                            textInputAction: TextInputAction.done,
                            onSubmitted: add,
                            decoration: InputDecoration(
                                hintText: 'Найти свой звук — имя исполнителя',
                                suffixIcon: IconButton(
                                    onPressed: () => add(input.text),
                                    icon:
                                        const Icon(Icons.add_circle_rounded)))),
                        Wrap(
                            spacing: 8,
                            children: [
                              'Кино',
                              'Земфира',
                              'Radiohead',
                              'The Weeknd',
                              'Lana Del Rey',
                              'Баста'
                            ]
                                .where((s) => !selected.contains(s))
                                .map((s) => ActionChip(
                                    label: Text(s), onPressed: () => add(s)))
                                .toList()),
                        const SizedBox(height: 24),
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, selected),
                                child: const Text('Это мой вкус'))),
                      ])));
            }));
    if (result == null) return;
    try {
      await _store.saveFavoriteArtists(result);
      if (mounted) setState(() => _artists = result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить исполнителей')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
          child:
              TextButton(onPressed: _load, child: Text('$_error. Повторить')));
    }
    if (_profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Row(children: [
                Text('Профиль',
                    style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                IconButton(
                    tooltip: 'Настройки',
                    onPressed: widget.onSettings,
                    icon: const Icon(Icons.settings_outlined))
              ]),
              const SizedBox(height: 16),
              Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF571B2B),
                            Color(0xFF21141B),
                            AppTheme.surface
                          ])),
                  child: Column(children: [
                    Stack(children: [
                      GestureDetector(
                          onTap: _photo,
                          child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white24, width: 2)),
                              child: ClipOval(
                                  child: UnmuteArtwork(
                                      imageUrl: _profile!.avatarUrl,
                                      size: 116,
                                      radius: 58)))),
                      Positioned(
                          bottom: 0,
                          right: 0,
                          child: IconButton.filled(
                              onPressed: _uploading ? null : _photo,
                              tooltip: 'Изменить фото',
                              icon: _uploading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.photo_camera_rounded,
                                      size: 20))),
                    ]),
                    const SizedBox(height: 18),
                    Text(_profile!.nickname,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    const Text('Мой мир музыки',
                        style: TextStyle(color: AppTheme.textSecondary)),
                    TextButton(
                        onPressed: _uploading ? null : _photo,
                        child: const Text('Изменить фото')),
                  ])),
              const SizedBox(height: 30),
              Row(children: [
                Expanded(
                    child: Text('Любимые исполнители',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    onPressed: _editArtists,
                    tooltip: 'Редактировать исполнителей',
                    icon: const Icon(Icons.add_circle_outline_rounded,
                        color: AppTheme.accent))
              ]),
              const Text('Ваш вкус — отправная точка Моей волны.',
                  style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 18),
              if (_artists.isEmpty)
                InkWell(
                    onTap: _editArtists,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(24)),
                        child: const Row(children: [
                          Icon(Icons.favorite_rounded, color: AppTheme.accent),
                          SizedBox(width: 16),
                          Expanded(
                              child:
                                  Text('Соберите свою музыкальную вселенную')),
                          Icon(Icons.chevron_right_rounded)
                        ])))
              else
                Wrap(
                    spacing: 14,
                    runSpacing: 20,
                    children: _artists
                        .asMap()
                        .entries
                        .map((e) => SizedBox(
                            width: 94,
                            child: Column(children: [
                              Container(
                                  width: 80,
                                  height: 80,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(colors: [
                                        Color.lerp(
                                            AppTheme.accent,
                                            const Color(0xFF823B59),
                                            e.key / 12)!,
                                        const Color(0xFF381F2C)
                                      ])),
                                  child: Text(
                                      e.value.substring(0, 1).toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w700))),
                              const SizedBox(height: 10),
                              Text(e.value,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis)
                            ])))
                        .toList()),
              const SizedBox(height: 32),
              const Divider(),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Настройки'),
                  subtitle: const Text('Подключённые музыкальные сервисы'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onSettings),
              TextButton(
                  onPressed: widget.onLogout,
                  child: const Text('Выйти из аккаунта')),
            ]));
  }
}
