class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.image,
    required this.preview,
    required this.source,
    this.externalId,
    this.artistId,
    this.albumId,
    this.albumTitle,
    this.albumYear,
    this.ownerId,
    this.audioId,
    this.accessKey,
    this.error,
  });

  final String id;
  final String title;
  final String artist;
  final String? image;
  final String? preview;
  final String source;

  final String? externalId;
  final String? artistId;
  final String? albumId;
  final String? albumTitle;
  final int? albumYear;
  final String? ownerId;
  final int? audioId;
  final String? accessKey;
  final String? error;

  bool get hasPlayableUrl => (preview ?? '').trim().isNotEmpty;

  factory Track.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      return int.tryParse(value.toString());
    }

    final source = (json['source'] ?? json['service'] ?? '').toString().trim();
    final rawId = (json['id'] ?? '').toString().trim();
    final externalId =
        (json['externalId'] ?? json['external_id'] ?? '').toString().trim();

    final title = (json['title'] ?? 'Без названия').toString().trim();
    final artist = (json['artist'] ?? '').toString().trim();

    final stableId = rawId.isNotEmpty
        ? rawId
        : externalId.isNotEmpty
            ? externalId
            : '${source.isEmpty ? 'track' : source}:$title:$artist';

    return Track(
      id: stableId,
      title: title.isEmpty ? 'Без названия' : title,
      artist: artist,
      image: _normalizeUrl(json['image']?.toString()),
      preview: _normalizeUrl(json['preview']?.toString()),
      source: source,
      externalId: externalId.isEmpty ? null : externalId,
      artistId: _nullIfBlank(json['artist_id']?.toString()),
      albumId: _nullIfBlank(json['album_id']?.toString()),
      albumTitle: _nullIfBlank(json['album_title']?.toString()),
      albumYear: parseInt(json['album_year']),
      ownerId: _nullIfBlank(json['owner_id']?.toString()),
      audioId: parseInt(json['audio_id']),
      accessKey: _nullIfBlank(json['access_key']?.toString()),
      error: _nullIfBlank(json['error']?.toString()),
    );
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? image,
    String? preview,
    String? source,
    String? externalId,
    String? artistId,
    String? albumId,
    String? albumTitle,
    int? albumYear,
    String? ownerId,
    int? audioId,
    String? accessKey,
    String? error,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      image: image ?? this.image,
      preview: preview ?? this.preview,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      albumTitle: albumTitle ?? this.albumTitle,
      albumYear: albumYear ?? this.albumYear,
      ownerId: ownerId ?? this.ownerId,
      audioId: audioId ?? this.audioId,
      accessKey: accessKey ?? this.accessKey,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toBackendJson() {
    return {
      'id': externalId ?? id,
      'title': title,
      'artist': artist,
      'image': image ?? '',
      'preview': preview ?? '',
      'source': source,
      'artist_id': artistId ?? '',
      'album_id': albumId ?? '',
      'album_title': albumTitle ?? '',
      'album_year': albumYear,
      'owner_id': ownerId ?? '',
      'audio_id': audioId?.toString() ?? '',
      'access_key': accessKey ?? '',
    };
  }

  static String? _nullIfBlank(String? value) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  static String? _normalizeUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('http://')) return 'https://${v.substring(7)}';
    return v;
  }
}
