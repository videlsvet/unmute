class PlaylistSummary {
  const PlaylistSummary({
    required this.playlistId,
    required this.title,
    required this.source,
    required this.link,
    required this.owner,
    required this.externalId,
    required this.trackCount,
  });

  final String playlistId;
  final String title;
  final String source;
  final String link;
  final String owner;
  final String externalId;
  final int trackCount;

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      playlistId: (json['playlist_id'] ?? '').toString(),
      title: (json['title'] ?? 'Без названия').toString(),
      source: (json['source'] ?? '').toString(),
      link: (json['link'] ?? '').toString(),
      owner: (json['owner'] ?? '').toString(),
      externalId: (json['external_id'] ?? '').toString(),
      trackCount: int.tryParse('${json['track_count']}') ?? 0,
    );
  }
}

class PlaylistTrackItem {
  const PlaylistTrackItem({
    required this.index,
    required this.title,
    required this.artist,
    required this.image,
    required this.preview,
    required this.source,
    required this.externalId,
    required this.albumId,
    required this.albumTitle,
    required this.albumYear,
    required this.artistId,
    required this.ownerId,
    required this.audioId,
    required this.accessKey,
  });

  final int index;
  final String title;
  final String artist;
  final String image;
  final String preview;
  final String source;
  final String externalId;
  final String albumId;
  final String albumTitle;
  final int? albumYear;
  final String artistId;
  final String ownerId;
  final String audioId;
  final String accessKey;

  factory PlaylistTrackItem.fromJson(Map<String, dynamic> json) {
    return PlaylistTrackItem(
      index: int.tryParse('${json['index']}') ?? 0,
      title: (json['title'] ?? 'Без названия').toString(),
      artist: (json['artist'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      preview: (json['preview'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      externalId: (json['external_id'] ?? json['externalId'] ?? '').toString(),
      albumId: (json['album_id'] ?? '').toString(),
      albumTitle: (json['album_title'] ?? '').toString(),
      albumYear: int.tryParse('${json['album_year']}'),
      artistId: (json['artist_id'] ?? '').toString(),
      ownerId: (json['owner_id'] ?? '').toString(),
      audioId: (json['audio_id'] ?? '').toString(),
      accessKey: (json['access_key'] ?? '').toString(),
    );
  }
}

class ImportProgress {
  const ImportProgress({
    required this.status,
    required this.done,
    required this.total,
    required this.current,
  });

  final String status;
  final int done;
  final int total;
  final String current;

  bool get isDone => status == 'done';
  bool get isRunning => status == 'running';

  factory ImportProgress.fromJson(Map<String, dynamic> json) {
    return ImportProgress(
      status: (json['status'] ?? 'none').toString(),
      done: int.tryParse('${json['done']}') ?? 0,
      total: int.tryParse('${json['total']}') ?? 0,
      current: (json['current'] ?? '').toString(),
    );
  }
}

class FavoriteImportResult {
  const FavoriteImportResult({
    required this.done,
    required this.nextOffset,
  });

  final bool done;
  final int nextOffset;

  factory FavoriteImportResult.fromJson(Map<String, dynamic> json) {
    final nextOffsetRaw = json['next_offset'];
    return FavoriteImportResult(
      done: json['done'] == true,
      nextOffset: nextOffsetRaw is int
          ? nextOffsetRaw
          : int.tryParse('$nextOffsetRaw') ?? 0,
    );
  }
}
