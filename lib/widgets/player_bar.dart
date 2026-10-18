import 'package:flutter/material.dart';

import '../core/controllers/player_controller.dart' as player;
import '../core/models/track.dart';
import '../core/services/lyrics_service.dart';
import '../theme/app_theme.dart';
import 'premium_components.dart';
import 'service_chip.dart';
import 'ui_kit.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.controller,
    required this.isFavoriteTrack,
    required this.onToggleFavorite,
  });

  final player.PlayerController controller;
  final bool Function(Track track) isFavoriteTrack;
  final ValueChanged<Track> onToggleFavorite;

  @override
  Widget build(BuildContext context) => BottomPlayerBar(
        controller: controller,
        isFavoriteTrack: isFavoriteTrack,
        onToggleFavorite: onToggleFavorite,
      );
}

class BottomPlayerBar extends StatelessWidget {
  const BottomPlayerBar({
    super.key,
    required this.controller,
    required this.isFavoriteTrack,
    required this.onToggleFavorite,
  });

  final player.PlayerController controller;
  final bool Function(Track track) isFavoriteTrack;
  final ValueChanged<Track> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasTrack) return const SizedBox.shrink();

    final compact = MediaQuery.sizeOf(context).width < 980;
    final track = controller.currentTrack!;
    final totalMs = controller.duration.inMilliseconds <= 0
        ? 1.0
        : controller.duration.inMilliseconds.toDouble();
    final posMs = controller.position.inMilliseconds
        .clamp(
            0,
            controller.duration.inMilliseconds <= 0
                ? 1
                : controller.duration.inMilliseconds)
        .toDouble();

    void openFullscreen() {
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          pageBuilder: (_, __, ___) =>
              _FullscreenPlayer(
                controller: controller,
                isFavoriteTrack: isFavoriteTrack,
                onToggleFavorite: onToggleFavorite,
              ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GlassSurface(
        padding:
            EdgeInsets.fromLTRB(18, compact ? 14 : 12, 18, compact ? 14 : 12),
        radius: 22,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((controller.error ?? '').isNotEmpty) ...[
              _PlayerError(message: controller.error!),
              const SizedBox(height: 10),
            ],
            compact
                ? _CompactPlayer(
                    controller: controller,
                    track: track,
                    isFavorite: isFavoriteTrack(track),
                    onToggleFavorite: onToggleFavorite,
                    totalMs: totalMs,
                    posMs: posMs,
                    onExpand: openFullscreen,
                  )
                : _WidePlayer(
                    controller: controller,
                    track: track,
                    isFavorite: isFavoriteTrack(track),
                    onToggleFavorite: onToggleFavorite,
                    totalMs: totalMs,
                    posMs: posMs,
                    onExpand: openFullscreen,
                  ),
          ],
        ),
      ),
    );
  }
}

class _WidePlayer extends StatelessWidget {
  const _WidePlayer({
    required this.controller,
    required this.track,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.totalMs,
    required this.posMs,
    required this.onExpand,
  });

  final player.PlayerController controller;
  final Track track;
  final bool isFavorite;
  final ValueChanged<Track> onToggleFavorite;
  final double totalMs;
  final double posMs;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _TrackIdentity(
            track: track,
            isFavorite: isFavorite,
            onToggleFavorite: onToggleFavorite,
          ),
        ),
        Expanded(
          flex: 4,
          child: _Transport(
              controller: controller, totalMs: totalMs, posMs: posMs),
        ),
        Expanded(
            flex: 3,
            child:
                _UtilityControls(controller: controller, onExpand: onExpand)),
      ],
    );
  }
}

class _CompactPlayer extends StatelessWidget {
  const _CompactPlayer({
    required this.controller,
    required this.track,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.totalMs,
    required this.posMs,
    required this.onExpand,
  });

  final player.PlayerController controller;
  final Track track;
  final bool isFavorite;
  final ValueChanged<Track> onToggleFavorite;
  final double totalMs;
  final double posMs;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TrackIdentity(
                track: track,
                compact: true,
                isFavorite: isFavorite,
                onToggleFavorite: onToggleFavorite,
              ),
            ),
            const SizedBox(width: 10),
            PlayButton(
              playing: controller.isPlaying,
              size: 52,
              onTap: controller.togglePlayPause,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Progress(controller: controller, totalMs: totalMs, posMs: posMs),
        const SizedBox(height: 10),
        _UtilityControls(
            controller: controller, compact: true, onExpand: onExpand),
      ],
    );
  }
}

