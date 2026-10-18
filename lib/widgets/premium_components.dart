import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/services/artwork_palette_service.dart';
import '../core/models/artist.dart';
import '../core/models/track.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

class DynamicGradientBackground extends StatefulWidget {
  const DynamicGradientBackground({
    super.key,
    required this.child,
    this.accent = AppTheme.accent,
    this.artwork,
  });

  final Widget child;
  final Color accent;
  final String? artwork;

  @override
  State<DynamicGradientBackground> createState() =>
      _DynamicGradientBackgroundState();
}

class _DynamicGradientBackgroundState extends State<DynamicGradientBackground> {
  late Future<Color> _accentFuture;

  @override
  void initState() {
    super.initState();
    _accentFuture = _loadAccent();
  }

  @override
  void didUpdateWidget(covariant DynamicGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artwork != widget.artwork || oldWidget.accent != widget.accent) {
      _accentFuture = _loadAccent();
    }
  }

  Future<Color> _loadAccent() {
    return ArtworkPaletteService.instance.colorFor(
      widget.artwork,
      fallback: widget.accent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Color>(
      future: _accentFuture,
      initialData: widget.accent,
      builder: (context, snapshot) {
        final accentColor = snapshot.data ?? widget.accent;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.62, -0.72),
              radius: 1.18,
              colors: [
                accentColor.withValues(alpha: 0.28),
                Color.lerp(
                      AppTheme.backgroundElevated,
                      accentColor,
                      0.12,
                    )!
                    .withValues(alpha: 0.96),
                AppTheme.background,
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
          child: Stack(
            children: [
              if ((widget.artwork ?? '').trim().isNotEmpty)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.12,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        accentColor.withValues(alpha: 0.38),
                        BlendMode.modulate,
                      ),
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                        child: Image.network(
                          widget.artwork!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: -170,
                right: -120,
                child: _Glow(size: 430, color: accentColor.withValues(alpha: 0.2)),
              ),
              Positioned(
                bottom: -190,
                left: 280,
                child: _Glow(
                  size: 360,
                  color: Color.lerp(accentColor, AppTheme.accentWarm, 0.35)!
                      .withValues(alpha: 0.12),
                ),
              ),
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppTheme.radiusXl,
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.shadow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: color ?? AppTheme.surface.withValues(alpha: 0.78),
        border: Border.all(
            color: borderColor ?? AppTheme.stroke.withValues(alpha: 0.8)),
        boxShadow: shadow ? AppTheme.premiumShadow(alpha: 0.06) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppTheme.radiusXl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: PremiumSurface(
          radius: radius,
          padding: padding,
          color: AppTheme.surfaceSoft.withValues(alpha: 0.7),
          borderColor: Colors.white.withValues(alpha: 0.06),
          child: child,
        ),
      ),
    );
  }
}

class PremiumIconButton extends StatefulWidget {
  const PremiumIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.selected = false,
    this.filled = false,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool selected;
  final bool filled;
  final double size;

  @override
  State<PremiumIconButton> createState() => _PremiumIconButtonState();
}

class _PremiumIconButtonState extends State<PremiumIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || widget.filled;
    final child = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && widget.onTap != null ? 1.04 : 1,
        duration: const Duration(milliseconds: 140),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.size / 2),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppTheme.accent.withValues(alpha: _hovered ? 0.96 : 0.86)
                    : AppTheme.surfaceMuted
                        .withValues(alpha: _hovered ? 0.96 : 0.64),
                border: Border.all(
                  color: active
                      ? AppTheme.accent2.withValues(alpha: 0.72)
                      : AppTheme.stroke.withValues(alpha: 0.92),
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppTheme.accent
                              .withValues(alpha: _hovered ? 0.36 : 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: active ? Colors.white : AppTheme.textSecondary,
                size: widget.size * 0.48,
              ),
            ),
          ),
        ),
      ),
    );

    if ((widget.tooltip ?? '').isEmpty) return child;
    return Tooltip(message: widget.tooltip!, child: child);
  }
}

