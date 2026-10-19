import 'package:flutter/material.dart';

import '../../core/controllers/player_controller.dart';
import '../../core/models/artist.dart';
import '../../core/models/track.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/wave_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/disc_beat_glow.dart';
import '../../widgets/premium_components.dart';
import '../../widgets/service_chip.dart';
import '../../widgets/ui_kit.dart';

class WavePage extends StatefulWidget {
  const WavePage({
    super.key,
    required this.waveController,
    required this.playerController,
    required this.authService,
    required this.isFavoriteTrack,
    required this.onToggleFavorite,
    this.onOpenArtist,
    this.onOpenAlbum,
  });

  final WaveController waveController;
  final PlayerController playerController;
  final AuthService authService;
  final bool Function(Track? track) isFavoriteTrack;
  final ValueChanged<Track> onToggleFavorite;
  final ValueChanged<ArtistSummary>? onOpenArtist;
  final ValueChanged<Track>? onOpenAlbum;

  @override
  State<WavePage> createState() => _WavePageState();
}

class _WavePageState extends State<WavePage> {
  int _beatTick = 0;

  @override
  void initState() {
    super.initState();
    widget.playerController.addListener(_onPlayerStateChanged);
  }

  @override
  void dispose() {
    widget.playerController.removeListener(_onPlayerStateChanged);
    super.dispose();
  }

