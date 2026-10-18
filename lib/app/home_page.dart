import 'package:flutter/material.dart';

import '../core/controllers/player_controller.dart';
import '../core/models/playlist.dart';
import '../core/models/track.dart';
import '../core/services/auth_service.dart';
import '../core/services/playlist_service.dart';
import '../core/services/wave_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/disc_beat_glow.dart';
import '../widgets/premium_components.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.authService,
    required this.playlistService,
    required this.playerController,
    required this.waveController,
    this.initialFavorites = const [],
    required this.onOpenSearch,
    required this.onOpenFavorites,
    required this.onOpenPlaylists,
    required this.onOpenWave,
  });

  final AuthService authService;
  final PlaylistService playlistService;
  final PlayerController playerController;
  final WaveController waveController;
  final List<Track> initialFavorites;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenPlaylists;
  final VoidCallback onOpenWave;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  List<Track> _favorites = const [];
  List<PlaylistSummary> _playlists = const [];

  @override
  void initState() {
    super.initState();
    _favorites = List<Track>.unmodifiable(widget.initialFavorites);
    _load();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameTrackIds(oldWidget.initialFavorites, widget.initialFavorites)) {
      _favorites = List<Track>.unmodifiable(widget.initialFavorites);
    }
  }

  Future<void> _load() async {
    final token = await widget.authService.getSavedToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _favorites = const [];
        _playlists = const [];
        _loading = false;
      });
      return;
    }

    try {
      final playlists = await widget.playlistService.listPlaylists(token);
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _sameTrackIds(List<Track> a, List<Track> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.playerController.queue;
    final favoriteTracks = _favorites.take(10).toList(growable: false);
    final recentTracks = queue.take(10).toList(growable: false);

    return AnimatedBuilder(
      animation: Listenable.merge([widget.playerController, widget.waveController]),
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 26),
          children: [
            _HomeHero(
              currentTrack: widget.playerController.currentTrack,
              favoriteCount: _favorites.length,
              playlistCount: _playlists.length,
              isPlaying: widget.playerController.isPlaying,
              waveController: widget.waveController,
              playerController: widget.playerController,
              onOpenSearch: widget.onOpenSearch,
              onOpenWave: widget.onOpenWave,
            ),
            const SizedBox(height: 22),
            _QuickActions(
              onOpenWave: widget.onOpenWave,
              onOpenSearch: widget.onOpenSearch,
              onOpenFavorites: widget.onOpenFavorites,
              onOpenPlaylists: widget.onOpenPlaylists,
            ),
            const SizedBox(height: 24),
            _TrackRail(
              title: 'Для тебя',
              subtitle: 'Быстрый доступ к тому, что уже собрано в UNMUTE.',
              tracks: favoriteTracks.isNotEmpty ? favoriteTracks : recentTracks,
              loading: _loading && favoriteTracks.isEmpty,
              emptyTitle: 'Пока нечего рекомендовать',
              emptySubtitle: 'Запусти поиск или добавь треки в избранное, и эта зона оживёт.',
              onPlay: (index, tracks) => widget.playerController.playTracks(tracks, startIndex: index),
            ),
            const SizedBox(height: 24),
            const _MoodRail(),
            const SizedBox(height: 24),
            _TrackRail(
              title: 'Недавно прослушано',
              subtitle: 'Текущая очередь и последние запущенные треки.',
              tracks: recentTracks,
              loading: false,
              emptyTitle: 'Очередь пока пустая',
              emptySubtitle: 'Когда включите музыку, последние треки появятся здесь.',
              onPlay: (index, tracks) => widget.playerController.playTracks(tracks, startIndex: index),
            ),
            const SizedBox(height: 24),
            _PlaylistSection(playlists: _playlists, loading: _loading),
          ],
        );
      },
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.currentTrack,
    required this.favoriteCount,
    required this.playlistCount,
    required this.isPlaying,
    required this.waveController,
    required this.playerController,
    required this.onOpenSearch,
    required this.onOpenWave,
  });

  final Track? currentTrack;
  final int favoriteCount;
  final int playlistCount;
  final bool isPlaying;
  final WaveController waveController;
  final PlayerController playerController;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenWave;

  @override
  Widget build(BuildContext context) {
    final hasTrack = currentTrack != null;
    final isWaveRunning = waveController.isRunning;

    return Container(
      constraints: const BoxConstraints(minHeight: 292),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withValues(alpha: 0.28),
            const Color(0xFF171014).withValues(alpha: 0.96),
            AppTheme.surface.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.24)),
        boxShadow: AppTheme.premiumShadow(alpha: 0.12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;

          final discWidget = DiscBeatGlow(
            isPlaying: isPlaying,
            level: isPlaying ? 0.70 : 0.08,
            glowSize: compact ? 220 : 250,
            child: MyWaveDisc(
              spin: isPlaying,
              size: compact ? 175 : 205,
              enabled: !waveController.isLoading,
              artworkUrl: currentTrack?.image,
              onPlayClick: () {
                if (!isWaveRunning) {
                  waveController.startWave(
                    seedTrack: currentTrack,
                    playerController: playerController,
                  );
                } else {
                  playerController.togglePlayPause();
                }
              },
            ),
          );

          return Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (compact) ...[
                discWidget,
                const SizedBox(height: 18),
              ],
              Expanded(
                flex: compact ? 0 : 5,
                child: Column(
                  crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandMark(size: 38, padding: 6, glow: false),
                        const SizedBox(width: 10),
                        Text(
                          isWaveRunning ? 'Моя Волна в эфире' : 'UNMUTE Music',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: AppTheme.accent2,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasTrack
                          ? 'Сейчас звучит ${currentTrack!.title}'
                          : 'Тёмная сцена для твоей музыки',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: compact ? TextAlign.center : TextAlign.start,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isWaveRunning
                          ? 'Бесконечный персонализированный поток музыки на основе твоего вкуса и истории.'
                          : 'Запусти Мою Волну, исследуй подборки и наслаждайся треками из Yandex, VK и других сервисов.',
                      textAlign: compact ? TextAlign.center : TextAlign.start,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: compact ? WrapAlignment.center : WrapAlignment.start,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            if (!isWaveRunning) {
                              waveController.startWave(
                                seedTrack: currentTrack,
                                playerController: playerController,
                              );
                            }
                            onOpenWave();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                          icon: Icon(
                            isWaveRunning
                                ? Icons.graphic_eq_rounded
                                : Icons.auto_awesome_rounded,
                            size: 20,
                          ),
                          label: Text(
                            isWaveRunning ? 'Открыть Волну' : 'Запустить Мою Волну',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onOpenSearch,
                          icon: const Icon(Icons.search_rounded, size: 20),
                          label: const Text('Поиск'),
                        ),
                        _MetricBadge(label: 'Избранное', value: '$favoriteCount'),
                        _MetricBadge(label: 'Плейлисты', value: '$playlistCount'),
                      ],
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 28),
                discWidget,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      radius: AppTheme.radiusLg,
      color: Colors.black.withValues(alpha: 0.24),
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onOpenWave,
    required this.onOpenSearch,
    required this.onOpenFavorites,
    required this.onOpenPlaylists,
  });

  final VoidCallback onOpenWave;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenPlaylists;

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('Моя Волна', 'Умный бесконечный поток', Icons.waves_rounded, onOpenWave),
      ('Поиск', 'Треки, артисты, альбомы', Icons.manage_search_rounded, onOpenSearch),
      ('Избранное', 'Сохранённые треки', Icons.favorite_rounded, onOpenFavorites),
      ('Плейлисты', 'Коллекции и импорт', Icons.queue_music_rounded, onOpenPlaylists),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 980
            ? 4
            : constraints.maxWidth > 580
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 96,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            final isWave = index == 0;
            return PremiumSurface(
              shadow: true,
              padding: const EdgeInsets.all(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                onTap: action.$4,
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        color: isWave
                            ? AppTheme.accent.withValues(alpha: 0.22)
                            : AppTheme.accent.withValues(alpha: 0.12),
                        border: Border.all(
                          color: isWave
                              ? AppTheme.accent.withValues(alpha: 0.45)
                              : AppTheme.accent.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Icon(
                        action.$3,
                        color: isWave ? AppTheme.accent2 : AppTheme.accent2.withValues(alpha: 0.85),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(action.$1, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 3),
                          Text(action.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 16, color: AppTheme.textMuted),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TrackRail extends StatelessWidget {
  const _TrackRail({
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.loading,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onPlay,
  });

  final String title;
  final String subtitle;
  final List<Track> tracks;
  final bool loading;
  final String emptyTitle;
  final String emptySubtitle;
  final void Function(int index, List<Track> tracks) onPlay;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, subtitle: subtitle, onSeeAll: () {}),
          const SizedBox(height: 16),
          if (loading)
            const Column(
              children: [
                LoadingSkeleton(height: 58),
                SizedBox(height: 10),
                LoadingSkeleton(height: 58),
                SizedBox(height: 10),
                LoadingSkeleton(height: 58),
              ],
            )
          else if (tracks.isEmpty)
            EmptyStateWidget(title: emptyTitle, subtitle: emptySubtitle, icon: Icons.queue_music_rounded)
          else
            SizedBox(
              height: 238,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return MediaCard(
                    title: track.title,
                    subtitle: track.artist.isEmpty ? track.source : track.artist,
                    imageUrl: track.image,
                    onPlay: track.hasPlayableUrl ? () => onPlay(index, tracks) : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MoodRail extends StatelessWidget {
  const _MoodRail();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Night Drive', 'Deep electronic pulse', Icons.nightlight_round),
      ('Red Room', 'Dark pop and velvet bass', Icons.local_fire_department_rounded),
      ('Focus Noir', 'Minimal beats for work', Icons.blur_on_rounded),
      ('Afterhours', 'Late city atmosphere', Icons.bolt_rounded),
    ];

    return PremiumSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Подборки по вайбу',
            subtitle: 'Cinematic, focus, night drive and red-room energy.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 146,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = items[index];
                return SizedBox(
                  width: 238,
                  child: PremiumSurface(
                    padding: const EdgeInsets.all(18),
                    radius: AppTheme.radiusLg,
                    color: AppTheme.surfaceMuted.withValues(alpha: 0.56),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.$3, color: AppTheme.accent2),
                        const Spacer(),
                        Text(item.$1, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 5),
                        Text(item.$2, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistSection extends StatelessWidget {
  const _PlaylistSection({required this.playlists, required this.loading});

  final List<PlaylistSummary> playlists;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Мои плейлисты',
            subtitle: 'Коллекции, импорт и быстрый возврат к своим подборкам.',
          ),
          const SizedBox(height: 16),
          if (loading)
            const LoadingSkeleton(height: 120)
          else if (playlists.isEmpty)
            const EmptyStateWidget(
              title: 'Плейлистов пока нет',
              subtitle: 'Создайте первую подборку или импортируйте музыку из сервиса.',
              icon: Icons.playlist_add_rounded,
            )
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: playlists.take(8).map((playlist) {
                return SizedBox(
                  width: 246,
                  child: PremiumSurface(
                    padding: const EdgeInsets.all(16),
                    radius: AppTheme.radiusLg,
                    color: AppTheme.surfaceMuted.withValues(alpha: 0.58),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [AppTheme.accent, AppTheme.accentWarm],
                            ),
                          ),
                          child: const Icon(Icons.library_music_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                playlist.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text('${playlist.trackCount} треков', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
        ],
      ),
    );
  }
}