class _TrackIdentity extends StatelessWidget {
  const _TrackIdentity({
    required this.track,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.compact = false,
  });

  final Track track;
  final bool isFavorite;
  final ValueChanged<Track> onToggleFavorite;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UnmuteArtwork(
            imageUrl: track.image, size: compact ? 52 : 58, radius: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                track.artist.isEmpty ? 'Unknown artist' : track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PremiumIconButton(
          icon: isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          selected: isFavorite,
          tooltip: 'Like',
          size: 36,
          onTap: () => onToggleFavorite(track),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.controller,
    required this.totalMs,
    required this.posMs,
  });

  final player.PlayerController controller;
  final double totalMs;
  final double posMs;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PremiumIconButton(
              icon: Icons.shuffle_rounded,
              selected: controller.shuffleEnabled,
              tooltip: 'Shuffle',
              size: 36,
              onTap: controller.toggleShuffle,
            ),
            const SizedBox(width: 8),
            PremiumIconButton(
              icon: Icons.skip_previous_rounded,
              tooltip: 'Previous',
              size: 42,
              onTap: controller.playPrevious,
            ),
            const SizedBox(width: 8),
            PlayButton(
              playing: controller.isPlaying,
              size: 58,
              onTap: controller.togglePlayPause,
            ),
            const SizedBox(width: 8),
            PremiumIconButton(
              icon: Icons.skip_next_rounded,
              tooltip: 'Next',
              size: 42,
              onTap: controller.playNext,
            ),
            const SizedBox(width: 8),
            PremiumIconButton(
              icon: switch (controller.repeatMode) {
                player.RepeatMode.one => Icons.repeat_one_rounded,
                _ => Icons.repeat_rounded,
              },
              selected: controller.repeatMode != player.RepeatMode.off,
              tooltip: 'Repeat',
              size: 36,
              onTap: controller.cycleRepeatMode,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Progress(controller: controller, totalMs: totalMs, posMs: posMs),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.controller,
    required this.totalMs,
    required this.posMs,
  });

  final player.PlayerController controller;
  final double totalMs;
  final double posMs;

  String _fmt(Duration d) {
    final total = d.inSeconds;
    final m = (total ~/ 60).toString();
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
            width: 42,
            child: Text(_fmt(controller.position),
                style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Slider(
            value: posMs,
            min: 0,
            max: totalMs,
            onChanged: (value) =>
                controller.seek(Duration(milliseconds: value.toInt())),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            _fmt(controller.duration),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _UtilityControls extends StatelessWidget {
  const _UtilityControls({
    required this.controller,
    required this.onExpand,
    this.compact = false,
  });

  final player.PlayerController controller;
  final VoidCallback onExpand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final volume = controller.volume.clamp(0, 100).toDouble();

    return Row(
      mainAxisAlignment:
          compact ? MainAxisAlignment.center : MainAxisAlignment.end,
      children: [
        if (!compact) ...[
          const SizedBox(width: 8),
          Icon(
            volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: AppTheme.textSecondary,
            size: 19,
          ),
          SizedBox(
            width: 126,
            child: Slider(
              value: volume,
              min: 0,
              max: 100,
              onChanged: controller.setVolume,
            ),
          ),
        ],
        PremiumIconButton(
            icon: Icons.open_in_full_rounded,
            tooltip: 'Expand',
            size: 36,
            onTap: onExpand),
      ],
    );
  }
}

class _FullscreenPlayer extends StatefulWidget {
  const _FullscreenPlayer({
    required this.controller,
    required this.isFavoriteTrack,
    required this.onToggleFavorite,
  });

  final player.PlayerController controller;
  final bool Function(Track track) isFavoriteTrack;
  final ValueChanged<Track> onToggleFavorite;

  @override
  State<_FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<_FullscreenPlayer> {
  bool _showLyrics = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final track = controller.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final totalMs = controller.duration.inMilliseconds <= 0
            ? 1.0
            : controller.duration.inMilliseconds.toDouble();
        final posMs = controller.position.inMilliseconds
            .clamp(
              0,
              controller.duration.inMilliseconds <= 0
                  ? 1
                  : controller.duration.inMilliseconds,
            )
            .toDouble();

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: DynamicGradientBackground(
            artwork: track.image,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('UNMUTE',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        PremiumIconButton(
                          icon: widget.isFavoriteTrack(track)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          selected: widget.isFavoriteTrack(track),
                          tooltip: 'Like',
                          onTap: () => widget.onToggleFavorite(track),
                        ),
                        const SizedBox(width: 8),
                        PremiumIconButton(
                          icon: _showLyrics
                              ? Icons.lyrics_rounded
                              : Icons.lyrics_outlined,
                          selected: _showLyrics,
                          tooltip: 'Lyrics',
                          onTap: () =>
                              setState(() => _showLyrics = !_showLyrics),
                        ),
                        const SizedBox(width: 8),
                        PremiumIconButton(
                          icon: Icons.close_fullscreen_rounded,
                          tooltip: 'Close',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final artworkSize =
                              constraints.maxWidth < 720 ? 180.0 : 360.0;
                          if (!_showLyrics) {
                            return Center(
                              child: _FullscreenTrackInfo(
                                track: track,
                                artworkSize: artworkSize,
                              ),
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      UnmuteArtwork(
                                        imageUrl: track.image,
                                        size: artworkSize,
                                        radius: AppTheme.radiusXl,
                                      ),
                                      const SizedBox(height: 28),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 760),
                                        child: Column(
                                          children: [
                                            Text(
                                              track.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .displayMedium,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              track.artist.isEmpty
                                                  ? 'Unknown artist'
                                                  : track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              (track.albumTitle ?? '')
                                                      .trim()
                                                      .isEmpty
                                                  ? 'Альбом не указан'
                                                  : track.albumTitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 6,
                                child: SizedBox(
                                  height: artworkSize,
                                  child: _FullscreenLyricsView(
                                    controller: controller,
                                    track: track,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _Transport(
                          controller: controller,
                          totalMs: totalMs,
                          posMs: posMs),
                    ),
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _UtilityControls(
                        controller: controller,
                        onExpand: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FullscreenTrackInfo extends StatelessWidget {
  const _FullscreenTrackInfo({
    required this.track,
    required this.artworkSize,
  });

  final Track track;
  final double artworkSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        UnmuteArtwork(
          imageUrl: track.image,
          size: artworkSize,
          radius: AppTheme.radiusXl,
        ),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                track.artist.isEmpty ? 'Unknown artist' : track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                (track.albumTitle ?? '').trim().isEmpty
                    ? 'Альбом не указан'
                    : track.albumTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncedLyricsPanel extends StatefulWidget {
  const _SyncedLyricsPanel({
    required this.controller,
    required this.track,
  });

  final player.PlayerController controller;
  final Track track;

  @override
  State<_SyncedLyricsPanel> createState() => _SyncedLyricsPanelState();
}

class _FullscreenLyricsView extends StatefulWidget {
  const _FullscreenLyricsView({
    required this.controller,
    required this.track,
  });

  final player.PlayerController controller;
  final Track track;

  @override
  State<_FullscreenLyricsView> createState() => _FullscreenLyricsViewState();
}

class _FullscreenLyricsViewState extends State<_FullscreenLyricsView> {
  final LyricsService _lyricsService = LyricsService();
  Future<LyricsResult?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FullscreenLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _load();
    }
  }

  void _load() {
    _future = _lyricsService.loadLyrics(
      track: widget.track,
      duration: widget.controller.duration,
    );
  }

  int _activeIndex(List<LyricLine> lines, Duration position) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LyricsResult?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _LyricsEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Не удалось загрузить текст',
            subtitle: 'Проверь подключение и попробуй открыть плеер снова.',
          );
        }

        final result = snapshot.data;
        if (result == null) {
          return const _LyricsEmptyState(
            icon: Icons.lyrics_outlined,
            title: 'Текст не найден',
            subtitle: 'Для этого трека пока нет синхронизированного текста.',
          );
        }
        if (result.instrumental) {
          return const _LyricsEmptyState(
            icon: Icons.music_note_rounded,
            title: 'Инструментал',
            subtitle: 'У трека нет вокального текста.',
          );
        }
        if (!result.hasSyncedLyrics) {
          return _PlainLyricsView(text: result.plainLyrics);
        }

        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final active = _activeIndex(
              result.lines,
              widget.controller.position,
            );
            final previous = active > 0 ? result.lines[active - 1].text : '';
            final current = active >= 0 && active < result.lines.length
                ? result.lines[active].text
                : '';
            final next = active + 1 < result.lines.length
                ? result.lines[active + 1].text
                : '';

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Column(
                key: ValueKey(active),
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FocusedLyricLine(
                    text: previous,
                    role: _LyricLineRole.previous,
                  ),
                  const SizedBox(height: 18),
                  _FocusedLyricLine(
                    text: current,
                    role: _LyricLineRole.current,
                  ),
                  const SizedBox(height: 18),
                  _FocusedLyricLine(
                    text: next,
                    role: _LyricLineRole.next,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

enum _LyricLineRole { previous, current, next }

class _FocusedLyricLine extends StatelessWidget {
  const _FocusedLyricLine({
    required this.text,
    required this.role,
  });

  final String text;
  final _LyricLineRole role;

  @override
  Widget build(BuildContext context) {
    final normalizedText = text.trim().isEmpty ? '...' : text.trim();
    final selected = role == _LyricLineRole.current;
    final baseStyle = selected
        ? Theme.of(context).textTheme.displaySmall
        : Theme.of(context).textTheme.headlineSmall;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: selected ? 1 : 0.52,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        style: baseStyle?.copyWith(
              color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
            ) ??
            const TextStyle(),
        child: Text(
          normalizedText,
          maxLines: selected ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SyncedLyricsPanelState extends State<_SyncedLyricsPanel> {
  final LyricsService _lyricsService = LyricsService();
  final ScrollController _scrollController = ScrollController();
  Future<LyricsResult?>? _future;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _lastActiveIndex = -1;
      _load();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _load() {
    _future = _lyricsService.loadLyrics(
      track: widget.track,
      duration: widget.controller.duration,
    );
  }

  int _activeIndex(List<LyricLine> lines, Duration position) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  void _scrollToActive(int index) {
    if (index < 0 ||
        index == _lastActiveIndex ||
        !_scrollController.hasClients) {
      return;
    }
    _lastActiveIndex = index;
    final target = (index * 56.0 - 112).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.all(16),
      radius: AppTheme.radiusXl,
      color: AppTheme.surface.withValues(alpha: 0.48),
      child: Column(
        children: [
          Row(
            children: [
              Text('Текст', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text('LRCLIB', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<LyricsResult?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _LyricsEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Не удалось загрузить текст',
                    subtitle:
                        'Проверь подключение и попробуй открыть плеер снова.',
                  );
                }

                final result = snapshot.data;
                if (result == null) {
                  return const _LyricsEmptyState(
                    icon: Icons.lyrics_outlined,
                    title: 'Текст не найден',
                    subtitle:
                        'Для этого трека в LRCLIB пока нет синхронизированного текста.',
                  );
                }
                if (result.instrumental) {
                  return const _LyricsEmptyState(
                    icon: Icons.music_note_rounded,
                    title: 'Инструментал',
                    subtitle: 'У трека нет вокального текста.',
                  );
                }
                if (!result.hasSyncedLyrics) {
                  return _PlainLyricsView(text: result.plainLyrics);
                }

                return AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final active = _activeIndex(
                      result.lines,
                      widget.controller.position,
                    );
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToActive(active),
                    );
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 96),
                      itemCount: result.lines.length,
                      itemBuilder: (context, index) {
                        final line = result.lines[index];
                        final selected = index == active;
                        return AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          style: (selected
                                      ? Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                      : Theme.of(context).textTheme.titleMedium)
                                  ?.copyWith(
                                color: selected
                                    ? AppTheme.textPrimary
                                    : AppTheme.textMuted,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ) ??
                              const TextStyle(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              line.text.isEmpty ? '...' : line.text,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainLyricsView extends StatelessWidget {
  const _PlainLyricsView({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final value = (text ?? '').trim();
    if (value.isEmpty) {
      return const _LyricsEmptyState(
        icon: Icons.lyrics_outlined,
        title: 'Синхронизации нет',
        subtitle: 'LRCLIB нашел трек, но без построчной синхронизации.',
      );
    }
    return ListView(
      children: [
        Text(
          value,
          style:
              Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.55),
        ),
      ],
    );
  }
}

class _LyricsEmptyState extends StatelessWidget {
  const _LyricsEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.textMuted, size: 42),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class RightNowPlayingPanel extends StatefulWidget {
  const RightNowPlayingPanel({
    super.key,
    required this.controller,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final player.PlayerController controller;
  final bool isFavorite;
  final ValueChanged<Track> onToggleFavorite;

  @override
  State<RightNowPlayingPanel> createState() => _RightNowPlayingPanelState();
}

class _RightNowPlayingPanelState extends State<RightNowPlayingPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final track = widget.controller.currentTrack;

    return SizedBox(
      width: 326,
      child: GlassSurface(
        padding: const EdgeInsets.all(18),
        radius: AppTheme.radiusXl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Контекст', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                PremiumIconButton(
                    icon: Icons.more_horiz_rounded, size: 34, onTap: () {}),
              ],
            ),
            const SizedBox(height: 14),
            _PanelTabs(
              selected: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: switch (_tab) {
                  0 =>
                    _NowPlayingTab(
                      track: track,
                      controller: widget.controller,
                      isFavorite: widget.isFavorite,
                      onToggleFavorite: widget.onToggleFavorite,
                    ),
                  1 => _QueueTab(controller: widget.controller),
                  _ => _DetailsTab(track: track),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelTabs extends StatelessWidget {
  const _PanelTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Сейчас', 'Очередь', 'Детали'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        color: AppTheme.surfaceMuted.withValues(alpha: 0.62),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: selected == i
                        ? AppTheme.accent.withValues(alpha: 0.18)
                        : Colors.transparent,
                  ),
                  child: Text(
                    labels[i],
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: selected == i
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NowPlayingTab extends StatelessWidget {
  const _NowPlayingTab({
    required this.track,
    required this.controller,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final Track? track;
  final player.PlayerController controller;
  final bool isFavorite;
  final ValueChanged<Track> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (track == null) {
      return const EmptyStateWidget(
        title: 'Ничего не играет',
        subtitle:
            'Запустите трек, чтобы здесь появились обложка, очередь и быстрые действия.',
        icon: Icons.music_note_rounded,
      );
    }
    final item = track!;

    return ListView(
      children: [
        UnmuteArtwork(
            imageUrl: item.image, size: 288, radius: AppTheme.radiusXl),
        const SizedBox(height: 18),
        Text(item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          item.artist.isEmpty ? 'Unknown artist' : item.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            PlayButton(
                playing: controller.isPlaying,
                onTap: controller.togglePlayPause,
                size: 52),
            const SizedBox(width: 10),
            PremiumIconButton(
                icon: isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                selected: isFavorite,
                tooltip: 'Like',
                onTap: () => onToggleFavorite(item)),
            PremiumIconButton(
                icon: Icons.playlist_add_rounded, tooltip: 'Add', onTap: () {}),
            PremiumIconButton(
                icon: Icons.share_rounded, tooltip: 'Share', onTap: () {}),
          ],
        ),
        const SizedBox(height: 18),
        PremiumSurface(
          padding: const EdgeInsets.all(14),
          radius: AppTheme.radiusLg,
          color: AppTheme.surfaceMuted.withValues(alpha: 0.46),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text('${controller.queue.length} треков в очереди',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              if (item.source.isEmpty)
                Text(
                  'Источник не указан',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ServiceChip(label: item.source),
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({required this.controller});

  final player.PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    if (queue.isEmpty) {
      return const EmptyStateWidget(
        title: 'Очередь пуста',
        subtitle: 'Добавьте музыку из поиска или библиотеки.',
        icon: Icons.queue_music_rounded,
      );
    }

    return ListView.separated(
      itemCount: queue.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = queue[index];
        final current = index == controller.currentIndex;
        return InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: item.hasPlayableUrl ? () => controller.playAt(index) : null,
          child: PremiumSurface(
            padding: const EdgeInsets.all(10),
            radius: AppTheme.radiusLg,
            color: current
                ? AppTheme.accent.withValues(alpha: 0.13)
                : AppTheme.surfaceMuted.withValues(alpha: 0.38),
            borderColor: current
                ? AppTheme.accent.withValues(alpha: 0.4)
                : AppTheme.stroke,
            child: Row(
              children: [
                UnmuteArtwork(imageUrl: item.image, size: 42, radius: 11),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(item.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (current)
                  const Icon(Icons.graphic_eq_rounded,
                      color: AppTheme.accent2, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    if (track == null) {
      return const EmptyStateWidget(
        title: 'Деталей пока нет',
        subtitle: 'Откройте трек, чтобы увидеть источник, альбом и метаданные.',
        icon: Icons.info_outline_rounded,
      );
    }
    final item = track!;

    final rows = [
      ('Артист', item.artist.isEmpty ? 'Unknown artist' : item.artist),
      ('Альбом', item.albumTitle ?? 'Не указан'),
      ('Год', item.albumYear?.toString() ?? 'Не указан'),
      ('Источник', item.source.isEmpty ? 'Не указан' : item.source),
    ];

    return ListView(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PremiumSurface(
              padding: const EdgeInsets.all(14),
              radius: AppTheme.radiusLg,
              color: AppTheme.surfaceMuted.withValues(alpha: 0.42),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.$1, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 5),
                  Text(row.$2, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.26)),
      ),
      child: Text(message, style: const TextStyle(color: AppTheme.danger)),
    );
  }
}
