import base64
import json
import os
import re
import time
import xml.etree.ElementTree as ET
from collections import OrderedDict
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import quote, urljoin

import requests
from requests.adapters import HTTPAdapter

try:
    # urllib3 is a transitive dependency of requests
    from urllib3.util.retry import Retry
except Exception:  # pragma: no cover
    Retry = None


# ===== CORS =====

def _cors_headers() -> Dict[str, str]:
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
    }


def _response(status: int, body: Any) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": _cors_headers(),
        "body": json.dumps(body, ensure_ascii=False),
    }


@dataclass(frozen=True)
class _Config:
    api_base_url: str
    proxy_enabled: bool
    proxy_url: Optional[str]
    http_timeout_s: float
    http_retries: int
    http_backoff_s: float
    cache_max_items: int


def _env_bool(name: str, default: bool = False) -> bool:
    raw = (os.getenv(name, "") or "").strip().lower()
    if raw == "":
        return default
    return raw in ("1", "true", "yes", "y", "on", "enabled")


def _load_config() -> _Config:
    api_base_url = (os.getenv("API_BASE_URL", "") or "").strip()
    if not api_base_url:
        # keep backward compatibility with existing hardcoded value
        api_base_url = "https://d5dn6r204cm4tpgfe0ms.kf69zffa.apigw.yandexcloud.net/search"

    proxy_url = (os.getenv("PROXY_URL", "") or "").strip() or None
    proxy_enabled = _env_bool("PROXY_ENABLED", default=False) and bool(proxy_url)

    def _env_float(name: str, default: float) -> float:
        try:
            return float((os.getenv(name, "") or "").strip() or default)
        except Exception:
            return default

    def _env_int(name: str, default: int) -> int:
        try:
            return int((os.getenv(name, "") or "").strip() or default)
        except Exception:
            return default

    return _Config(
        api_base_url=api_base_url,
        proxy_enabled=proxy_enabled,
        proxy_url=proxy_url,
        http_timeout_s=_env_float("HTTP_TIMEOUT_S", 20.0),
        http_retries=_env_int("HTTP_RETRIES", 2),
        http_backoff_s=_env_float("HTTP_BACKOFF_S", 0.4),
        cache_max_items=_env_int("CACHE_MAX_ITEMS", 2048),
    )


_CFG = _load_config()


class _TtlLruCache:
    def __init__(self, max_items: int):
        self._max = max(16, int(max_items or 0))
        self._data: "OrderedDict[str, Tuple[float, Any]]" = OrderedDict()

    def get(self, key: str) -> Optional[Any]:
        item = self._data.get(key)
        if not item:
            return None
        exp, val = item
        now = time.time()
        if exp < now:
            self._data.pop(key, None)
            return None
        # touch
        self._data.move_to_end(key, last=True)
        return val

    def set(self, key: str, val: Any, ttl_s: int) -> None:
        exp = time.time() + max(1, int(ttl_s or 1))
        self._data[key] = (exp, val)
        self._data.move_to_end(key, last=True)
        while len(self._data) > self._max:
            self._data.popitem(last=False)


_CACHE = _TtlLruCache(max_items=_CFG.cache_max_items)


def cache_get(key: str) -> Optional[Any]:
    return _CACHE.get(key)


def cache_set(key: str, data: Any, ttl: int = 60) -> None:
    _CACHE.set(key, data, ttl_s=ttl)


def _proxies_if_enabled() -> Optional[Dict[str, str]]:
    if not _CFG.proxy_enabled or not _CFG.proxy_url:
        return None
    return {"http": _CFG.proxy_url, "https": _CFG.proxy_url}


def _build_http_session() -> requests.Session:
    s = requests.Session()
    if Retry is None:
        return s

    retries = Retry(
        total=max(0, int(_CFG.http_retries)),
        connect=max(0, int(_CFG.http_retries)),
        read=max(0, int(_CFG.http_retries)),
        status=max(0, int(_CFG.http_retries)),
        backoff_factor=max(0.0, float(_CFG.http_backoff_s)),
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=frozenset(["GET", "POST"]),
        raise_on_status=False,
        respect_retry_after_header=True,
    )
    adapter = HTTPAdapter(max_retries=retries, pool_connections=16, pool_maxsize=32)
    s.mount("http://", adapter)
    s.mount("https://", adapter)
    return s


_HTTP = _build_http_session()

# ===== STREAM PROXY (РґР»СЏ SoundCloud preview) =====

def _cors_headers_stream(extra: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    h = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, Range",
        "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges",
    }
    if extra:
        h.update(extra)
    return h

def _stream_response(status: int, body: bytes, headers: Dict[str, str]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": headers,
        "isBase64Encoded": True,
        "body": base64.b64encode(body).decode("ascii"),
    }

def _strict_quote_url(url: str) -> str:
    # urllib keeps "~" unescaped by design, but CloudFront signatures use it
    # heavily. Encoding it makes the proxied URL safer across players/gateways.
    return quote(url, safe="").replace("~", "%7E")


def _rewrite_uri_attributes(line: str, base_url: str) -> str:
    def repl(match: "re.Match[str]") -> str:
        uri = match.group(1)
        absolute = urljoin(base_url, uri)
        return f'URI="{make_stream_proxy_url(absolute)}"'

    return re.sub(r'URI="([^"]+)"', repl, line)


def _rewrite_m3u8_playlist(text: str, base_url: str) -> str:
    out = []
    for line in text.splitlines():
        line = line.strip()

        # РїРµСЂРµРїРёСЃС‹РІР°РµРј EXT-X-MAP:URI="https://...."
        if not line:
            out.append(line)
            continue

        if line.startswith("#") and 'URI="' in line:
            out.append(_rewrite_uri_attributes(line, base_url))
            continue

        if line.startswith("#"):
            out.append(line)
            continue

        out.append(make_stream_proxy_url(urljoin(base_url, line)))

        # URL СЃС‚СЂРѕРєР° (СЃРµРіРјРµРЅС‚)
    return "\n".join(out) + "\n"


def _validate_http_url(u: str) -> Optional[str]:
    u = (u or "").strip()
    if not u:
        return None
    if u.startswith("http://") or u.startswith("https://"):
        return u
    return None


def proxy_image(url: str, raw_mode: bool = False) -> Dict[str, Any]:
    url = _validate_http_url(url) or ""
    if not url:
        return _response(400, {"error": "Missing or bad u"})

    try:
        r = _HTTP.get(
            url,
            headers={"User-Agent": "Mozilla/5.0", "Accept": "image/*,*/*;q=0.8"},
            timeout=_CFG.http_timeout_s,
            proxies=_proxies_if_enabled(),
            allow_redirects=True,
        )

        content_type = r.headers.get("Content-Type", "image/jpeg")
        out_headers = {
            "Content-Type": content_type,
            "Cache-Control": "public, max-age=86400",
        }

        # NOTE:
        # Most API-gateway/Lambda-style integrations require base64 transport for binary bodies.
        # `raw_mode` is kept for client-side intent ("I want image bytes"), while transport remains base64.
        body_b64 = base64.b64encode(r.content).decode("ascii")
        return {
            "statusCode": r.status_code,
            "headers": _cors_headers_stream(out_headers),
            "isBase64Encoded": True,
            "body": body_b64,
        }

    except Exception as e:
        return _response(502, {"error": f"img proxy: {type(e).__name__}: {e}"})


