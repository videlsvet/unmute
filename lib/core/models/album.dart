class AlbumSummary {
  const AlbumSummary({
    required this.albumTitle,
    required this.source,
    this.albumId,
    this.image,
    this.albumYear,
  });

  final String albumTitle;
  final String source;
  final String? albumId;
  final String? image;
  final int? albumYear;
}

class AlbumDetails {
  const AlbumDetails({
    required this.source,
    required this.title,
    required this.tracks,
    this.albumId,
    this.image,
    this.year,
  });

  final String source;
  final String title;
  final String? albumId;
  final String? image;
  final int? year;
  final List<dynamic> tracks;
}