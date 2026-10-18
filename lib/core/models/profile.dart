class Profile {
  const Profile({
    required this.nickname,
    this.avatarUrl,
  });

  final String nickname;
  final String? avatarUrl;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final avatar = (json['avatar_url'] ?? '').toString().trim();
    return Profile(
      nickname: (json['nickname'] ?? '').toString().trim(),
      avatarUrl: avatar.isEmpty ? null : avatar,
    );
  }
}

class ServiceKeys {
  const ServiceKeys({
    this.spotifyId = '',
    this.spotifySecret = '',
    this.soundcloudId = '',
    this.yandexToken = '',
    this.vkMusicToken = '',
  });

  final String spotifyId;
  final String spotifySecret;
  final String soundcloudId;
  final String yandexToken;
  final String vkMusicToken;

  factory ServiceKeys.fromJson(Map<String, dynamic> json) {
    return ServiceKeys(
      spotifyId: (json['spotify_id'] ?? '').toString(),
      spotifySecret: (json['spotify_secret'] ?? '').toString(),
      soundcloudId: (json['soundcloud_id'] ?? '').toString(),
      yandexToken: (json['yandex_token'] ?? '').toString(),
      vkMusicToken: (json['vkmusic_token'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'spotify_id': spotifyId,
      'spotify_secret': spotifySecret,
      'soundcloud_id': soundcloudId,
      'yandex_token': yandexToken,
      'vkmusic_token': vkMusicToken,
    };
  }
}