def proxy_stream(url: str, event: Dict[str, Any]) -> Dict[str, Any]:
    url = _validate_http_url(url) or ""
    if not url:
        return _response(400, {"error": "Missing or bad u"})

    req_headers = event.get("headers") or {}
    range_h = req_headers.get("Range") or req_headers.get("range")

    headers = {
        "User-Agent": "Mozilla/5.0",
        "Accept": "*/*",
    }
    if range_h:
        headers["Range"] = range_h

    try:
        r = _HTTP.get(
            url,
            headers=headers,
            stream=True,
            timeout=_CFG.http_timeout_s,
            proxies=_proxies_if_enabled(),
            allow_redirects=True,
        )

        # ---- РµСЃР»Рё СЌС‚Рѕ M3U8: РїРµСЂРµРїРёСЃС‹РІР°РµРј СЃСЃС‹Р»РєРё Рё РѕС‚РґР°С‘Рј С‚РµРєСЃС‚РѕРј, РќР• base64
        ct = (r.headers.get("Content-Type") or "").lower()
        if ".m3u8" in url or "application/vnd.apple.mpegurl" in ct or "application/x-mpegurl" in ct:
            text = r.text
            rewritten = _rewrite_m3u8_playlist(text, url)
            return {
                "statusCode": r.status_code,
                "headers": _cors_headers_stream({
                    "Content-Type": "application/vnd.apple.mpegurl",
                    "Cache-Control": "no-store",
                }),
                "body": rewritten,
                "isBase64Encoded": False,
            }

        # ---- РёРЅР°С‡Рµ СЌС‚Рѕ Р±РёРЅР°СЂСЊ (init.mp4 / .m4s / etc)
        content = r.content

        out_headers = {
            "Content-Type": r.headers.get("Content-Type", "application/octet-stream"),
            "Accept-Ranges": r.headers.get("Accept-Ranges", "bytes"),
            "Cache-Control": "no-store",
        }
        if r.headers.get("Content-Range"):
            out_headers["Content-Range"] = r.headers["Content-Range"]
        if r.headers.get("Content-Length"):
            out_headers["Content-Length"] = r.headers["Content-Length"]

        return _stream_response(r.status_code, content, _cors_headers_stream(out_headers))

    except Exception as e:
        return _response(502, {"error": f"stream proxy: {type(e).__name__}: {e}"})





# ===== Spotify Token =====
_spotify_token: Dict[str, Any] = {"value": None, "exp": 0}


def _get_spotify_token() -> Optional[str]:
    now = time.time()
    if _spotify_token["value"] and now < _spotify_token["exp"]:
        return _spotify_token["value"]

    cid = os.getenv("SPOTIFY_CLIENT_ID")
    sec = os.getenv("SPOTIFY_CLIENT_SECRET")
    if not cid or not sec:
        print("Spotify token error: missing SPOTIFY_CLIENT_ID/SECRET")
        return None

    try:
        r = _HTTP.post(
            "https://accounts.spotify.com/api/token",
            data={"grant_type": "client_credentials"},
            auth=(cid, sec),
            headers={
                "Accept": "application/json",
                "User-Agent": "WaveServer/1.0",
            },
            timeout=_CFG.http_timeout_s,
            proxies=_proxies_if_enabled(),
        )

        if r.status_code != 200:
            print("Spotify token HTTP", r.status_code, r.text[:800])
            return None

        data = r.json()
        token = data.get("access_token")
        expires_in = int(data.get("expires_in", 3600))

        if token:
            _spotify_token["value"] = token
            _spotify_token["exp"] = now + max(60, expires_in - 60)
            return token

        print("Spotify token error: no access_token in response", data)
        return None

    except Exception as e:
        print("Spotify token exception:", type(e).__name__, str(e))
        return None


# ======================================================================================
# ===== Yandex Music (Search + Artist + Album) =========================================
# ======================================================================================

def _ym_cover_to_image(cover_uri: Optional[str]) -> Optional[str]:
    if not cover_uri:
        return None
    if cover_uri.startswith("http"):
        return cover_uri
    if cover_uri.startswith("//"):
        return f"https:{cover_uri}"
    return f"https://{cover_uri.replace('%%', '400x400')}"


def _norm_yandexmusic(item: Dict[str, Any]) -> Dict[str, Any]:
    """
    РќРѕСЂРјР°Р»РёР·СѓРµРј С‚СЂРµРє РЇ.РњСѓР·С‹РєРё Рё Р”РћР‘РђР’Р›РЇР•Рњ РґР°РЅРЅС‹Рµ РґР»СЏ СЌРєСЂР°РЅРѕРІ:
    - artist_id (РїРµСЂРІС‹Р№ Р°СЂС‚РёСЃС‚)
    - album_id / album_title / album_year (РїРµСЂРІС‹Р№ Р°Р»СЊР±РѕРј)
    """
    artists_arr = item.get("artists", []) or []
    albums_arr = item.get("albums", []) or []

    artists = ", ".join(a.get("name") for a in artists_arr if a.get("name"))
    artist_id = artists_arr[0].get("id") if artists_arr else None

    album0 = albums_arr[0] if albums_arr else None
    album_id = album0.get("id") if album0 else None
    album_title = album0.get("title") if album0 else None
    album_year = album0.get("year") if album0 else None
    album_cover = album0.get("coverUri") if album0 else None

    # РІ РїСЂРёРѕСЂРёС‚РµС‚Рµ РѕР±Р»РѕР¶РєР° Р°Р»СЊР±РѕРјР°, РїРѕС‚РѕРј coverUri С‚СЂРµРєР°
    cover_uri = album_cover or item.get("coverUri")
    image = _ym_cover_to_image(cover_uri)

    return {
        "title": item.get("title"),
        "artist": artists,
        "artist_id": str(artist_id) if artist_id is not None else None,
        "album_id": str(album_id) if album_id is not None else None,
        "album_title": album_title,
        "album_year": album_year,
        "image": image,
        "preview": None,
        "duration": item.get("durationMs", 0) // 1000,
        "id": str(item.get("id")) if item.get("id") is not None else None,
        "source": "yandex",
    }


def _ym_request(url: str, token: str, params=None, use_proxy: bool = False):
    proxies = _proxies_if_enabled() if use_proxy else None
    r = _HTTP.get(
        url,
        headers={
            "Authorization": f"OAuth {token}",
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json",
        },
        params=params or {},
        timeout=_CFG.http_timeout_s,
        proxies=proxies,
        allow_redirects=True,
    )
    if r.status_code != 200:
        print("YM HTTP", r.status_code, url, r.text[:600])
    r.raise_for_status()
    return r.json()



def _get_yandex_stream(track_id: int, token: str) -> Optional[str]:
    try:
        track_id = int(track_id)

        info = _ym_request(
            f"https://api.music.yandex.net/tracks/{track_id}/download-info",
            token=token,
            use_proxy=False
        )

        infos = info.get("result", [])
        if not infos:
            return None

# рџ”Ґ РІС‹Р±РёСЂР°РµРј РёРјРµРЅРЅРѕ mp3, Р° РЅРµ РїРµСЂРІС‹Р№ РїРѕРїР°РІС€РёР№СЃСЏ
        pick = None
        for it in infos:
            if (it.get("codec") or "").lower() == "mp3":
                pick = it
                break

