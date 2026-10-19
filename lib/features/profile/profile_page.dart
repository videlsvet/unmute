import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/profile.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/ui_kit.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.token,
    required this.authService,
    required this.profileService,
    required this.onLogout,
  });

  final String token;
  final AuthService authService;
  final ProfileService profileService;
  final Future<void> Function() onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _avatarController = TextEditingController();
  final _spotifyIdController = TextEditingController();
  final _spotifySecretController = TextEditingController();
  final _soundcloudIdController = TextEditingController();
  final _yandexTokenController = TextEditingController();
  final _vkMusicTokenController = TextEditingController();

  bool _loading = true;
  bool _savingAvatar = false;
  bool _savingKeys = false;
  String? _error;
  Profile? _profile;
  final Set<String> _visibleSecrets = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _spotifyIdController.dispose();
    _spotifySecretController.dispose();
    _soundcloudIdController.dispose();
    _yandexTokenController.dispose();
    _vkMusicTokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        widget.profileService.getProfile(widget.token),
        widget.profileService.getKeys(widget.token),
      ]);

      if (!mounted) return;
      final profile = results[0] as Profile;
      final keys = results[1] as ServiceKeys;

      _profile = profile;
      _avatarController.text = profile.avatarUrl ?? '';
      _spotifyIdController.text = keys.spotifyId;
      _spotifySecretController.text = keys.spotifySecret;
      _soundcloudIdController.text = keys.soundcloudId;
      _yandexTokenController.text = keys.yandexToken;
      _vkMusicTokenController.text = keys.vkMusicToken;

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _saveAvatar() async {
    final avatarUrl = _avatarController.text.trim();
    if (avatarUrl.isEmpty) return;

    setState(() => _savingAvatar = true);
    try {
      final savedUrl = await widget.profileService.updateAvatar(
        token: widget.token,
        avatarUrl: avatarUrl,
      );

      if (!mounted) return;
      setState(() {
        _savingAvatar = false;
        _profile = Profile(
          nickname: _profile?.nickname ?? '',
          avatarUrl: savedUrl.trim().isEmpty ? null : savedUrl,
        );
        _avatarController.text = savedUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аватар обновлён')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить аватар: $e')),
      );
    }
  }

  Future<void> _saveKeys() async {
    setState(() => _savingKeys = true);
    try {
      await widget.profileService.saveKeys(
        token: widget.token,
        keys: ServiceKeys(
          spotifyId: _spotifyIdController.text.trim(),
          spotifySecret: _spotifySecretController.text.trim(),
          soundcloudId: _soundcloudIdController.text.trim(),
          yandexToken: _yandexTokenController.text.trim(),
          vkMusicToken: _vkMusicTokenController.text.trim(),
        ),
      );

      if (!mounted) return;
      setState(() => _savingKeys = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ключи сервисов сохранены')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingKeys = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить ключи сервисов: $e')),
      );
    }
  }

  void _toggleVisibility(String key) {
    setState(() {
      if (_visibleSecrets.contains(key)) {
        _visibleSecrets.remove(key);
      } else {
        _visibleSecrets.add(key);
      }
    });
  }

  Future<void> _copy(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if ((_error ?? '').isNotEmpty) {
      if (isMobile) {
        return ErrorState(message: _error!, onRetry: _load);
      }
      return GlassPanel(
        child: ErrorState(message: _error!, onRetry: _load),
      );
    }

    final profile = _profile;
    if (profile == null) {
      if (isMobile) {
        return ErrorState(
          message: 'Профиль не найден',
          onRetry: _load,
        );
      }
      return GlassPanel(
        child: ErrorState(
          message: 'Профиль не найден',
          onRetry: _load,
        ),
      );
    }

    if (isMobile) {
      return _buildMobile(context, profile);
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: 'Профиль',
            subtitle: 'Аккаунт, аватар и ключи сервисов с более безопасным редактированием и понятными статусами.',
            trailing: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Обновить'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Выйти'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  PremiumPanel(
                    padding: const EdgeInsets.all(22),
                    child: Row(
                      children: [
                        UnmuteArtwork(
                          imageUrl: profile.avatarUrl,
                          size: 96,
                          radius: 32,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.nickname,
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Подключённый аккаунт с интеграциями сервисов, готовой синхронизацией и более безопасным управлением ключами.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  const MetricPill(
                                    label: 'Аккаунт',
                                    value: 'Активен',
                                    icon: Icons.verified_rounded,
                                  ),
                                  MetricPill(
                                    label: 'Ключи',
                                    value: _filledKeyCount.toString(),
                                    icon: Icons.vpn_key_rounded,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionCard(
                    title: 'Аватар',
                    subtitle: 'Используй прямую ссылку на изображение и настраивай аватар как часть продукта, а не как сухую форму настроек.',
                    child: Column(
                      children: [
                        TextField(
                          controller: _avatarController,
                          decoration: const InputDecoration(
                            labelText: 'URL аватара',
                            hintText: 'https://...',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            onPressed: _savingAvatar ? null : _saveAvatar,
                            icon: _savingAvatar
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.image_outlined),
                            label: const Text('Сохранить аватар'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionCard(
                    title: 'Ключи сервисов',
                    subtitle: 'Показывай, скрывай и копируй значения без ощущения сырой технической формы.',
                    child: Column(
                      children: [
                        _SecretField(
                          label: 'Spotify Client ID',
                          controller: _spotifyIdController,
                          visible: _visibleSecrets.contains('spotify_id'),
                          onToggleVisibility: () => _toggleVisibility('spotify_id'),
                          onCopy: () => _copy(_spotifyIdController.text, 'Spotify Client ID'),
                        ),
                        const SizedBox(height: 12),
                        _SecretField(
                          label: 'Spotify Client Secret',
                          controller: _spotifySecretController,
                          visible: _visibleSecrets.contains('spotify_secret'),
                          onToggleVisibility: () => _toggleVisibility('spotify_secret'),
                          onCopy: () => _copy(_spotifySecretController.text, 'Spotify Client Secret'),
                        ),
                        const SizedBox(height: 12),
                        _SecretField(
                          label: 'SoundCloud Client ID',
                          controller: _soundcloudIdController,
                          visible: _visibleSecrets.contains('soundcloud_id'),
                          onToggleVisibility: () => _toggleVisibility('soundcloud_id'),
                          onCopy: () => _copy(_soundcloudIdController.text, 'SoundCloud Client ID'),
                        ),
                        const SizedBox(height: 12),
                        _SecretField(
                          label: 'Yandex Token',
                          controller: _yandexTokenController,
                          visible: _visibleSecrets.contains('yandex_token'),
                          onToggleVisibility: () => _toggleVisibility('yandex_token'),
                          onCopy: () => _copy(_yandexTokenController.text, 'Yandex Token'),
                        ),
                        const SizedBox(height: 12),
                        _SecretField(
                          label: 'VK Music Token',
                          controller: _vkMusicTokenController,
                          visible: _visibleSecrets.contains('vkmusic_token'),
                          onToggleVisibility: () => _toggleVisibility('vkmusic_token'),
                          onCopy: () => _copy(_vkMusicTokenController.text, 'VK Music Token'),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            onPressed: _savingKeys ? null : _saveKeys,
                            icon: _savingKeys
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.vpn_key_outlined),
                            label: const Text('Сохранить ключи сервисов'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context, Profile profile) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accent2,
      backgroundColor: AppTheme.surfaceRaised,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipOval(
                  child: UnmuteArtwork(
                    imageUrl: profile.avatarUrl,
                    size: 64,
                    radius: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.nickname,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppTheme.accent2,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Аккаунт активен',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  color: AppTheme.textSecondary,
                  tooltip: 'Выйти',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _MobileSectionCard(
              title: 'Аватар',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _avatarController,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      labelText: 'URL аватара',
                      hintText: 'https://...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _savingAvatar ? null : _saveAvatar,
                      icon: _savingAvatar
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Сохранить аватар'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _MobileSectionCard(
              title: 'Ключи сервисов',
              child: Column(
                children: [
                  _MobileSecretField(
                    label: 'Spotify Client ID',
                    controller: _spotifyIdController,
                    visible: _visibleSecrets.contains('spotify_id'),
                    onToggleVisibility: () => _toggleVisibility('spotify_id'),
                  ),
                  const SizedBox(height: 10),
                  _MobileSecretField(
                    label: 'Spotify Client Secret',
                    controller: _spotifySecretController,
                    visible: _visibleSecrets.contains('spotify_secret'),
                    onToggleVisibility: () => _toggleVisibility('spotify_secret'),
                  ),
                  const SizedBox(height: 10),
                  _MobileSecretField(
                    label: 'SoundCloud Client ID',
                    controller: _soundcloudIdController,
                    visible: _visibleSecrets.contains('soundcloud_id'),
                    onToggleVisibility: () => _toggleVisibility('soundcloud_id'),
                  ),
                  const SizedBox(height: 10),
                  _MobileSecretField(
                    label: 'Yandex Token',
                    controller: _yandexTokenController,
                    visible: _visibleSecrets.contains('yandex_token'),
                    onToggleVisibility: () => _toggleVisibility('yandex_token'),
                  ),
                  const SizedBox(height: 10),
                  _MobileSecretField(
                    label: 'VK Music Token',
                    controller: _vkMusicTokenController,
                    visible: _visibleSecrets.contains('vkmusic_token'),
                    onToggleVisibility: () => _toggleVisibility('vkmusic_token'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _savingKeys ? null : _saveKeys,
                      icon: _savingKeys
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.vpn_key_outlined, size: 18),
                      label: const Text('Сохранить ключи сервисов'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _filledKeyCount {
    final values = [
      _spotifyIdController.text,
      _spotifySecretController.text,
      _soundcloudIdController.text,
      _yandexTokenController.text,
      _vkMusicTokenController.text,
    ];
    return values.where((value) => value.trim().isNotEmpty).length;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _MobileSectionCard extends StatelessWidget {
  const _MobileSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SecretField extends StatelessWidget {
  const _SecretField({
    required this.label,
    required this.controller,
    required this.visible,
    required this.onToggleVisibility,
    required this.onCopy,
  });

  final String label;
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final filled = controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppTheme.surfaceSoft.withValues(alpha: 0.74),
        border: Border.all(
          color: filled ? AppTheme.strokeSoft : AppTheme.stroke,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: filled
                      ? AppTheme.accent.withValues(alpha: 0.14)
                      : AppTheme.surfaceMuted,
                ),
                child: Text(
                  filled ? 'Сохранено' : 'Пусто',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: filled ? AppTheme.accent2 : AppTheme.textMuted,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: !visible,
            decoration: InputDecoration(
              hintText: 'Введите значение',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    onPressed: onToggleVisibility,
                    icon: Icon(
                      visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSecretField extends StatelessWidget {
  const _MobileSecretField({
    required this.label,
    required this.controller,
    required this.visible,
    required this.onToggleVisibility,
  });

  final String label;
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    final filled = controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: filled
              ? AppTheme.accent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: filled
                      ? AppTheme.accent.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                ),
                child: Text(
                  filled ? 'Сохранено' : 'Пусто',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: filled ? AppTheme.accent2 : AppTheme.textMuted,
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: !visible,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              hintText: 'Введите значение',
              suffixIcon: IconButton(
                iconSize: 20,
                onPressed: onToggleVisibility,
                icon: Icon(
                  visible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