  void _onPlayerStateChanged() {
    widget.waveController.onPlayerTick(widget.playerController);
    if (widget.playerController.isPlaying) {
      setState(() {
        _beatTick++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.waveController, widget.playerController]),
      builder: (context, _) {
        final currentTrack = widget.playerController.currentTrack;
        final isPlaying = widget.playerController.isPlaying;
        final isWaveRunning = widget.waveController.isRunning;
        final isLoading = widget.waveController.isLoading;
        final isFavorite = widget.isFavoriteTrack(currentTrack);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = MediaQuery.sizeOf(context).width < 720;

            if (isMobile) {
              return _buildMobileLayout(
                context,
                currentTrack: currentTrack,
                isPlaying: isPlaying,
                isWaveRunning: isWaveRunning,
                isLoading: isLoading,
                isFavorite: isFavorite,
              );
            }

            return _buildDesktopLayout(
              context,
              currentTrack: currentTrack,
              isPlaying: isPlaying,
              isWaveRunning: isWaveRunning,
              isLoading: isLoading,
              isFavorite: isFavorite,
            );
          },
        );
      },
    );
  }

  Widget _buildMobileLayout(
    BuildContext context, {
    required Track? currentTrack,
    required bool isPlaying,
    required bool isWaveRunning,
    required bool isLoading,
    required bool isFavorite,
  }) {
    const glowSize = 210.0;
    const discSize = 165.0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Status Header (compact, horizontal scrolling pills)
            _WaveHeader(
              controller: widget.waveController,
              isMobile: true,
              onModeChanged: (mode) {
                widget.waveController.setMode(
                  mode,
                  playerController: widget.playerController,
                );
              },
            ),
            const SizedBox(height: 16),

            // Center Vinyl Disc with Animated Radial Beat Glow
            SizedBox(
              height: glowSize + 16,
              child: Center(
                child: DiscBeatGlow(
                  isPlaying: isPlaying,
                  level: isPlaying ? 0.75 : 0.05,
                  beatTick: _beatTick,
                  glowSize: glowSize,
                  child: MyWaveDisc(
                    spin: isWaveRunning && isPlaying,
                    size: discSize,
                    enabled: !isLoading,
                    artworkUrl: currentTrack?.image,
                    onPlayClick: () {
                      if (!isWaveRunning) {
                        widget.waveController.startWave(
                          seedTrack: currentTrack,
                          playerController: widget.playerController,
                        );
                      } else {
                        widget.playerController.togglePlayPause();
                      }
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Track Info (Spotify style: left-aligned, smaller artist text)
            if (currentTrack != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentTrack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                          ),
                        ),
                        if (currentTrack.source.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ServiceChip(label: currentTrack.source),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: widget.onOpenArtist != null &&
                              currentTrack.artist.isNotEmpty
                          ? () => widget.onOpenArtist!(
                                ArtistSummary(
                                  artistName: currentTrack.artist,
                                  source: currentTrack.source,
                                  artistId: currentTrack.artistId,
                                ),
                              )
                          : null,
                      child: Text(
                        currentTrack.artist.isEmpty
                            ? 'Неизвестный исполнитель'
                            : currentTrack.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Моя Волна',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Бесконечный персональный поток треков',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Playback and Wave Action Controls (Spotify style touch targets & spacing)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Dislike button
                IconButton.filledTonal(
                  onPressed: currentTrack != null && !isLoading
                      ? () => widget.waveController.dislikeTrack(
                            currentTrack,
                            playerController: widget.playerController,
                          )
                      : null,
                  tooltip: 'Не нравится (убрать из волны)',
                  icon: const Icon(Icons.thumb_down_outlined, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white.withValues(alpha: 0.7),
                    padding: const EdgeInsets.all(10),
                    minimumSize: const Size(44, 44),
                  ),
                ),

                // Previous track
                IconButton.filledTonal(
                  onPressed: widget.playerController.canPlayPrevious
                      ? () => widget.playerController.playPrevious()
                      : null,
                  tooltip: 'Предыдущий трек',
                  icon: const Icon(Icons.skip_previous_rounded, size: 26),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(10),
                    minimumSize: const Size(44, 44),
                  ),
                ),

                // Center Play / Start Wave Button
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.45),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: IconButton.filled(
                    onPressed: isLoading
                        ? null
                        : () {
                            if (!isWaveRunning) {
                              widget.waveController.startWave(
                                seedTrack: currentTrack,
                                playerController: widget.playerController,
                              );
                            } else {
                              widget.playerController.togglePlayPause();
                            }
                          },
                    iconSize: 34,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(14),
                      minimumSize: const Size(60, 60),
                    ),
                    icon: isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                  ),
                ),

                // Next track
                IconButton.filledTonal(
                  onPressed: widget.playerController.canPlayNext
                      ? () => widget.playerController.playNext()
                      : null,
                  tooltip: 'Следующий трек',
                  icon: const Icon(Icons.skip_next_rounded, size: 26),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(10),
                    minimumSize: const Size(44, 44),
                  ),
                ),

                // Favorite / Like button
                IconButton.filledTonal(
                  onPressed: currentTrack != null
                      ? () => widget.onToggleFavorite(currentTrack)
                      : null,
                  tooltip: isFavorite ? 'В избранном' : 'Добавить в избранное',
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavorite ? AppTheme.accent2 : null,
                    size: 20,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: isFavorite
                        ? AppTheme.accent.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08),
                    foregroundColor: isFavorite ? AppTheme.accent2 : Colors.white,
                    padding: const EdgeInsets.all(10),
                    minimumSize: const Size(44, 44),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Wave Queue Preview (no PremiumSurface wrapper on mobile)
            _WaveQueuePreview(
              playerController: widget.playerController,
              onOpenAlbum: widget.onOpenAlbum,
              isMobile: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context, {
    required Track? currentTrack,
    required bool isPlaying,
    required bool isWaveRunning,
    required bool isLoading,
    required bool isFavorite,
  }) {
    const glowSize = 300.0;
    const discSize = 230.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: 28,
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top Status Header
          _WaveHeader(
            controller: widget.waveController,
            onModeChanged: (mode) {
              widget.waveController.setMode(
                mode,
                playerController: widget.playerController,
              );
            },
          ),
          const SizedBox(height: 20),

          // Center Vinyl Disc with Animated Radial Beat Glow
          SizedBox(
            height: glowSize + 20,
            child: Center(
              child: DiscBeatGlow(
                isPlaying: isPlaying,
                level: isPlaying ? 0.75 : 0.05,
                beatTick: _beatTick,
                glowSize: glowSize,
                child: MyWaveDisc(
                  spin: isWaveRunning && isPlaying,
                  size: discSize,
                  enabled: !isLoading,
                  artworkUrl: currentTrack?.image,
                  onPlayClick: () {
                    if (!isWaveRunning) {
                      widget.waveController.startWave(
                        seedTrack: currentTrack,
                        playerController: widget.playerController,
                      );
                    } else {
                      widget.playerController.togglePlayPause();
                    }
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Track Info
          if (currentTrack != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(
                    currentTrack.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: widget.onOpenArtist != null &&
                            currentTrack.artist.isNotEmpty
                        ? () => widget.onOpenArtist!(
                              ArtistSummary(
                                artistName: currentTrack.artist,
                                source: currentTrack.source,
                                artistId: currentTrack.artistId,
                              ),
                            )
                        : null,
                    child: Text(
                      currentTrack.artist.isEmpty
                          ? 'Неизвестный исполнитель'
                          : currentTrack.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: AppTheme.accent2,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (currentTrack.source.isNotEmpty)
                    ServiceChip(label: currentTrack.source),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Моя Волна',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Бесконечный персональный поток треков',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
          ],

          const SizedBox(height: 24),

          // Playback and Wave Action Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Dislike button
              IconButton.filledTonal(
                onPressed: currentTrack != null && !isLoading
                    ? () => widget.waveController.dislikeTrack(
                          currentTrack,
                          playerController: widget.playerController,
                        )
                    : null,
                tooltip: 'Не нравится (убрать из волны)',
                icon: const Icon(Icons.thumb_down_outlined, size: 22),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white.withValues(alpha: 0.7),
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(width: 14),

              // Previous track
              IconButton.filledTonal(
                onPressed: widget.playerController.canPlayPrevious
                    ? () => widget.playerController.playPrevious()
                    : null,
                tooltip: 'Предыдущий трек',
                icon: const Icon(Icons.skip_previous_rounded, size: 26),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(width: 14),

              // Center Play / Start Wave Button
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: IconButton.filled(
                  onPressed: isLoading
                      ? null
                      : () {
                          if (!isWaveRunning) {
                            widget.waveController.startWave(
                              seedTrack: currentTrack,
                              playerController: widget.playerController,
                            );
                          } else {
                            widget.playerController.togglePlayPause();
                          }
                        },
                  iconSize: 38,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ),
              const SizedBox(width: 14),

              // Next track
              IconButton.filledTonal(
                onPressed: widget.playerController.canPlayNext
                    ? () => widget.playerController.playNext()
                    : null,
                tooltip: 'Следующий трек',
                icon: const Icon(Icons.skip_next_rounded, size: 26),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(width: 14),

              // Favorite / Like button
              IconButton.filledTonal(
                onPressed: currentTrack != null
                    ? () => widget.onToggleFavorite(currentTrack)
                    : null,
                tooltip: isFavorite ? 'В избранном' : 'Добавить в избранное',
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? AppTheme.accent2 : null,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isFavorite
                      ? AppTheme.accent.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  foregroundColor: isFavorite ? AppTheme.accent2 : Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Wave Queue Preview
          _WaveQueuePreview(
            playerController: widget.playerController,
            onOpenAlbum: widget.onOpenAlbum,
          ),
        ],
      ),
    );
  }
}

class _WaveHeader extends StatelessWidget {
  const _WaveHeader({
    required this.controller,
    required this.onModeChanged,
    this.isMobile = false,
  });

  final WaveController controller;
  final ValueChanged<WaveMode> onModeChanged;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accent.withValues(alpha: 0.16),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(
                    Icons.waves_rounded,
                    color: AppTheme.accent2,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Моя Волна',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        controller.statusMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                      ),
                    ],
                  ),
                ),
                if (controller.isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Mode pills with horizontal scrolling
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _ModeChip(
                    label: 'Моя Волна',
                    selected: controller.mode == WaveMode.flow,
                    onTap: () => onModeChanged(WaveMode.flow),
                    isMobile: true,
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: 'Открытия',
                    selected: controller.mode == WaveMode.exploration,
                    onTap: () => onModeChanged(WaveMode.exploration),
                    isMobile: true,
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: 'Любимое',
                    selected: controller.mode == WaveMode.favorites,
                    onTap: () => onModeChanged(WaveMode.favorites),
                    isMobile: true,
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: 'Драйв',
                    selected: controller.mode == WaveMode.energy,
                    onTap: () => onModeChanged(WaveMode.energy),
                    isMobile: true,
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: 'Спокойное',
                    selected: controller.mode == WaveMode.calm,
                    onTap: () => onModeChanged(WaveMode.calm),
                    isMobile: true,
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: 'Популярное',
                    selected: controller.mode == WaveMode.coldStart,
                    onTap: () => onModeChanged(WaveMode.coldStart),
                    isMobile: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: AppTheme.strokeSoft),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.waves_rounded,
                    color: AppTheme.accent2, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Моя Волна',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      controller.statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              if (controller.isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Mode pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _ModeChip(
                  label: 'Моя Волна',
                  selected: controller.mode == WaveMode.flow,
                  onTap: () => onModeChanged(WaveMode.flow),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Открытия',
                  selected: controller.mode == WaveMode.exploration,
                  onTap: () => onModeChanged(WaveMode.exploration),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Любимое',
                  selected: controller.mode == WaveMode.favorites,
                  onTap: () => onModeChanged(WaveMode.favorites),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Драйв',
                  selected: controller.mode == WaveMode.energy,
                  onTap: () => onModeChanged(WaveMode.energy),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Спокойное',
                  selected: controller.mode == WaveMode.calm,
                  onTap: () => onModeChanged(WaveMode.calm),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Популярное',
                  selected: controller.mode == WaveMode.coldStart,
                  onTap: () => onModeChanged(WaveMode.coldStart),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isMobile = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected
                ? AppTheme.accent
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: selected
                  ? AppTheme.accent
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? Colors.white : Colors.white.withValues(alpha: 0.7),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 12,
                ),
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.5)
                : AppTheme.strokeSoft,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected ? Colors.white : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}

class _WaveQueuePreview extends StatelessWidget {
  const _WaveQueuePreview({
    required this.playerController,
    this.onOpenAlbum,
    this.isMobile = false,
  });

  final PlayerController playerController;
  final ValueChanged<Track>? onOpenAlbum;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final queue = playerController.queue;
    final currentIndex = playerController.currentIndex;
    final upcoming = currentIndex >= 0 && currentIndex + 1 < queue.length
        ? queue.sublist(currentIndex + 1).take(8).toList()
        : <Track>[];

    if (upcoming.isEmpty) {
      return const SizedBox.shrink();
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.queue_music_rounded,
                size: 20, color: AppTheme.accent2),
            const SizedBox(width: 8),
            Text(
              'Далее в Волне',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            Text(
              '${playerController.remainingTracksCount} треков осталось',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: isMobile ? 12 : null,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: upcoming.length,
          separatorBuilder: (_, __) => Divider(
            height: 8,
            thickness: 0.5,
            color: isMobile ? Colors.white.withValues(alpha: 0.08) : null,
          ),
          itemBuilder: (context, index) {
            final track = upcoming[index];
            final absoluteIndex = currentIndex + 1 + index;
            return InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: () => playerController.playAt(absoluteIndex),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: isMobile ? 4 : 6,
                  horizontal: isMobile ? 4 : 8,
                ),
                child: Row(
                  children: [
                    UnmuteArtwork(
                      imageUrl: track.image,
                      size: isMobile ? 40 : 42,
                      radius: AppTheme.radiusMd,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      ServiceChip(label: track.source),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        child: content,
      );
    }

    return PremiumSurface(
      padding: const EdgeInsets.all(16),
      radius: AppTheme.radiusXl,
      child: content,
    );
  }
}