# fallback вЂ” РµСЃР»Рё mp3 РІРґСЂСѓРі РЅРµС‚
        pick = pick or infos[0]

        download_info_url = pick.get("downloadInfoUrl")
        if not download_info_url:
            return None


        # normalize URL
        if download_info_url.startswith("//"):
            download_info_url = "https:" + download_info_url
        elif download_info_url.startswith("/"):
            download_info_url = "https://api.music.yandex.net" + download_info_url

        # downloadInfoUrl РѕР±С‹С‡РЅРѕ РЅРµ С‚СЂРµР±СѓРµС‚ OAuth
        xml_resp = requests.get(
            download_info_url,
            timeout=_CFG.http_timeout_s,
            headers={"User-Agent": "Mozilla/5.0", "Accept": "*/*"},
            allow_redirects=True,
        )
        xml_resp.raise_for_status()

        root = ET.fromstring(xml_resp.text)
        host = root.findtext("host")
        path = root.findtext("path")
        ts = root.findtext("ts")
        s = root.findtext("s")

        if not host or not path or not ts or not s:
            return None

        path = path.lstrip("/")
        return f"https://{host}/get-mp3/{s}/{ts}/{path}"

    except Exception as e:
        print("Yandex stream error:", e)
        return None


def search_yandexmusic(q: str, page: int = 0, page_size: int = 50) -> List[Dict[str, Any]]:
    q_norm = " ".join((q or "").strip().split())
    page = max(0, int(page))
    page_size = max(1, min(int(page_size), 100))
    cache_key = f"yandexmusic:search:{q_norm}:{page}:{page_size}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    token = os.getenv("YANDEXMUSIC_TOKEN")
    if not token:
        return [{"error": "yandexmusic: missing YANDEXMUSIC_TOKEN"}]

    try:
        data = _ym_request(
            "https://api.music.yandex.net/search",
            token=token,
            params={"text": q_norm, "type": "track", "page": page, "pageSize": page_size},
            use_proxy=False
        )

        tracks = data.get("result", {}).get("tracks", {}).get("results", [])
        results = []
        for t in tracks:
            item = _norm_yandexmusic(t)
            if item.get("id"):
               item["preview"] = _get_yandex_stream(item["id"], token)
            results.append(item)


        cache_set(cache_key, results, ttl=60)
        return results

    except Exception as e:
        return [{"error": f"yandexmusic: {e}"}]


def yandex_album_with_tracks(album_id: str) -> Dict[str, Any]:
    """
    Р’РѕР·РІСЂР°С‰Р°РµС‚:
    {
      "type": "album",
      "source": "yandex",
      "album": {...},
      "tracks": [...]
    }
    """
    cache_key = f"yandexmusic:album:{album_id}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    token = os.getenv("YANDEXMUSIC_TOKEN")
    if not token:
        return {"error": "yandexmusic: missing YANDEXMUSIC_TOKEN"}

    try:
        album_id_int = int(album_id)

        data = _ym_request(
            f"https://api.music.yandex.net/albums/{album_id_int}/with-tracks",
            token=token,
            params={},
            use_proxy=False
        )

        result = data.get("result") or {}

        # album meta
        album_meta = result.get("album") or result.get("result") or result.get("album") or {}
        # РёРЅРѕРіРґР° album_meta РјРѕР¶РµС‚ Р±С‹С‚СЊ РїСЂСЏРјРѕ РІ result (РІ Р·Р°РІРёСЃРёРјРѕСЃС‚Рё РѕС‚ РІРµСЂСЃРёРё)
        if not album_meta and isinstance(result, dict):
            # try best-effort:
            album_meta = result.get("album") or result

        album_title = album_meta.get("title") or album_meta.get("name")
        cover_uri = album_meta.get("coverUri") or album_meta.get("cover_uri")
        image = _ym_cover_to_image(cover_uri)
        year = album_meta.get("year")

        # tracks: РѕР±С‹С‡РЅРѕ volumes: [[track, track], [track...]]
        volumes = result.get("volumes") or []
        tracks_out: List[Dict[str, Any]] = []

        for disc in volumes:
            if not isinstance(disc, list):
                continue
            for t in disc:
                track = t.get("track") if isinstance(t, dict) else None
                track = track or (t if isinstance(t, dict) else None)
                if not isinstance(track, dict):
                    continue
                item = _norm_yandexmusic(track)
                if item.get("id"):
                    item["preview"] = _get_yandex_stream(item["id"], token)
                # РµСЃР»Рё РІРґСЂСѓРі Р°Р»СЊР±РѕРјРЅС‹С… РїРѕР»РµР№ РЅРµС‚ РІ С‚СЂРµРєРµ вЂ” РїРѕРґСЃС‚Р°РІРёРј
                item["album_id"] = item.get("album_id") or str(album_id_int)
                item["album_title"] = item.get("album_title") or album_title
                item["album_year"] = item.get("album_year") or year
                if not item.get("image") and image:
                    item["image"] = image
                tracks_out.append(item)

        payload = {
            "type": "album",
            "source": "yandex",
            "album": {
                "album_id": str(album_id_int),
                "album_title": album_title,
                "album_year": year,
                "image": image,
            },
            "tracks": tracks_out
        }

        cache_set(cache_key, payload, ttl=60)
        return payload

    except Exception as e:
        return {"error": f"yandexmusic album: {type(e).__name__}: {e}"}


