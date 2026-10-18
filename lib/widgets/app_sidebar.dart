import 'package:flutter/material.dart';

import '../app/unmute_shell.dart';
import '../theme/app_theme.dart';
import 'brand_mark.dart';
import 'premium_components.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.current,
    required this.onChanged,
    required this.isAuthorized,
    this.collapsed = false,
  });

  final AppSection current;
  final ValueChanged<AppSection> onChanged;
  final bool isAuthorized;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final width = collapsed ? 86.0 : 286.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      margin: const EdgeInsets.fromLTRB(16, 16, 0, 12),
      child: GlassSurface(
        padding: EdgeInsets.fromLTRB(
            collapsed ? 12 : 16, 16, collapsed ? 12 : 16, 14),
        radius: AppTheme.radiusXl,
        child: Column(
          crossAxisAlignment:
              collapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            _BrandHeader(collapsed: collapsed),
            const SizedBox(height: 18),
            _SidebarSearch(
                collapsed: collapsed,
                onTap: () => onChanged(AppSection.search)),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _GroupLabel('Discover', collapsed: collapsed),
                  _NavItem(
                    title: 'Главная',
                    icon: Icons.home_rounded,
                    selected: current == AppSection.home,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.home),
                  ),
                  _NavItem(
                    title: 'Поиск',
                    icon: Icons.search_rounded,
                    selected: current == AppSection.search,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.search),
                  ),
                  _NavItem(
                    title: 'Избранное',
                    icon: Icons.favorite_rounded,
                    selected: current == AppSection.favorites,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.favorites),
                  ),
                  _NavItem(
                    title: 'Плейлисты',
                    icon: Icons.queue_music_rounded,
                    selected: current == AppSection.playlists,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.playlists),
                  ),
                  _NavItem(
                    title: 'Исполнители',
                    icon: Icons.mic_external_on_rounded,
                    selected: current == AppSection.artists,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.artists),
                  ),
                  _NavItem(
                    title: 'Альбомы',
                    icon: Icons.album_rounded,
                    selected: current == AppSection.albums,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.albums),
                  ),
                  _NavItem(
                    title: 'Радио',
                    icon: Icons.radio_rounded,
                    selected: current == AppSection.radio,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.radio),
                  ),
                  const SizedBox(height: 16),
                  _GroupLabel('Account', collapsed: collapsed),
                  _NavItem(
                    title: 'Настройки',
                    icon: Icons.tune_rounded,
                    selected: current == AppSection.settings,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.settings),
                  ),
                  _NavItem(
                    title: 'Профиль',
                    icon: Icons.person_rounded,
                    selected: current == AppSection.profile,
                    collapsed: collapsed,
                    onTap: () => onChanged(AppSection.profile),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(height: 18),
                    const _PlaylistBlock(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _StatusCard(isAuthorized: isAuthorized, collapsed: collapsed),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return const BrandMark(size: 50, padding: 8);
    }

    return Row(
      children: [
        const BrandMark(size: 52, padding: 8),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UNMUTE',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Музыкальное приложение',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarSearch extends StatelessWidget {
  const _SidebarSearch({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Ink(
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            color: AppTheme.surfaceMuted.withValues(alpha: 0.58),
            border: Border.all(color: AppTheme.stroke.withValues(alpha: 0.82)),
          ),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              const Icon(Icons.search_rounded,
                  size: 19, color: AppTheme.textMuted),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Text('Поиск музыки',
                    style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                Text('Ctrl K', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.title, {required this.collapsed});

  final String title;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.collapsed,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool collapsed;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final content = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          color: active
              ? AppTheme.accent.withValues(alpha: 0.14)
              : _hovered
                  ? AppTheme.surfaceRaised.withValues(alpha: 0.62)
                  : Colors.transparent,
          border: Border.all(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.4)
                : _hovered
                    ? AppTheme.strokeSoft
                    : Colors.transparent,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            if (active && !widget.collapsed)
              Positioned(
                left: 0,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.accent2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                onTap: widget.onTap,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: widget.collapsed ? 0 : 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: widget.collapsed
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        Icon(
                          widget.icon,
                          size: 20,
                          color: active
                              ? AppTheme.accent2
                              : AppTheme.textSecondary,
                        ),
                        if (!widget.collapsed) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: active
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                    height: 1,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.collapsed) return content;
    return Tooltip(message: widget.title, child: content);
  }
}

class _PlaylistBlock extends StatelessWidget {
  const _PlaylistBlock();

  @override
  Widget build(BuildContext context) {
    const playlists = ['Late night signal', 'Красный неон', 'Deep focus'];

    return PremiumSurface(
      padding: const EdgeInsets.all(14),
      radius: AppTheme.radiusLg,
      color: AppTheme.surface.withValues(alpha: 0.44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Мои плейлисты',
                  style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              PremiumIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Создать плейлист',
                size: 32,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final playlist in playlists)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      playlist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded),
              label: const Text('Создать плейлист'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.isAuthorized, required this.collapsed});

  final bool isAuthorized;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return PremiumIconButton(
        icon:
            isAuthorized ? Icons.verified_rounded : Icons.lock_outline_rounded,
        selected: isAuthorized,
        tooltip: isAuthorized ? 'Профиль подключён' : 'Нужна авторизация',
      );
    }

    return PremiumSurface(
      padding: const EdgeInsets.all(12),
      radius: AppTheme.radiusLg,
      color: AppTheme.surfaceMuted.withValues(alpha: 0.44),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAuthorized
                  ? AppTheme.accent.withValues(alpha: 0.14)
                  : AppTheme.surfaceRaised.withValues(alpha: 0.78),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: Icon(
              isAuthorized
                  ? Icons.verified_rounded
                  : Icons.lock_outline_rounded,
              color: isAuthorized ? AppTheme.accent2 : AppTheme.textMuted,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAuthorized ? 'Аккаунт подключён' : 'Гостевой режим',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  isAuthorized
                      ? 'Синхронизация активна'
                      : 'Войдите для лайков и плейлистов',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