class PlayButton extends StatelessWidget {
  const PlayButton({
    super.key,
    required this.onTap,
    this.playing = false,
    this.size = 58,
  });

  final VoidCallback? onTap;
  final bool playing;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PremiumIconButton(
      icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      onTap: onTap,
      filled: true,
      size: size,
      tooltip: playing ? 'Pause' : 'Play',
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSeeAll,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton.icon(
            onPressed: onSeeAll,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('See all'),
          ),
      ],
    );
  }
}

class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.onTap,
    this.onPlay,
    this.circle = false,
    this.width = 174,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final bool circle;
  final double width;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.circle ? widget.width / 2 : AppTheme.radiusLg;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: widget.width,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          color: _hovered
              ? AppTheme.surfaceRaised.withValues(alpha: 0.72)
              : Colors.transparent,
          border: Border.all(
            color: _hovered ? AppTheme.strokeSoft : Colors.transparent,
          ),
          boxShadow: _hovered ? AppTheme.premiumShadow(alpha: 0.08) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      UnmuteArtwork(
                        imageUrl: widget.imageUrl,
                        size: widget.width - 24,
                        radius: radius,
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: AnimatedOpacity(
                          opacity: _hovered || widget.onPlay != null ? 1 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: PlayButton(onTap: widget.onPlay, size: 44),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if ((widget.subtitle ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumSearchBar extends StatelessWidget {
  const PremiumSearchBar({
    super.key,
    required this.controller,
    this.hint = 'Search UNMUTE',
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<String> items;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => ActionChipButton(
              label: item,
              selected: selected == item,
              onTap: () => onSelected(item),
            ),
          )
          .toList(growable: false),
    );
  }
}

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.music_off_rounded,
    this.action,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PremiumSurface(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.12),
                border:
                    Border.all(color: AppTheme.accent.withValues(alpha: 0.24)),
              ),
              child: Icon(icon, color: AppTheme.accent2),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            SizedBox(
              width: 420,
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    this.height = 18,
    this.width,
    this.radius = 10,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + _controller.value * 2, 0),
              end: Alignment(0.2 + _controller.value * 2, 0),
              colors: const [
                Color(0xFF17171B),
                Color(0xFF25222A),
                Color(0xFF17171B),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PremiumTrackRow extends StatefulWidget {
  const PremiumTrackRow({
    super.key,
    required this.track,
    this.index,
    this.onPlay,
    this.onFavorite,
    this.onArtist,
    this.onAlbum,
    this.onPlaylist,
    this.onRemove,
    this.isFavorite = false,
    this.isCurrent = false,
  });

  final Track track;
  final int? index;
  final VoidCallback? onPlay;
  final VoidCallback? onFavorite;
  final ValueChanged<ArtistSummary>? onArtist;
  final VoidCallback? onAlbum;
  final VoidCallback? onPlaylist;
  final VoidCallback? onRemove;
  final bool isFavorite;
  final bool isCurrent;

  @override
  State<PremiumTrackRow> createState() => _PremiumTrackRowState();
}

class _PremiumTrackRowState extends State<PremiumTrackRow> {
  bool _hovered = false;

  List<String> _artistNames() {
    final names = widget.track.artist
        .split(RegExp(r'\s*(?:,|;|&|\s+feat\.?\s+|\s+ft\.?\s+|\s+и\s+)\s*',
            caseSensitive: false))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return names.isEmpty ? const [] : names;
  }

  void _openArtist(String name) {
    widget.onArtist?.call(
      ArtistSummary(
        artistName: name,
        source: widget.track.source,
        artistId:
            name == widget.track.artist.trim() ? widget.track.artistId : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: widget.onPlay,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              color: widget.isCurrent
                  ? AppTheme.accent.withValues(alpha: 0.13)
                  : _hovered
                      ? AppTheme.surfaceRaised.withValues(alpha: 0.66)
                      : Colors.transparent,
              border: Border.all(
                color: widget.isCurrent
                    ? AppTheme.accent.withValues(alpha: 0.44)
                    : _hovered
                        ? AppTheme.strokeSoft.withValues(alpha: 0.72)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: widget.isCurrent
                      ? const Icon(Icons.graphic_eq_rounded,
                          color: AppTheme.accent2, size: 18)
                      : Text(
                          widget.index == null ? '' : '${widget.index! + 1}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                ),
                const SizedBox(width: 8),
                UnmuteArtwork(
                    imageUrl: widget.track.image, size: 46, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      _TrackArtists(
                        names: _artistNames(),
                        enabled: widget.onArtist != null,
                        onTap: _openArtist,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _TrackAlbum(
                    title: widget.track.albumTitle,
                    onTap: widget.onAlbum,
                  ),
                ),
                /*
                  child: Text(
                    (widget.track.albumTitle ?? '').trim().isEmpty
                        ? 'Альбом не указан'
                        : widget.track.albumTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                */
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: _hovered || widget.isCurrent ? 1 : 0.68,
                  duration: const Duration(milliseconds: 140),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onFavorite != null)
                        PremiumIconButton(
                          icon: widget.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          selected: widget.isFavorite,
                          tooltip: 'Favorite',
                          size: 34,
                          onTap: widget.onFavorite,
                        ),
                      if (widget.onArtist != null)
                        PremiumIconButton(
                          icon: Icons.person_outline_rounded,
                          tooltip: 'Artist',
                          size: 34,
                          onTap: () => _openArtist(widget.track.artist.trim()),
                        ),
                      if (widget.onAlbum != null)
                        PremiumIconButton(
                          icon: Icons.album_outlined,
                          tooltip: 'Album',
                          size: 34,
                          onTap: widget.onAlbum,
                        ),
                      if (widget.onPlaylist != null)
                        PremiumIconButton(
                          icon: Icons.playlist_add_rounded,
                          tooltip: 'Add to playlist',
                          size: 34,
                          onTap: widget.onPlaylist,
                        ),
                      if (widget.onRemove != null)
                        PremiumIconButton(
                          icon: Icons.delete_outline_rounded,
                          tooltip: 'Remove',
                          size: 34,
                          onTap: widget.onRemove,
                        ),
                      if (widget.onPlay != null) ...[
                        const SizedBox(width: 6),
                        PlayButton(onTap: widget.onPlay, size: 38),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackAlbum extends StatelessWidget {
  const _TrackAlbum({
    required this.title,
    required this.onTap,
  });

  final String? title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final albumTitle = (title ?? '').trim();
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final text = Text(
      albumTitle.isEmpty ? 'Альбом не указан' : albumTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: albumTitle.isEmpty || onTap == null
          ? textStyle
          : textStyle?.copyWith(
              color: AppTheme.textPrimary,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.textMuted,
            ),
    );

    if (albumTitle.isEmpty || onTap == null) return text;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: text,
    );
  }
}

class _TrackArtists extends StatelessWidget {
  const _TrackArtists({
    required this.names,
    required this.enabled,
    required this.onTap,
  });

  final List<String> names;
  final bool enabled;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    if (names.isEmpty) {
      return Text(
        'Unknown artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }

    return SizedBox(
      height: 18,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: names.length,
        separatorBuilder: (context, index) => Text(', ', style: textStyle),
        itemBuilder: (context, index) {
          final name = names[index];
          if (!enabled) {
            return Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle);
          }
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onTap(name),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle?.copyWith(
                color: AppTheme.textPrimary,
                decoration: TextDecoration.underline,
                decorationColor: AppTheme.textMuted,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color, blurRadius: size * 0.35)],
        ),
      ),
    );
  }
}