def yandex_artist_top_tracks(artist_id: str, fallback_name: Optional[str] = None) -> Dict[str, Any]:
    """
    MVP: РѕС‚РґР°С‘Рј С‚РѕРї С‚СЂРµРєРё Р°СЂС‚РёСЃС‚Р°.
    РЎС…РµРјР°:
    - /artists/{id}/brief-info (РґР»СЏ РјРµС‚С‹)
    - /artists/{id}/track-ids-by-rating -> Р±РµСЂС‘Рј id С‚СЂРµРєРѕРІ
    - /tracks?trackIds=... -> РїРѕР»СѓС‡Р°РµРј С‚СЂРµРєРё
    Р•СЃР»Рё С‡С‚Рѕ-С‚Рѕ РЅРµ РІС‹С€Р»Рѕ вЂ” fallback РЅР° search РїРѕ РёРјРµРЅРё.
    """
    cache_key = f"yandexmusic:artist:{artist_id}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    token = os.getenv("YANDEXMUSIC_TOKEN")
    if not token:
        return {"error": "yandexmusic: missing YANDEXMUSIC_TOKEN"}

    try:
        artist_id_int = int(artist_id)

        # meta (best-effort)
        artist_meta: Dict[str, Any] = {}
        try:
            meta_json = _ym_request(
                f"https://api.music.yandex.net/artists/{artist_id_int}/brief-info",
                token=token,
                params={},
                use_proxy=False
            )
            artist_meta = meta_json.get("result") or {}
        except Exception as e:
            print("Yandex artist meta error:", e)

        # track ids
        ids_json = _ym_request(
            f"https://api.music.yandex.net/artists/{artist_id_int}/track-ids-by-rating",
            token=token,
            params={"pageSize": 25, "page": 0},
            use_proxy=False
        )
        ids_result = ids_json.get("result") or {}
        track_ids = ids_result.get("tracks") or ids_result.get("trackIds") or ids_result.get("ids") or []
        track_ids = [int(x) for x in track_ids if str(x).isdigit()]

        tracks_raw: List[Dict[str, Any]] = []
        if track_ids:
            # РїРѕРїС‹С‚РєР° РїРѕР»СѓС‡РёС‚СЊ РїР°С‡РєРѕР№
            try:
                tracks_json = _ym_request(
                    "https://api.music.yandex.net/tracks",
                    token=token,
                    params={"trackIds": ",".join(map(str, track_ids))},
                    use_proxy=False
                )
                tracks_raw = tracks_json.get("result") or []
            except Exception as e:
                print("Yandex tracks batch error:", e)
                tracks_raw = []

        tracks_out: List[Dict[str, Any]] = []
        for t in tracks_raw:
            if not isinstance(t, dict):
                continue
            item = _norm_yandexmusic(t)
            if item.get("id"):
                item["preview"] = _get_yandex_stream(item["id"], token)
            tracks_out.append(item)

        # fallback РµСЃР»Рё РїСѓСЃС‚Рѕ
        if not tracks_out and fallback_name:
            tracks_out = search_yandexmusic(fallback_name, page=0, page_size=50)  # СѓР¶Рµ РЅРѕСЂРјР°Р»РёР·РѕРІР°РЅРѕ + preview

        # artist meta normalize
        artist_name = None
        artist_cover = None
        try:
            artist_obj = artist_meta.get("artist") or artist_meta.get("result") or {}
            artist_name = artist_obj.get("name") or artist_meta.get("name") or fallback_name
            cover_uri = artist_obj.get("coverUri") or artist_obj.get("cover", {}).get("uri")
            artist_cover = _ym_cover_to_image(cover_uri)
        except Exception:
            artist_name = fallback_name

        payload = {
            "type": "artist",
            "source": "yandex",
            "artist": {
                "artist_id": str(artist_id_int),
                "artist_name": artist_name or fallback_name,
                "image": artist_cover,
            },
            "tracks": tracks_out
        }

        cache_set(cache_key, payload, ttl=60)
        return payload

    except Exception as e:
        # fallback РЅР° РїРѕРёСЃРє РїРѕ РёРјРµРЅРё
        if fallback_name:
            return {
                "type": "artist",
                "source": "yandex",
                "artist": {
                    "artist_id": str(artist_id),
                    "artist_name": fallback_name,
                    "image": None,
                },
                "tracks": search_yandexmusic(fallback_name, page=0, page_size=50),
                "warning": f"fallback_to_search: {type(e).__name__}: {e}",
            }
        return {"error": f"yandexmusic artist: {type(e).__name__}: {e}"}


def yandex_similar_tracks(track_id: str) -> List[Dict[str, Any]]:
    track_id = (track_id or "").strip()
    if not track_id:
        return []
    cache_key = f"yandexmusic:similar:{track_id}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    token = os.getenv("YANDEXMUSIC_TOKEN")
    if not token:
        return []

    try:
        data = _ym_request(
            f"https://api.music.yandex.net/tracks/{track_id}/similar",
            token=token,
            use_proxy=False
        )
        tracks = data.get("result", {}).get("similarTracks", [])
        results = []
        for t in tracks:
            item = _norm_yandexmusic(t)
            if item.get("id"):
                item["preview"] = _get_yandex_stream(item["id"], token)
            results.append(item)
        cache_set(cache_key, results, ttl=180)
        return results
    except Exception as e:
        print("yandex_similar_tracks error:", e)
        return []


# ======================================================================================
# ===== Spotify (РєР°Рє Р±С‹Р»Рѕ) ==============================================================
# ======================================================================================

def _norm_spotify(item: Dict[str, Any]) -> Dict[str, Any]:
    artists = ", ".join(a.get("name") for a in item.get("artists", []))
    image = None
    imgs = item.get("album", {}).get("images", [])
    if imgs:
        image = imgs[0].get("url")
    return {
        "title": item.get("name"),
        "artist": artists,
        "image": image,
        "preview": item.get("preview_url"),
        "spotify_id": item.get("id"),
        "spotify_url": (item.get("external_urls") or {}).get("spotify"),
        "duration": item.get("duration_ms", 0) // 1000,
        "source": "spotify",
    }


def search_spotify(q: str, offset: int = 0, limit: int = 50) -> List[Dict[str, Any]]:
    q_norm = " ".join((q or "").strip().split())
    offset = max(0, int(offset))
    limit = max(1, min(int(limit), 50))
    cache_key = f"spotify:{q_norm.lower()}:{offset}:{limit}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    token = _get_spotify_token()
    if not token:
        return [{"error": "spotify: missing token"}]

    try:
        r = _HTTP.get(
            "https://api.spotify.com/v1/search",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "User-Agent": "WaveServer/1.0",
            },
            params={"q": q_norm, "type": "track", "limit": limit, "offset": offset},
            timeout=_CFG.http_timeout_s,
            proxies=_proxies_if_enabled(),
        )

        if r.status_code != 200:
            return [{
                "error": f"spotify: HTTP {r.status_code}",
                "details": r.text[:800]
            }]

        items = r.json().get("tracks", {}).get("items", [])
        results = [_norm_spotify(x) for x in items]
        cache_set(cache_key, results, ttl=60)
        return results

    except Exception as e:
        return [{"error": f"spotify: {type(e).__name__}: {e}"}]


# ======================================================================================
# ===== SoundCloud (РєР°Рє Р±С‹Р»Рѕ) ===========================================================
# ======================================================================================

def _resolve_soundcloud_stream(api_url: str, client_id: str) -> Optional[str]:
    try:
        proxies = _proxies_if_enabled()
        r = _HTTP.get(
            api_url,
            params={"client_id": client_id},
            timeout=_CFG.http_timeout_s,
            proxies=proxies,
            headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"},
        )
        r.raise_for_status()
        return r.json().get("url")
    except Exception as e:
        print("SoundCloud resolve error:", e)
        return None

def make_stream_proxy_url(real_url: str) -> str:
    # РѕС‚РґР°С‘Рј РєР»РёРµРЅС‚Сѓ СЃСЃС‹Р»РєСѓ РЅР° РЅР°С€ backend, Р° РЅРµ РїСЂСЏРјРѕР№ playback/cf-media
    return f"{_CFG.api_base_url}?type=stream&u={_strict_quote_url(real_url)}"
    
def make_img_proxy_url(real_url: str) -> str:
    return f"{_CFG.api_base_url}?type=img&u={requests.utils.quote(real_url, safe='')}"


def make_img_raw_proxy_url(real_url: str) -> str:
    return f"{_CFG.api_base_url}?type=img_raw&u={requests.utils.quote(real_url, safe='')}"



def _norm_soundcloud(item: Dict[str, Any], client_id: str) -> Dict[str, Any]:
    stream_url = None
    transcodings = item.get("media", {}).get("transcodings", [])
    for t in transcodings:
        if "progressive" in t.get("format", {}).get("protocol", ""):
            stream_url = _resolve_soundcloud_stream(t.get("url"), client_id)
            print("STREAM_URL =", stream_url)
            if stream_url:
                break
    if not stream_url:
        for t in transcodings:
            if "hls" in t.get("format", {}).get("protocol", ""):
                stream_url = _resolve_soundcloud_stream(t.get("url"), client_id)
                print("STREAM_URL =", stream_url)
                if stream_url:
                    break

    image = item.get("artwork_url") or item.get("user", {}).get("avatar_url")
    if image:
        image = image.replace("http://", "https://")
        image = image.replace("-large", "-t500x500").replace("-t300x300", "-t500x500")

    return {
        "title": item.get("title"),
        "artist": item.get("user", {}).get("username"),
        "image": make_img_proxy_url(image) if image else None,
        "preview": make_stream_proxy_url(stream_url) if stream_url else None,
        "duration": int(item.get("duration", 0)) // 1000,
        "source": "soundcloud",
    }


