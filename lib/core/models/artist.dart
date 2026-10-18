class ArtistSummary {
  const ArtistSummary({
    required this.artistName,
    required this.source,
    this.artistId,
    this.image,
  });

  final String artistName;
  final String source;
  final String? artistId;
  final String? image;

  factory ArtistSummary.fromJson(Map<String, dynamic> json) {
    return ArtistSummary(
      artistId: _nullIfBlank(json['artist_id']?.toString()),
      artistName: (json['artist_name'] ?? 'Без имени').toString(),
      source: (json['source'] ?? '').toString(),
      image: _normalizeUrl(json['image']?.toString()),
    );
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

class ArtistDetails {
  const ArtistDetails({
    required this.source,
    required this.name,
    required this.tracks,
    this.artistId,
    this.image,
  });

  final String source;
  final String name;
  final String? artistId;
  final String? image;
  final List<dynamic> tracks;
}