def search_soundcloud(
    q: str,
    offset: int = 0,
    limit: int = 50,
    bypass_cache: bool = False,
) -> List[Dict[str, Any]]:
    q_norm = " ".join((q or "").strip().split())
    offset = max(0, int(offset))
    limit = max(1, min(int(limit), 80))
    cache_key = f"soundcloud:{q_norm}:{offset}:{limit}"
    cached = cache_get(cache_key) if not bypass_cache else None
    if cached:
        return cached

    cid = os.getenv("SOUNDCLOUD_CLIENT_ID")
    if not cid:
        return [{"error": "soundcloud: missing client_id"}]

    proxies = _proxies_if_enabled()

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
        "Referer": "https://soundcloud.com/",
        "Origin": "https://soundcloud.com",
    }

    try:
        r = _HTTP.get(
            "https://api-v2.soundcloud.com/search/tracks",
            params={"q": q_norm, "client_id": cid, "limit": limit, "offset": offset},
            timeout=_CFG.http_timeout_s,
            proxies=proxies,
            headers=headers,
        )
        # РµСЃР»Рё 403 вЂ” РїРѕРєР°Р¶РµРј РєСѓСЃРѕРє С‚РµР»Р°, РёРЅРѕРіРґР° С‚Р°Рј РїСЂРёС‡РёРЅР°
        if r.status_code != 200:
            return [{
                "error": f"soundcloud: HTTP {r.status_code}",
                "details": r.text[:500]
            }]

        collection = r.json().get("collection", [])
        results = [_norm_soundcloud(x, cid) for x in collection]
        cache_set(cache_key, results, ttl=60)
        return results

    except Exception as e:
        return [{"error": f"soundcloud: {type(e).__name__}: {e}"}]



# ======================================================================================
# ===== VK Music (Search + Artist + Album-as-Playlist) =================================
# ======================================================================================

def _get_vk_token(token: Optional[str] = None) -> Optional[str]:
    if token and str(token).strip():
        return str(token).strip()
    for k in (
        "VKMusic_ACCESS_TOKEN",
        "VKMUSIC_ACCESS_TOKEN",
        "VK_ACCESS_TOKEN",
        "VK_MUSIC_ACCESS_TOKEN",
        "VKMUSIC_TOKEN",
        "VK_TOKEN",
    ):
        v = (os.getenv(k) or "").strip()
        if v:
            return v
    return None

def _vk_call(method: str, token: str, params: Dict[str, Any], use_proxy: bool = False) -> Dict[str, Any]:
    base = "https://api.vk.com/method/"
    p = dict(params)
    p["access_token"] = token
    p.setdefault("v", "5.131")

    headers = {
        "User-Agent": "VKAndroidApp/8.29-17342 (Android 11; SDK 30; arm64-v8a; Google Pixel 6; ru; 2400x1080)"
    }
    proxies = _proxies_if_enabled() if use_proxy else None

    r = _HTTP.get(
        base + method,
        params=p,
        timeout=_CFG.http_timeout_s,
        headers=headers,
        proxies=proxies,
        allow_redirects=True,
    )
    r.raise_for_status()

    data = r.json()
    if "error" in data:
        err = data["error"] or {}
        raise RuntimeError(f"VK API error {err.get('error_code')}: {err.get('error_msg')}")
    return data




def _vk_audio_key(owner_id: Any, audio_id: Any, access_key: Optional[str]) -> Optional[str]:
    if owner_id is None or audio_id is None:
        return None
    s = f"{owner_id}_{audio_id}"
    # access_key РІ VK Р±С‹РІР°РµС‚ РЅСѓР¶РµРЅ, РЅРѕ РЅРµ РІСЃРµРіРґР° РµСЃС‚СЊ
    if access_key:
        s = f"{s}_{access_key}"
    return s

def _vk_pick_image_from_album(album: Dict[str, Any]) -> Optional[str]:
    thumb = (album.get("thumb") or {})
    return thumb.get("photo_600") or thumb.get("photo_300") or thumb.get("photo_135")

def _norm_vkmusic(item: Dict[str, Any]) -> Dict[str, Any]:
    artist = item.get("artist")
    title = item.get("title")
    duration = item.get("duration")
    url = item.get("url")  # РјРѕР¶РµС‚ Р±С‹С‚СЊ None

    owner_id = item.get("owner_id")
    audio_id = item.get("id")
    access_key = item.get("access_key")

    image = None
    album_id = None
    album_title = None
    album_year = None

    alb = item.get("album")
    if isinstance(alb, dict):
        album_id = alb.get("id") or alb.get("playlist_id")
        album_title = alb.get("title") or alb.get("name")
        album_year = alb.get("year")

        image = _vk_pick_image_from_album(alb) or image

        # РёРЅРѕРіРґР° РІ album Р»РµР¶Р°С‚ owner_id/access_key РїР»РµР№Р»РёСЃС‚Р° вЂ” РќР• РїРµСЂРµС‚РёСЂР°РµРј track access_key,
        # РЅРѕ owner_id РјРѕР¶РЅРѕ СѓС‚РѕС‡РЅРёС‚СЊ РµСЃР»Рё Сѓ С‚СЂРµРєР° РµРіРѕ РЅРµС‚
        owner_id = owner_id if owner_id is not None else alb.get("owner_id") or owner_id
        # access_key С‚СЂРµРєР° РІР°Р¶РЅРµРµ, С‡РµРј access_key РїР»РµР№Р»РёСЃС‚Р°
        access_key = access_key or alb.get("access_key") or access_key

    return {
        "title": title,
        "artist": artist,
        "image": image,
        "preview": url,  # С‚СѓС‚ РјРѕР¶РµС‚ Р±С‹С‚СЊ None вЂ” РїРѕР·Р¶Рµ РѕР±РѕРіР°С‚РёРј С‡РµСЂРµР· getById
        "duration": int(duration or 0),
        "source": "vkmusic",

        # extras
        "owner_id": owner_id,
        "audio_id": audio_id,
        "access_key": access_key,

        # album extras (РµСЃР»Рё РµСЃС‚СЊ)
        "album_id": str(album_id) if album_id is not None else None,
        "album_title": album_title,
        "album_year": album_year,

        # universal id
        "id": _vk_audio_key(owner_id, audio_id, access_key),
    }

def _vk_enrich_previews_batch(tracks: List[Dict[str, Any]], token: str) -> None:
    """
    РћР±РѕРіР°С‰Р°РµС‚ tracks: РїСЂРѕСЃС‚Р°РІР»СЏРµС‚ preview С‡РµСЂРµР· audio.getById (РѕРґРЅРёРј Р±Р°С‚С‡-Р·Р°РїСЂРѕСЃРѕРј).
    РњРµРЅСЏРµС‚ СЃРїРёСЃРѕРє inplace.
    """
    # СЃРѕР±РµСЂС‘Рј РєР»СЋС‡Рё С‚РµС…, Сѓ РєРѕРіРѕ preview РїСѓСЃС‚РѕР№
    keys = []
    key_to_index = {}

    for i, t in enumerate(tracks):
        if t.get("preview"):
            continue
        k = _vk_audio_key(t.get("owner_id"), t.get("audio_id"), t.get("access_key"))
        if not k:
            continue
        key_to_index[k] = i
        keys.append(k)

    if not keys:
        return

    # VK РїСЂРёРЅРёРјР°РµС‚ РґРѕ РЅРµСЃРєРѕР»СЊРєРёС… СЃРѕС‚РµРЅ id Р·Р° СЂР°Р·, РЅРѕ РЅР° РІСЃСЏРєРёР№ СЃР»СѓС‡Р°Р№ СЂРµР¶РµРј
    CHUNK = 100
    for start in range(0, len(keys), CHUNK):
        part = keys[start:start + CHUNK]
        try:
            rj = _vk_call("audio.getById", token=token, params={"audios": ",".join(part)})
            data = rj.get("response") or []
            if not isinstance(data, list):
                continue

            for it in data:
                if not isinstance(it, dict):
                    continue
                oid = it.get("owner_id")
                aid = it.get("id")
                akey = it.get("access_key")
                url = it.get("url")

                # РїСЂРѕР±СѓРµРј СЃРѕРїРѕСЃС‚Р°РІРёС‚СЊ: СЃРЅР°С‡Р°Р»Р° СЃ access_key, РїРѕС‚РѕРј Р±РµР·
                k1 = _vk_audio_key(oid, aid, akey)
                k2 = _vk_audio_key(oid, aid, None)

                idx = None
                if k1 in key_to_index:
                    idx = key_to_index[k1]
                elif k2 in key_to_index:
                    idx = key_to_index[k2]

                if idx is not None and url:
                    tracks[idx]["preview"] = url

                    # РµСЃР»Рё access_key РІРґСЂСѓРі РїРѕСЏРІРёР»СЃСЏ вЂ” СЃРѕС…СЂР°РЅРёРј
                    if akey and not tracks[idx].get("access_key"):
                        tracks[idx]["access_key"] = akey

                    # РёРЅРѕРіРґР° Сѓ getById РјРѕР¶РЅРѕ РІС‹С‚Р°С‰РёС‚СЊ РѕР±Р»РѕР¶РєСѓ
                    if not tracks[idx].get("image") and isinstance(it.get("album"), dict):
                        tracks[idx]["image"] = _vk_pick_image_from_album(it["album"]) or tracks[idx].get("image")

        except Exception as e:
            print("VK enrich batch error:", type(e).__name__, str(e))

def search_vkmusic(q: str, performer_only: int = 0, offset: int = 0, count: int = 50, token: Optional[str] = None) -> List[Dict[str, Any]]:
    q_norm = " ".join((q or "").strip().split())
    offset = max(0, int(offset))
    count = max(1, min(int(count), 200))
    cache_key = f"vkmusic:search:{q_norm}:{performer_only}:{offset}:{count}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    vk_tok = _get_vk_token(token)
    if not vk_tok:
        return [{"error": "vkmusic: missing VK access token. Please provide token or set VK_ACCESS_TOKEN in environment"}]

    try:
        rj = _vk_call(
            "audio.search",
            token=vk_tok,
            params={
                "q": q_norm,
                "count": count,
                "offset": offset,
                "search_own": 0,
                "performer_only": performer_only,
            },
        )

        items = (rj.get("response") or {}).get("items", [])
        tracks = [_norm_vkmusic(x) for x in items]

        try:
            _vk_enrich_previews_batch(tracks, vk_tok)
        except Exception as enrich_err:
            print("VK preview enrich warning:", enrich_err)

        cache_set(cache_key, tracks, ttl=60)
        return tracks

    except Exception as e:
        return [{"error": f"vkmusic: {e}"}]

def vk_preview(track_id: str, token: Optional[str] = None) -> Dict[str, Any]:
    vk_tok = _get_vk_token(token)
    if not vk_tok:
        return {"error": "vkmusic: missing VK access token"}

    parts = track_id.split("_")
    if len(parts) < 2:
        return {"error": "bad track_id"}

    owner_id = parts[0]
    audio_id = parts[1]
    access_key = parts[2] if len(parts) >= 3 else None

    audios = f"{owner_id}_{audio_id}"
    if access_key:
        audios = f"{audios}_{access_key}"

    try:
        rj = _vk_call("audio.getById", token=vk_tok, params={"audios": audios})
        arr = rj.get("response") or []
        it = arr[0] if isinstance(arr, list) and arr else {}
        url = it.get("url")

        return {
            "id": track_id,
            "preview": url,
            "source": "vkmusic",
        }
    except Exception as e:
        return {"error": f"vkmusic preview: {e}"}

def vk_artist_tracks(artist_id: Optional[str], artist_name: Optional[str], token: Optional[str] = None) -> Dict[str, Any]:
    vk_tok = _get_vk_token(token)
    if not vk_tok:
        return {"error": "vkmusic: missing VK access token"}

    cache_key = f"vkmusic:artist:{artist_id or artist_name or ''}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    try:
        tracks: List[Dict[str, Any]] = []
        meta_name = artist_name

        if artist_id:
            rj = _vk_call(
                "audio.getAudiosByArtist",
                token=vk_tok,
                params={"artist_id": artist_id, "count": 25, "offset": 0},
            )
            items = (rj.get("response") or {}).get("items") or (rj.get("response") or [])
            if isinstance(items, dict):
                items = items.get("items") or []
            if not isinstance(items, list):
                items = []

            tracks = [_norm_vkmusic(x) for x in items]
            try:
                _vk_enrich_previews_batch(tracks, vk_tok)
            except Exception:
                pass

        if not tracks and artist_name:
            tracks = search_vkmusic(artist_name, performer_only=1, token=vk_tok)

        payload = {
            "type": "artist",
            "source": "vkmusic",
            "artist": {
                "artist_id": artist_id,
                "artist_name": meta_name or artist_name or "",
                "image": None,
            },
            "tracks": tracks,
        }

        cache_set(cache_key, payload, ttl=60)
        return payload

    except Exception as e:
        if artist_name:
            return {
                "type": "artist",
                "source": "vkmusic",
                "artist": {"artist_id": artist_id, "artist_name": artist_name, "image": None},
                "tracks": search_vkmusic(artist_name, performer_only=1, token=vk_tok),
                "warning": f"fallback_to_search: {type(e).__name__}: {e}",
            }
        return {"error": f"vkmusic artist: {type(e).__name__}: {e}"}


def vk_playlist_album(owner_id: str, album_id: str, access_key: Optional[str] = None, token: Optional[str] = None) -> Dict[str, Any]:
    vk_tok = _get_vk_token(token)
    if not vk_tok:
        return {"error": "vkmusic: missing VK access token"}

    cache_key = f"vkmusic:album:{owner_id}:{album_id}:{access_key or ''}"
    cached = cache_get(cache_key)
    if cached:
        return cached

    try:
        meta = {}
        try:
            params = {"owner_id": owner_id, "playlist_id": album_id}
            if access_key:
                params["access_key"] = access_key
            meta_json = _vk_call("audio.getPlaylistById", token=token, params=params)
            meta = meta_json.get("response") or {}
        except Exception as e:
            print("VK playlist meta error:", e)
            meta = {}

        params2 = {"owner_id": owner_id, "album_id": album_id, "count": 200, "offset": 0}
        if access_key:
            params2["access_key"] = access_key

        rj = _vk_call("audio.get", token=token, params=params2)
        items = (rj.get("response") or {}).get("items") or (rj.get("response") or [])
        if isinstance(items, dict):
            items = items.get("items") or []
        if not isinstance(items, list):
            items = []

        tracks = [_norm_vkmusic(x) for x in items]
        _vk_enrich_previews_batch(tracks, token)

        title = meta.get("title") or meta.get("name")
        photo = None
        thumbs = meta.get("thumbs") or []
        if isinstance(thumbs, list) and thumbs:
            photo = thumbs[-1].get("photo_600") or thumbs[-1].get("photo_300") or thumbs[-1].get("photo_135")
        photo = photo or meta.get("photo_600") or meta.get("photo_300")

        payload = {
            "type": "album",
            "source": "vkmusic",
            "album": {
                "owner_id": owner_id,
                "album_id": album_id,
                "access_key": access_key,
                "album_title": title,
                "image": photo,
            },
            "tracks": tracks,
        }

        cache_set(cache_key, payload, ttl=60)
        return payload

    except Exception as e:
        return {"error": f"vkmusic album: {type(e).__name__}: {e}"}


# ======================================================================================
# ===== Search v2 (pagination + artist hints) ===========================================
# ======================================================================================

def _search_artists_yandex(q: str, limit: int) -> List[Dict[str, Any]]:
    token = os.getenv("YANDEXMUSIC_TOKEN")
    if not token:
        return []
    try:
        data = _ym_request(
            "https://api.music.yandex.net/search",
            token=token,
            params={"text": q, "type": "artist", "page": 0, "pageSize": max(5, min(limit, 20))},
            use_proxy=False,
        )
        artists = data.get("result", {}).get("artists", {}).get("results", []) or []
        out: List[Dict[str, Any]] = []
        for a in artists[:limit]:
            if not isinstance(a, dict):
                continue
            aid = a.get("id")
            name = a.get("name")
            cover = a.get("cover") or {}
            uri = None
            if isinstance(cover, dict):
                uri = cover.get("uri") or cover.get("coverUri")
            img = _ym_cover_to_image(uri) if uri else None
            out.append(
                {
                    "artist_id": str(aid) if aid is not None else None,
                    "artist_name": name,
                    "image": img,
                    "source": "yandex",
                }
            )
        return out
    except Exception as e:
        print("Yandex artist search error:", e)
        return []


def _search_artists_spotify(q: str, limit: int) -> List[Dict[str, Any]]:
    token = _get_spotify_token()
    if not token:
        return []
    qn = " ".join((q or "").strip().split())
    try:
        r = _HTTP.get(
            "https://api.spotify.com/v1/search",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "User-Agent": "WaveServer/1.0",
            },
            params={"q": qn, "type": "artist", "limit": max(1, min(limit, 50))},
            timeout=_CFG.http_timeout_s,
            proxies=_proxies_if_enabled(),
        )
        if r.status_code != 200:
            return []
        items = r.json().get("artists", {}).get("items", []) or []
        out: List[Dict[str, Any]] = []
        for it in items:
            if not isinstance(it, dict):
                continue
            imgs = it.get("images") or []
            img = imgs[0].get("url") if imgs else None
            out.append(
                {
                    "artist_id": it.get("id"),
                    "artist_name": it.get("name"),
                    "image": img,
                    "source": "spotify",
                }
            )
        return out
    except Exception as e:
        print("Spotify artist search error:", e)
        return []


def _search_artists_vk_hint(q: str, limit: int, token: Optional[str] = None) -> List[Dict[str, Any]]:
    vk_tok = _get_vk_token(token)
    if not vk_tok:
        return []
    try:
        rj = _vk_call(
            "audio.search",
            token=vk_tok,
            params={
                "q": q,
                "count": 30,
                "offset": 0,
                "search_own": 0,
                "performer_only": 1,
            },
        )
        items = (rj.get("response") or {}).get("items", []) or []
        seen = set()
        out: List[Dict[str, Any]] = []
        for it in items:
            if not isinstance(it, dict):
                continue
            name = (it.get("artist") or "").strip()
            if not name:
                continue
            key = name.lower()
            if key in seen:
                continue
            seen.add(key)
            alb = it.get("album")
            img = _vk_pick_image_from_album(alb) if isinstance(alb, dict) else None
            out.append(
                {
                    "artist_id": None,
                    "artist_name": name,
                    "image": img,
                    "source": "vkmusic",
                }
            )
            if len(out) >= limit:
                break
        return out
    except Exception as e:
        print("VK artist hint error:", e)
        return []


def search_artists_hint(service: str, q: str, limit: int = 8, token: Optional[str] = None) -> List[Dict[str, Any]]:
    service = (service or "").lower()
    if service in ("itunes",):
        service = "yandex"
    if service == "":
        service = "yandex"
    if service in ("yandex", "yandexmusic", "ya", "", "itunes"):
        return _search_artists_yandex(q, limit)
    if service == "spotify":
        return _search_artists_spotify(q, limit)
    if service == "vkmusic":
        return _search_artists_vk_hint(q, limit, token=token)
    return []


def search_enriched_v2(
    service: str,
    q: str,
    offset: int,
    limit: int,
    refresh: bool = False,
    token: Optional[str] = None,
) -> Dict[str, Any]:
    service = (service or "yandex").lower()
    if service in ("itunes",):
        service = "yandex"
    if service == "":
        service = "yandex"
    limit = max(1, min(int(limit), 100))
    offset = max(0, int(offset))

    artists: List[Dict[str, Any]] = []
    if offset == 0:
        artists = search_artists_hint(service, q, 8, token=token)

    tracks: List[Dict[str, Any]] = []
    if service in ("yandex", "yandexmusic", "ya", "itunes", ""):
        page_size = limit
        page = offset // page_size if page_size else 0
        tracks = search_yandexmusic(q, page=page, page_size=page_size)
    elif service == "spotify":
        tracks = search_spotify(q, offset=offset, limit=limit)
    elif service == "soundcloud":
        tracks = search_soundcloud(q, offset=offset, limit=limit, bypass_cache=refresh)
    elif service == "vkmusic":
        tracks = search_vkmusic(q, performer_only=0, offset=offset, count=limit, token=token)
    else:
        tracks = [{"error": f"Unsupported service: {service}"}]

    err = next((t for t in tracks if isinstance(t, dict) and t.get("error")), None)
    if err:
        has_more = False
        playable = 0
    else:
        playable = len(tracks)
        has_more = playable >= limit

    return {
        "tracks": tracks,
        "artists": artists,
        "has_more": has_more,
        "next_offset": offset + playable,
    }


def spotify_artist_top_tracks_payload(artist_id: str) -> Dict[str, Any]:
    token = _get_spotify_token()
    if not token:
        return {"error": "spotify: missing token"}
    try:
        r = _HTTP.get(
            f"https://api.spotify.com/v1/artists/{artist_id}",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "User-Agent": "WaveServer/1.0",
            },
            timeout=_CFG.http_timeout_s,
            proxies=_proxies_if_enabled(),
        )
        if r.status_code != 200:
            return {"error": f"spotify artist HTTP {r.status_code}", "details": r.text[:500]}
        meta = r.json()
        imgs = meta.get("images") or []
        img = imgs[0].get("url") if imgs else None

        r2 = _HTTP.get(
            f"https://api.spotify.com/v1/artists/{artist_id}/top-tracks",
            params={"market": "US"},
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "User-Agent": "WaveServer/1.0",
            },
            timeout=_CFG.http_timeout_s,
            proxies=_proxies_if_enabled(),
        )
        r2.raise_for_status()
        titems = r2.json().get("tracks", []) or []
        track_list = [_norm_spotify(x) for x in titems if isinstance(x, dict)]

        return {
            "type": "artist",
            "source": "spotify",
            "artist": {
                "artist_id": meta.get("id"),
                "artist_name": meta.get("name"),
                "image": img,
            },
            "tracks": track_list,
        }
    except Exception as e:
        return {"error": f"spotify artist: {type(e).__name__}: {e}"}


# ======================================================================================
# ===== Handler ========================================================================
# ======================================================================================

def handler(event, context):
    if isinstance(event, str):
        try:
            event = json.loads(event)
        except Exception:
            event = {}

    if event.get("httpMethod") == "OPTIONS":
        return {"statusCode": 204, "headers": _cors_headers(), "body": ""}

    params = event.get("queryStringParameters") or {}

    def _p(name: str) -> str:
        return (params.get(name, "") or "").strip()

    service = _p("service").lower()

    # type: search | artist | album | preview | stream | img | img_raw
    req_type = (_p("type") or "search").lower()

    q = _p("q")
    stream_url = _p("u")
    track_id = _p("track_id")


    # вњ… STREAM endpoint
    if req_type == "stream":
        return proxy_stream(stream_url, event)
    
    img_url = _p("u")

    # вњ… IMAGE endpoint (РѕР±Р»РѕР¶РєРё С‡РµСЂРµР· РїСЂРѕРєСЃРё)
    if req_type == "img":
        return proxy_image(img_url, raw_mode=False)

    # вњ… IMAGE endpoint (raw intent; transport remains base64 for gateway)
    if req_type == "img_raw":
        return proxy_image(img_url, raw_mode=True)



    # ids for artist/album
    artist_id = (params.get("artist_id", "") or "").strip() or None
    artist_name = (params.get("artist_name", "") or "").strip() or None

    album_id = (params.get("album_id", "") or "").strip() or None

    # vk playlist album args
    owner_id = (params.get("owner_id", "") or "").strip() or None
    access_key = (params.get("access_key", "") or "").strip() or None
    token_param = (_p("token") or _p("vk_token") or _p("vkmusic_token")).strip() or None

    try:
        # ----------------- PREVIEW -----------------
        if req_type == "preview":
            if service != "vkmusic":
                return _response(400, {"error": "preview supported only for vkmusic"})
            if not track_id:
                return _response(400, {"error": "Missing track_id"})
            data = vk_preview(track_id, token=token_param)
            return _response(200, data)

        # ----------------- SIMILAR (recommendations) -----------------
        if req_type == "similar":
            if not track_id:
                return _response(400, {"error": "Missing track_id"})
            data = yandex_similar_tracks(track_id)
            return _response(200, data)
            
        # ----------------- SEARCH V2 (tracks + artists + pagination) -----------------
        if req_type == "search_v2":
            if not q:
                return _response(400, {"error": "Missing q"})
            try:
                limit = int(_p("limit") or "40")
            except Exception:
                limit = 40
            try:
                offset = int(_p("offset") or "0")
            except Exception:
                offset = 0
            refresh = (_p("refresh").lower() in ("1", "true", "yes", "y", "on"))
            payload = search_enriched_v2(service, q, offset, limit, refresh=refresh, token=token_param)
            return _response(200, payload)

        # ----------------- SEARCH (legacy: list of tracks, first page) -----------------
        if req_type in ("search", ""):
            if not q:
                return _response(400, {"error": "Missing q"})

            if service in ("yandex", "yandexmusic", "ya", "itunes", ""):
                data = search_yandexmusic(q, page=0, page_size=50)
            elif service == "spotify":
                data = search_spotify(q, offset=0, limit=50)
            elif service == "soundcloud":
                data = search_soundcloud(q, offset=0, limit=50)
            elif service == "vkmusic":
                data = search_vkmusic(q, offset=0, count=50, token=token_param)
            else:
                return _response(400, {"error": f"Unsupported service: {service}"})

            return _response(200, data)

        


        # ----------------- ARTIST -----------------
        if req_type == "artist":
            # Spotify
            if service == "spotify":
                fallback_name = (artist_name or q or "").strip()
                aid = (artist_id or "").strip() or None
                if not aid and fallback_name:
                    found = _search_artists_spotify(fallback_name, 1)
                    if found:
                        aid = found[0].get("artist_id")
                if aid:
                    data = spotify_artist_top_tracks_payload(aid)
                    if isinstance(data, dict) and data.get("error"):
                        return _response(502, data)
                    return _response(200, data)
                return _response(200, {
                    "type": "artist",
                    "source": "spotify",
                    "artist": {"artist_id": None, "artist_name": fallback_name, "image": None},
                    "tracks": search_spotify(fallback_name, offset=0, limit=30),
                    "warning": "spotify_artist_fallback_search",
                })

            # Yandex
            if service in ("yandex", "yandexmusic", "ya", "itunes", ""):
                # РјРѕР¶РЅРѕ РїРµСЂРµРґР°С‚СЊ artist_id РёР»Рё РёРјСЏ
                if not artist_id and not artist_name and not q:
                    return _response(400, {"error": "Missing artist_id or artist_name (or q as fallback)"})
                fallback_name = artist_name or q
                if not artist_id:
                    # РЅРµС‚ id -> РїСЂРѕСЃС‚Рѕ РїРѕРёСЃРє
                    return _response(200, {
                        "type": "artist",
                        "source": "yandex",
                        "artist": {"artist_id": None, "artist_name": fallback_name, "image": None},
                        "tracks": search_yandexmusic(fallback_name, page=0, page_size=50),
                        "warning": "no_artist_id_provided_fallback_to_search"
                    })
                data = yandex_artist_top_tracks(artist_id, fallback_name=fallback_name)
                return _response(200, data)

            # VK
            if service == "vkmusic":
                # РїРѕРґРґРµСЂР¶РёРІР°РµРј: artist_id РёР»Рё artist_name/q
                name = artist_name or q
                if not artist_id and not name:
                    return _response(400, {"error": "Missing artist_id or artist_name (or q as fallback)"})
                data = vk_artist_tracks(artist_id=artist_id, artist_name=name)
                return _response(200, data)

            return _response(400, {"error": f"Unsupported service for artist: {service}"})

        # ----------------- ALBUM -----------------
        if req_type == "album":
            # Yandex
            if service in ("yandex", "yandexmusic", "ya", "itunes", ""):
                if not album_id:
                    return _response(400, {"error": "Missing album_id"})
                data = yandex_album_with_tracks(album_id)
                return _response(200, data)

            # VK playlist album
            if service == "vkmusic":
                if not owner_id or not album_id:
                    return _response(400, {"error": "Missing owner_id or album_id (playlist_id)"})
                data = vk_playlist_album(owner_id=owner_id, album_id=album_id, access_key=access_key)
                return _response(200, data)

            return _response(400, {"error": f"Unsupported service for album: {service}"})

        return _response(400, {"error": f"Unsupported type: {req_type}"})

    except Exception as e:
        return _response(500, {"error": f"{type(e).__name__}: {e}"})