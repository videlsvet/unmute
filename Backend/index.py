import json
import os
import hashlib
import hmac
import jwt
import base64
import time
import boto3
import requests
import xml.etree.ElementTree as ET
import ydb
import re
import ydb.iam
import traceback
from typing import Tuple, Optional, Any, Dict, List, Callable

# ======================================
#     Security / JWT / Passwords
# ======================================

SECRET_KEY = (os.getenv("WAVE_SECRET_KEY", "") or "").strip()
JWT_ISS = (os.getenv("JWT_ISS", "") or "").strip() or "wave"
JWT_AUD = (os.getenv("JWT_AUD", "") or "").strip() or "wave-app"
JWT_TTL_S = int((os.getenv("JWT_TTL_S", "") or "").strip() or "2592000")  # 30 days
if not SECRET_KEY:
    raise RuntimeError("WAVE_SECRET_KEY is not set")

PBKDF2_ITERS = int((os.getenv("PBKDF2_ITERS", "") or "").strip() or "100000")


def _now() -> int:
    return int(time.time())


def _issue_token(nickname: str) -> str:
    if not SECRET_KEY:
        raise RuntimeError("WAVE_SECRET_KEY is not set")
    iat = _now()
    payload = {
        "nickname": nickname,
        "iat": iat,
        "exp": iat + max(60, int(JWT_TTL_S)),
        "iss": JWT_ISS,
        "aud": JWT_AUD,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")


def _hash_password_pbkdf2(password: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ITERS, dklen=32)
    return "pbkdf2_sha256${}${}${}".format(
        PBKDF2_ITERS,
        base64.urlsafe_b64encode(salt).decode("ascii").rstrip("="),
        base64.urlsafe_b64encode(dk).decode("ascii").rstrip("="),
    )


def _verify_password(password: str, stored: str) -> bool:
    stored = (stored or "").strip()
    if not stored:
        return False

    # New format
    if stored.startswith("pbkdf2_sha256$"):
        try:
            _, iters_s, salt_b64, dk_b64 = stored.split("$", 3)
            iters = int(iters_s)

            def _b64d(s: str) -> bytes:
                pad = "=" * ((4 - (len(s) % 4)) % 4)
                return base64.urlsafe_b64decode((s + pad).encode("ascii"))

            salt = _b64d(salt_b64)
            expected = _b64d(dk_b64)
            dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iters, dklen=len(expected))
            return hmac.compare_digest(dk, expected)
        except Exception:
            return False

    # Legacy sha256 hex (kept for existing users)
    if re.fullmatch(r"[0-9a-f]{64}", stored.lower() or ""):
        return stored.lower() == hashlib.sha256(password.encode("utf-8")).hexdigest()

    return False

# ======================================
#            YDB подключение
# ======================================
driver_config = ydb.DriverConfig(
    endpoint="grpcs://ydb.serverless.yandexcloud.net:2135",
    database="/ru-central1/b1gv22vbpgub3re3p1bl/etno5imvmb5j5fsqthnr",
    credentials=ydb.iam.MetadataUrlCredentials()
)
driver = ydb.Driver(driver_config)
driver.wait(fail_fast=True, timeout=5)


def _ydb_session():
    # create a fresh session; YDB serverless sessions can expire
    return driver.table_client.session().create()


def _ydb_retry(fn: Callable[[], Any], tries: int = 3, base_delay_s: float = 0.15):
    last_err = None
    for i in range(max(1, tries)):
        try:
            return fn()
        except Exception as e:
            last_err = e
            # best-effort: retry transient issues
            time.sleep(base_delay_s * (2 ** i))
    raise last_err


def _prepare(session, query: str):
    return session.prepare(query)

# ======================================
#            Конфигурация
# ======================================
S3_ENDPOINT = "https://storage.yandexcloud.net"
BUCKET_NAME = os.getenv("BUCKET_NAME", "wave-avatars")

S3 = boto3.client(
    "s3",
    endpoint_url=S3_ENDPOINT,
    aws_access_key_id=os.getenv("YC_ACCESS_KEY"),
    aws_secret_access_key=os.getenv("YC_SECRET_KEY"),
)

# ======================================
#        Иниц. таблиц (+ миграции)
# ======================================
def init_tables():
    # Пользователи
    session = _ydb_session()
    try:
        session.execute_scheme("""
        CREATE TABLE users (
            nickname Utf8,
            password_hash Utf8,
            avatar_url Utf8,
            PRIMARY KEY (nickname)
        );
        """)
    except Exception as e:
        if "already exists" not in str(e):
            print("Users table error:", e)

    # Ключи сервисов
    try:
        session.execute_scheme("""
        CREATE TABLE user_keys (
            nickname Utf8,
            spotify_id Utf8,
            spotify_secret Utf8,
            soundcloud_id Utf8,
            yandex_token Utf8,
            vkmusic_token Utf8,
            PRIMARY KEY (nickname)
        );
        """)
    except Exception as e:
        if "already exists" not in str(e):
            print("Keys table error:", e)

    # Треки внутри плейлистов (нормальная модель)
    try:
        session.execute_scheme("""
        CREATE TABLE playlist_tracks (
            nickname Utf8,
            playlist_id Utf8,
            track_id Utf8,          -- уникальный id трека в твоей системе: source:external или хеш
            title Utf8,
            artist Utf8,
            image Utf8,
            preview Utf8,
            source Utf8,
            external_id Utf8,

            artist_id Utf8,
            album_id Utf8,
            album_title Utf8,
            album_year Utf8,
            owner_id Utf8,
            audio_id Utf8,
            access_key Utf8,

            added_at Timestamp,
            PRIMARY KEY (nickname, playlist_id, track_id)
        );
        """)
    except Exception as e:
        if "already exists" not in str(e):
            print("playlist_tracks table error:", e)

    # Плейлисты пользователя
    try:
        session.execute_scheme("""
        CREATE TABLE user_playlists (
            nickname Utf8,
            playlist_id Utf8,
            title Utf8,
            source Utf8,
            link Utf8,
            owner Utf8,
            external_id Utf8,
            PRIMARY KEY (nickname, playlist_id)
        );
        """)
    except Exception as e:
        if "already exists" not in str(e):
            print("Playlists table error:", e)

    # Избранные треки
    created = False
    try:
        session.execute_scheme("""
        CREATE TABLE user_favorites (
            nickname Utf8,
            track_id Utf8,
            title Utf8,
            artist Utf8,
            image Utf8,
            preview Utf8,
            liked_at Timestamp,
            source Utf8,
            external_id Utf8,

            artist_id Utf8,
            album_id Utf8,
            album_title Utf8,
            album_year Utf8,
            owner_id Utf8,
            audio_id Utf8,
            access_key Utf8,

            PRIMARY KEY (nickname, track_id)
        );
        """)
        created = True
    except Exception as e:
        if "already exists" not in str(e):
            print("Favorites table error:", e)

    # Реальные треки внутри плейлиста
    try:
        session.execute_scheme("""
        CREATE TABLE playlist_real_tracks (
            nickname Utf8,
            playlist_id Utf8,
            track_index Uint32,
            title Utf8,
            artist Utf8,
            image Utf8,
            preview Utf8,
            source Utf8,
            external_id Utf8,
            album_id Utf8,
            album_title Utf8,
            album_year Utf8,
            artist_id Utf8,
            owner_id Utf8,
            audio_id Utf8,
            access_key Utf8,
            PRIMARY KEY (nickname, playlist_id, track_index)
        );
        """)
    except Exception as e:
        if "already exists" not in str(e):
            print("Playlist tracks table error:", e)

    # Таблица прогресса импорта
    try:
        session.execute_scheme("""
        CREATE TABLE import_progress (
            progress_id Utf8,
            status Utf8,
            done Uint32,
            total Uint32,
            current Utf8,
            updated_at Timestamp,
            PRIMARY KEY (progress_id)
        );
        """)
    except Exception as e:
        if "already exists" not in str(e):
            print("Import progress table error:", e)

    # ✅ Миграции — ТОЛЬКО если таблица уже была
    if not created:
        def _add(col_sql: str, ok_msg: str, err_msg: str):
            try:
                session.execute_scheme(col_sql)
                print(ok_msg)
            except Exception as e:
                if "already exists" not in str(e):
                    print(err_msg, e)

        _add("""ALTER TABLE user_favorites ADD COLUMN liked_at Timestamp;""",
             "Migrated: added liked_at", "Migration liked_at error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN source Utf8;""",
             "Migrated: added source", "Migration source error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN external_id Utf8;""",
             "Migrated: added external_id", "Migration external_id error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN artist_id Utf8;""",
             "Migrated: added artist_id", "Migration artist_id error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN album_id Utf8;""",
             "Migrated: added album_id", "Migration album_id error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN album_title Utf8;""",
             "Migrated: added album_title", "Migration album_title error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN album_year Utf8;""",
             "Migrated: added album_year", "Migration album_year error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN owner_id Utf8;""",
             "Migrated: added owner_id", "Migration owner_id error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN audio_id Utf8;""",
             "Migrated: added audio_id", "Migration audio_id error:")

        _add("""ALTER TABLE user_favorites ADD COLUMN access_key Utf8;""",
             "Migrated: added access_key", "Migration access_key error:")

    # Миграции для playlist_real_tracks
    try:
        session.execute_scheme("""
        ALTER TABLE playlist_real_tracks ADD COLUMN album_id Utf8;
        """)
        print("Migrated: added album_id to playlist_real_tracks")
    except Exception as e:
        if "already exists" not in str(e):
            print("Migration album_id error:", e)

    try:
        session.execute_scheme("""
        ALTER TABLE playlist_real_tracks ADD COLUMN album_title Utf8;
        """)
        print("Migrated: added album_title to playlist_real_tracks")
    except Exception as e:
        if "already exists" not in str(e):
            print("Migration album_title error:", e)

    try:
        session.execute_scheme("""
        ALTER TABLE playlist_real_tracks ADD COLUMN album_year Utf8;
        """)
        print("Migrated: added album_year to playlist_real_tracks")
    except Exception as e:
        if "already exists" not in str(e):
            print("Migration album_year error:", e)

    try:
        session.execute_scheme("""
        ALTER TABLE playlist_real_tracks ADD COLUMN artist_id Utf8;
        """)
        print("Migrated: added artist_id to playlist_real_tracks")
    except Exception as e:
        if "already exists" not in str(e):
            print("Migration artist_id error:", e)

    try:
        session.execute_scheme("""
        ALTER TABLE playlist_real_tracks ADD COLUMN owner_id Utf8;
        """)
        print("Migrated: added owner_id to playlist_real_tracks")
    except Exception as e:
        if "already exists" not in str(e):
            print("Migration owner_id error:", e)

    try:
        session.execute_scheme("""
        ALTER TABLE playlist_real_tracks ADD COLUMN audio_id Utf8;
        """)
        print("Migrated: added audio_id to playlist_real_tracks")
    except Exception as e:
        if "already exists" not in str(e):
            print("Migration audio_id error:", e)

    try:
        session.execute_scheme("""
        ALTER TABLE playlist_real_tracks ADD COLUMN access_key Utf8;
        """)
        print("Migrated: added access_key to playlist_real_tracks")
    except Exception as e:
        if "already exists" not in str(e):
            print("Migration access_key error:", e)

init_tables()


# ======================================
#        Утилиты ответов (CORS)
# ======================================
def _cors_headers() -> Dict[str, str]:
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
    }

def _resp(status: int, body: Any) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": _cors_headers(),
        "body": json.dumps(body, ensure_ascii=False)
    }

def _require_body(event: Dict[str, Any]):
    if "body" not in event or not event["body"]:
        return None, _resp(400, {"error": "Empty request body"})
    try:
        return json.loads(event["body"]), None
    except Exception as e:
        return None, _resp(400, {"error": f"Invalid JSON: {e}"})

def _decode_token(token: str):
    if not SECRET_KEY:
        return None, _resp(500, {"error": "Server misconfigured: WAVE_SECRET_KEY is not set"})
    try:
        return (
            jwt.decode(
                token,
                SECRET_KEY,
                algorithms=["HS256"],
                issuer=JWT_ISS,
                audience=JWT_AUD,
                options={"require": ["exp", "iat", "iss", "aud"]},
            ),
            None,
        )
    except jwt.ExpiredSignatureError:
        return None, _resp(401, {"error": "Token expired"})
    except jwt.InvalidTokenError:
        return None, _resp(401, {"error": "Invalid token"})

# ======================================
#     Вспомогательные для аватаров
# ======================================
def _mime_and_ext_from_data_uri(data_uri: str):
    try:
        header = data_uri.split(";")[0]
        mime = header.split(":", 1)[1]
        if mime == "image/jpeg":
            return mime, ".jpg"
        if mime == "image/webp":
            return mime, ".webp"
        if mime == "image/png":
            return mime, ".png"
        return mime, ".png"
    except Exception:
        return "image/png", ".png"

def _upload_avatar_and_get_url(nickname: str, avatar_input: str) -> str:
    """
    Принимает либо data:image;base64,... либо прямой http(s) URL.
    Если http(s) — возвращает его как есть.
    Если data:image — загружает в бакет и возвращает публичную ссылку.
    """
    if not avatar_input:
        return ""

    # Прямой URL
    if avatar_input.startswith("http://") or avatar_input.startswith("https://"):
        return avatar_input

    # Data URI
    if avatar_input.startswith("data:image"):
        mime, ext = _mime_and_ext_from_data_uri(avatar_input)
        base64_data = avatar_input.split(",", 1)[1] if "," in avatar_input else avatar_input
        img_bytes = base64.b64decode(base64_data)

        key = f"avatars/{nickname}{ext}"

        S3.put_object(
            Bucket=BUCKET_NAME,
            Key=key,
            Body=img_bytes,
            ContentType=mime,
            ACL="public-read"
        )

        return f"{S3_ENDPOINT}/{BUCKET_NAME}/{key}"

    return ""
    
def _norm_txt(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"\s+", " ", s)
    s = s.replace("ё", "е")
    return s

def _search_yandex_track_id_by_meta(title: str, artist: str, token: str) -> Optional[int]:
    """
    Находит track_id в Я.Музыке по "artist + title".
    """
    try:
        q = f"{artist} {title}".strip()
        if not q:
            return None

        r = requests.get(
            "https://api.music.yandex.net/search",
            params={"text": q, "type": "track", "page": 0, "pageSize": 10},
            headers={"Authorization": f"OAuth {token}"},
            timeout=10
        )
        r.raise_for_status()

        tracks = r.json().get("result", {}).get("tracks", {}).get("results", []) or []
        if not tracks:
            return None

        t0 = _norm_txt(title)
        a0 = _norm_txt(artist)

        best_id = None
        best_score = -1

        for item in tracks:
            t = _norm_txt(item.get("title", ""))
            artists = ", ".join([a.get("name", "") for a in item.get("artists", [])])
            a = _norm_txt(artists)

            score = 0
            if t == t0: score += 3
            elif t0 and t0 in t: score += 2
            elif t and t in t0: score += 1

            if a0 and a0 in a: score += 3
            elif a and a in a0: score += 1

            if score > best_score:
                best_score = score
                best_id = item.get("id")

        if best_id is None:
            return None

        return int(best_id)

    except Exception as e:
        print("Yandex search by meta error:", e)
        return None

# ======================================
#     Yandex: refresh stream URL (mp3)
# ======================================
def _get_yandex_stream(track_id: int, token: str) -> Optional[str]:
    try:
        track_id = int(track_id)

        info = requests.get(
            f"https://api.music.yandex.net/tracks/{track_id}/download-info",
            headers={"Authorization": f"OAuth {token}"},
            timeout=10
        )
        info.raise_for_status()

        infos = info.json().get("result", [])
        if not infos:
            return None

        download_info_url = infos[0].get("downloadInfoUrl")
        if not download_info_url:
            return None

        if download_info_url.startswith("//"):
            download_info_url = "https:" + download_info_url
        elif download_info_url.startswith("/"):
            download_info_url = "https://api.music.yandex.net" + download_info_url

        xml_resp = requests.get(download_info_url, timeout=10)
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

def _get_search_backend_url() -> str:
    import base64 as _b64
    DEFAULT_SEARCH_URL = "https://functions.yandexcloud.net/d4e09khm9p5t3cu2oq22"
    raw = (os.getenv("SEARCH_BACKEND_URL", "") or "").strip()

    if raw.startswith("http://") or raw.startswith("https://"):
        return raw.strip()
    if raw:
        try:
            return _b64.b64decode(raw).decode().strip()
        except Exception:
            return DEFAULT_SEARCH_URL
    return DEFAULT_SEARCH_URL


def _search_soundcloud_preview_by_meta(title: str, artist: str) -> Optional[str]:
    """
    Ищет SoundCloud трек по метаданным (artist + title) через SEARCH backend.
    Возвращает fresh preview URL или None.
    """
    try:
        SEARCH_URL = _get_search_backend_url()
        q = f"{artist or ''} {title or ''}".strip()
        if not q:
            return None

        r = requests.get(
            SEARCH_URL,
            params={"service": "soundcloud", "q": q, "type": "search"},
            timeout=10
        )
        if r.status_code != 200:
            return None

        items = r.json()
        if not items or not isinstance(items, list) or not isinstance(items[0], dict):
            return None

        fresh = (items[0].get("preview") or "").strip()
        return fresh or None
    except Exception as e:
        print("SoundCloud search by meta error:", e)
        return None

# ======================================
#     Вспомогательные для плейлистов
# ======================================
def _detect_source_and_ids(link: str) -> Tuple[str, Optional[str], Optional[str]]:
    """
    Возвращает кортеж: (source, owner, external_id)
    source: yandexplaylist / spotifyplaylist / vkplaylist / soundcloudplaylist / unknown
    owner / external_id могут быть None, если распарсить не удалось.
    """
    link_l = link.lower().strip()

    # Yandex Music
    if "music.yandex" in link_l:
        owner = None
        external_id = None
        if "/users/" in link_l and "/playlists/" in link_l:
            try:
                owner = link_l.split("/users/")[1].split("/")[0]
                external_id = link_l.split("/playlists/")[1].split("?")[0].split("#")[0]
            except Exception:
                pass
        elif "/playlists/" in link_l:
            try:
                token = link_l.split("/playlists/")[1].split("?")[0].split("#")[0]
                owner = token
                external_id = token
            except Exception:
                pass
        return "yandexplaylist", owner, external_id

    # Spotify
    if "spotify" in link_l and "playlist" in link_l:
        owner = None
        external_id = None
        if "open.spotify.com" in link_l and "/playlist/" in link_l:
            try:
                external_id = link_l.split("/playlist/")[1].split("?")[0].split("#")[0]
            except Exception:
                pass
        elif link_l.startswith("spotify:playlist:"):
            try:
                external_id = link_l.split("spotify:playlist:")[1]
            except Exception:
                pass
        return "spotifyplaylist", owner, external_id

    # VK Music
    if "vk.com" in link_l and "/music/playlist/" in link_l:
        owner = None
        external_id = None
        try:
            tail = link_l.split("/music/playlist/")[1].split("?")[0].split("#")[0]
            owner = tail.split("_")[0]
            external_id = tail.split("_")[1] if "_" in tail else None
        except Exception:
            pass
        return "vkplaylist", owner, external_id

    # SoundCloud sets
    if "soundcloud.com" in link_l and "/sets/" in link_l:
        try:
            parts = link_l.split("soundcloud.com/")[1].split("/")
            owner = parts[0] if len(parts) > 0 else None
            external_id = parts[2] if len(parts) > 2 else None
        except Exception:
            owner, external_id = None, None
        return "soundcloudplaylist", owner, external_id

    return "unknown", None, None

# ======================================
#               Handler
# ======================================

def handler(event, context):
    # CORS preflight
    if isinstance(event, dict) and event.get("httpMethod") == "OPTIONS":
        return {"statusCode": 204, "headers": _cors_headers(), "body": ""}

    try:
        body, err = _require_body(event if isinstance(event, dict) else {})
        if err:
            return err

        # Fresh session per invocation (serverless-safe)
        session = _ydb_session()

        action = body.get("action")
        if not action:
            return _resp(400, {"error": "Missing 'action'"})
        
        # -----------------------------
        #           REGISTER
        # -----------------------------
        if action == "register":
            nickname = (body.get("nickname") or "").strip()
            password = (body.get("password") or "").strip()
            avatar_input = (body.get("avatar_url") or "").strip()

            if not nickname or not password:
                return _resp(400, {"error": "Nickname and password required"})

            q_check = """
                DECLARE $nickname AS Utf8;
                SELECT nickname FROM users WHERE nickname = $nickname;
            """
            st = _prepare(session, q_check)
            res = _ydb_retry(lambda: session.transaction().execute(st, {"$nickname": nickname}, commit_tx=True))
            if res and len(res[0].rows) > 0:
                return _resp(400, {"error": "User already exists"})

            password_hash = _hash_password_pbkdf2(password)

            avatar_url = ""
            if avatar_input:
                try:
                    avatar_url = _upload_avatar_and_get_url(nickname, avatar_input)
                except Exception as e:
                    print("Avatar upload on register error:", e)
                    traceback.print_exc()
                    avatar_url = ""

            q_ins = """
                DECLARE $nickname AS Utf8;
                DECLARE $password_hash AS Utf8;
                DECLARE $avatar_url AS Utf8;
                INSERT INTO users (nickname, password_hash, avatar_url)
                VALUES ($nickname, $password_hash, $avatar_url);
            """
            st2 = _prepare(session, q_ins)
            _ydb_retry(
                lambda: session.transaction().execute(
                    st2,
                    {"$nickname": nickname, "$password_hash": password_hash, "$avatar_url": avatar_url},
                    commit_tx=True,
                )
            )

            token = _issue_token(nickname)
            return _resp(200, {"message": "registered successfully", "token": token, "avatar_url": avatar_url})

        # -----------------------------
        #        PLAYLISTS: CREATE
        # -----------------------------
        elif action == "create_playlist":
            token = (body.get("token") or "").strip()
            title = (body.get("title") or "").strip()
            if not token or not title:
                return _resp(400, {"error": "token, title required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            playlist_id = hashlib.sha1(f"{nickname}:{title}:{time.time()}".encode()).hexdigest()

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                DECLARE $title AS Utf8;

                UPSERT INTO user_playlists (nickname, playlist_id, title, source, link, owner, external_id)
                VALUES ($nickname, $playlist_id, $title, "local", "", "", "");
            """
            st = _prepare(session, q)
            _ydb_retry(
                lambda: session.transaction().execute(
                    st,
                    {"$nickname": nickname, "$playlist_id": playlist_id, "$title": title},
                    commit_tx=True,
                )
            )

            return _resp(200, {"message": "created", "playlist_id": playlist_id, "title": title})

        # -----------------------------
        #   PLAYLISTS: ADD TRACK
        # -----------------------------
        elif action == "add_track_to_playlist":
            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()
            track = body.get("track")

            if not token or not playlist_id or not track:
                return _resp(400, {"error": "token, playlist_id, track required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            source = (track.get("source") or "").strip()
            external_id = (track.get("id") or "").strip()

            artist_id = (track.get("artist_id") or "").strip()
            album_id = (track.get("album_id") or "").strip()
            album_title = (track.get("album_title") or "").strip()
            _raw_year = track.get("album_year")
            album_year = str(_raw_year).strip() if _raw_year is not None and str(_raw_year).strip() else ""

            owner_id = (track.get("owner_id") or "").strip()
            audio_id = str(track.get("audio_id") or "").strip()
            access_key = (track.get("access_key") or "").strip()

            base_id = external_id or f"{track.get('title','')}:{track.get('artist','')}"
            track_id = f"{source}:{base_id}" if source else base_id

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                DECLARE $track_id AS Utf8;

                DECLARE $title AS Utf8;
                DECLARE $artist AS Utf8;
                DECLARE $image AS Utf8;
                DECLARE $preview AS Utf8;
                DECLARE $source AS Utf8;
                DECLARE $external_id AS Utf8;

                DECLARE $artist_id AS Utf8;
                DECLARE $album_id AS Utf8;
                DECLARE $album_title AS Utf8;
                DECLARE $album_year AS Utf8;

                DECLARE $owner_id AS Utf8;
                DECLARE $audio_id AS Utf8;
                DECLARE $access_key AS Utf8;

                UPSERT INTO playlist_tracks
                (nickname, playlist_id, track_id, title, artist, image, preview, source, external_id,
                 artist_id, album_id, album_title, album_year,
                 owner_id, audio_id, access_key, added_at)
                VALUES
                ($nickname, $playlist_id, $track_id, $title, $artist, $image, $preview, $source, $external_id,
                 $artist_id, $album_id, $album_title, $album_year,
                 $owner_id, $audio_id, $access_key, CurrentUtcTimestamp());
            """

            st = _prepare(session, q)
            _ydb_retry(
                lambda: session.transaction().execute(
                    st,
                    {
                    "$nickname": nickname,
                    "$playlist_id": playlist_id,
                    "$track_id": track_id,

                    "$title": track.get("title", ""),
                    "$artist": track.get("artist", ""),
                    "$image": track.get("image", ""),
                    "$preview": track.get("preview", ""),
                    "$source": source,
                    "$external_id": external_id,

                    "$artist_id": artist_id,
                    "$album_id": album_id,
                    "$album_title": album_title,
                    "$album_year": album_year,

                    "$owner_id": owner_id,
                    "$audio_id": audio_id,
                    "$access_key": access_key,
                    },
                    commit_tx=True,
                )
            )

            return _resp(200, {"message": "added", "track_id": track_id})

        # -----------------------------
        #   PLAYLISTS: LIST TRACKS
        # -----------------------------
        elif action == "list_playlist_tracks":
            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()
            if not token or not playlist_id:
                return _resp(400, {"error": "token, playlist_id required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                SELECT
                  track_id, title, artist, image, preview, source, external_id,
                  artist_id, album_id, album_title, album_year,
                  owner_id, audio_id, access_key, added_at
                FROM playlist_tracks
                WHERE nickname = $nickname AND playlist_id = $playlist_id
                ORDER BY added_at DESC;
            """
            st = _prepare(session, q)
            res = _ydb_retry(
                lambda: session.transaction().execute(
                    st, {"$nickname": nickname, "$playlist_id": playlist_id}, commit_tx=True
                )
            )

            items = []
            for row in res[0].rows:
                year_int = None
                try:
                    y = (row.album_year or "").strip()
                    year_int = int(y) if y else None
                except Exception:
                    year_int = None

                items.append({
                    "id": row.track_id,
                    "title": row.title,
                    "artist": row.artist,
                    "image": row.image,
                    "preview": row.preview or "",
                    "source": row.source,
                    "externalId": row.external_id,

                    "artist_id": row.artist_id,
                    "album_id": row.album_id,
                    "album_title": row.album_title,
                    "album_year": year_int,

                    "owner_id": row.owner_id,
                    "audio_id": row.audio_id,
                    "access_key": row.access_key,
                })

            return _resp(200, {"tracks": items})

        # -----------------------------
        #   PLAYLISTS: REMOVE TRACK
        # -----------------------------
        elif action == "remove_track_from_playlist":
            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()
            track_id = (body.get("track_id") or "").strip()

            if not token or not playlist_id or not track_id:
                return _resp(400, {"error": "token, playlist_id, track_id required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                DECLARE $track_id AS Utf8;
                DELETE FROM playlist_tracks
                WHERE nickname = $nickname AND playlist_id = $playlist_id AND track_id = $track_id;
            """
            st = _prepare(session, q)
            _ydb_retry(
                lambda: session.transaction().execute(
                    st,
                    {"$nickname": nickname, "$playlist_id": playlist_id, "$track_id": track_id},
                    commit_tx=True,
                )
            )

            return _resp(200, {"message": "removed"})

        # -----------------------------
        #             LOGIN
        # -----------------------------
        elif action == "login":
            nickname = (body.get("nickname") or "").strip()
            password = (body.get("password") or "").strip()
            if not nickname or not password:
                return _resp(400, {"error": "Nickname and password required"})

            q = """
                DECLARE $nickname AS Utf8;
                SELECT password_hash FROM users WHERE nickname = $nickname;
            """
            st = _prepare(session, q)
            res = _ydb_retry(lambda: session.transaction().execute(st, {"$nickname": nickname}, commit_tx=True))
            if not res or len(res[0].rows) == 0:
                return _resp(404, {"error": "User not found"})

            db_hash = res[0].rows[0].password_hash
            if not _verify_password(password, db_hash):
                return _resp(401, {"error": "Wrong password"})

            # opportunistic upgrade from legacy sha256 to pbkdf2
            if re.fullmatch(r"[0-9a-f]{64}", (db_hash or "").lower() or ""):
                try:
                    new_hash = _hash_password_pbkdf2(password)
                    q_upd = """
                        DECLARE $nickname AS Utf8;
                        DECLARE $password_hash AS Utf8;
                        UPDATE users SET password_hash = $password_hash WHERE nickname = $nickname;
                    """
                    _ydb_retry(
                        lambda: session.transaction().execute(
                            _prepare(session, q_upd),
                            {"$nickname": nickname, "$password_hash": new_hash},
                            commit_tx=True,
                        )
                    )
                except Exception:
                    pass

            token = _issue_token(nickname)
            return _resp(200, {"message": "login ok", "token": token})

        # -----------------------------
        #          GET_PROFILE
        # -----------------------------
        elif action == "get_profile":
            token = body.get("token")
            if not token:
                return _resp(400, {"error": "Token required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            q = """
                DECLARE $nickname AS Utf8;
                SELECT nickname, avatar_url FROM users WHERE nickname = $nickname;
            """
            st = session.prepare(q)
            res = session.transaction().execute(st, {"$nickname": nickname}, commit_tx=True)
            if not res or len(res[0].rows) == 0:
                return _resp(404, {"error": "User not found"})

            row = res[0].rows[0]
            return _resp(200, {"nickname": row.nickname, "avatar_url": row.avatar_url or ""})

        # -----------------------------
        #         UPDATE_AVATAR
        # -----------------------------
        elif action == "update_avatar":
            token = body.get("token")
            avatar_input = (body.get("avatar_url") or "").strip()
            if not token:
                return _resp(400, {"error": "Token required"})
            if not avatar_input:
                return _resp(400, {"error": "avatar_url required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            try:
                public_url = _upload_avatar_and_get_url(nickname, avatar_input)
            except Exception as e:
                print("❌ Avatar upload error:", e)
                traceback.print_exc()
                return _resp(500, {"error": f"avatar upload failed: {str(e)}"})

            q_upd = """
                DECLARE $nickname AS Utf8;
                DECLARE $avatar_url AS Utf8;
                UPDATE users SET avatar_url = $avatar_url WHERE nickname = $nickname;
            """
            st = session.prepare(q_upd)
            session.transaction().execute(
                st,
                {"$nickname": nickname, "$avatar_url": public_url},
                commit_tx=True
            )
            return _resp(200, {"message": "avatar updated", "avatar_url": public_url})

        # -----------------------------
        #           SAVE_KEYS / GET_KEYS
        # -----------------------------
        elif action == "save_keys":
            token = body.get("token")
            if not token:
                return _resp(400, {"error": "Token required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            spotify_id = body.get("spotify_id", "")
            spotify_secret = body.get("spotify_secret", "")
            soundcloud_id = body.get("soundcloud_id", "")
            yandex_token = body.get("yandex_token", "")
            vkmusic_token = body.get("vkmusic_token", "")

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $spotify_id AS Utf8;
                DECLARE $spotify_secret AS Utf8;
                DECLARE $soundcloud_id AS Utf8;
                DECLARE $yandex_token AS Utf8;
                DECLARE $vkmusic_token AS Utf8;
                UPSERT INTO user_keys
                (nickname, spotify_id, spotify_secret, soundcloud_id, yandex_token, vkmusic_token)
                VALUES ($nickname, $spotify_id, $spotify_secret, $soundcloud_id, $yandex_token, $vkmusic_token);
            """
            st = session.prepare(q)
            session.transaction().execute(
                st,
                {
                    "$nickname": nickname,
                    "$spotify_id": spotify_id,
                    "$spotify_secret": spotify_secret,
                    "$soundcloud_id": soundcloud_id,
                    "$yandex_token": yandex_token,
                    "$vkmusic_token": vkmusic_token
                },
                commit_tx=True
            )

            return _resp(200, {"message": "keys saved successfully"})

        elif action == "get_keys":
            token = body.get("token")
            if not token:
                return _resp(400, {"error": "Token required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            q = """
                DECLARE $nickname AS Utf8;
                SELECT spotify_id, spotify_secret, soundcloud_id, yandex_token, vkmusic_token
                FROM user_keys WHERE nickname = $nickname;
            """
            st = session.prepare(q)
            res = session.transaction().execute(st, {"$nickname": nickname}, commit_tx=True)
            if not res or len(res[0].rows) == 0:
                return _resp(404, {"error": "No keys found"})

            row = res[0].rows[0]
            return _resp(200, {
                "spotify_id": row.spotify_id,
                "spotify_secret": row.spotify_secret,
                "soundcloud_id": row.soundcloud_id,
                "yandex_token": row.yandex_token,
                "vkmusic_token": row.vkmusic_token
            })

        # -----------------------------
        #           PLAYLISTS: ADD
        # -----------------------------
        elif action == "add_playlist":
            token = (body.get("token") or "").strip()
            title = (body.get("title") or "").strip()
            link = (body.get("link") or "").strip()

            if not token or not title or not link:
                return _resp(400, {"error": "token, title, link required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            source, owner, external_id = _detect_source_and_ids(link)
            if source == "unknown":
                return _resp(400, {"error": "Unknown playlist source"})

            playlist_id = hashlib.sha1(f"{nickname}:{link}".encode()).hexdigest()

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                DECLARE $title AS Utf8;
                DECLARE $source AS Utf8;
                DECLARE $link AS Utf8;
                DECLARE $owner AS Utf8;
                DECLARE $external_id AS Utf8;
                UPSERT INTO user_playlists (nickname, playlist_id, title, source, link, owner, external_id)
                VALUES ($nickname, $playlist_id, $title, $source, $link, $owner, $external_id);
            """
            st = session.prepare(q)
            session.transaction().execute(
                st,
                {
                    "$nickname": nickname,
                    "$playlist_id": playlist_id,
                    "$title": title,
                    "$source": source,
                    "$link": link,
                    "$owner": owner or "",
                    "$external_id": external_id or ""
                },
                commit_tx=True
            )

            return _resp(200, {
                "message": "added",
                "playlist_id": playlist_id,
                "source": source,
                "owner": owner or "",
                "external_id": external_id or ""
            })

        # -----------------------------
        #        PLAYLISTS: LIST (с количеством треков)
        # -----------------------------
        elif action == "list_playlists":
            token = (body.get("token") or "").strip()
            if not token:
                return _resp(400, {"error": "Token required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            q = """
                DECLARE $nickname AS Utf8;
                SELECT 
                    p.playlist_id, 
                    p.title, 
                    p.source, 
                    p.link, 
                    p.owner, 
                    p.external_id,
                    (SELECT COUNT(*) FROM playlist_real_tracks r 
                     WHERE r.nickname = p.nickname AND r.playlist_id = p.playlist_id) as track_count
                FROM user_playlists as p
                WHERE p.nickname = $nickname;
            """
            st = session.prepare(q)
            res = session.transaction().execute(st, {"$nickname": nickname}, commit_tx=True)

            items = []
            for row in res[0].rows:
                items.append({
                    "playlist_id": row.playlist_id,
                    "title": row.title,
                    "source": row.source,
                    "link": row.link,
                    "owner": row.owner,
                    "external_id": row.external_id,
                    "track_count": row.track_count or 0
                })

            return _resp(200, items)
        
        # -----------------------------
        #   IMPORT TEXT -> FAVORITES (BATCH, SAFE FOR TIMEOUT)
        # -----------------------------
        elif action == "import_text_to_favorites":
            import base64 as _b64

            DEFAULT_SEARCH_URL = "https://functions.yandexcloud.net/d4e09khm9p5t3cu2oq22"
            raw = (os.getenv("SEARCH_BACKEND_URL", "") or "").strip()

            if raw.startswith("http://") or raw.startswith("https://"):
                SEARCH_URL = raw.strip()
            elif raw:
                try:
                    SEARCH_URL = _b64.b64decode(raw).decode().strip()
                except Exception:
                    SEARCH_URL = DEFAULT_SEARCH_URL
            else:
                SEARCH_URL = DEFAULT_SEARCH_URL

            token = (body.get("token") or "").strip()
            text = (body.get("text") or "").strip()
            service = (body.get("service") or "vkmusic").strip().lower()

            # 🔥 батч-параметры
            offset = int(body.get("offset") or 0)
            batch_size = int(body.get("batch_size") or 2)  # <= ставь 1..3 если таймаут маленький
            if batch_size < 1:
                batch_size = 1
            if batch_size > 5:
                batch_size = 5  # не разгоняйся, иначе опять таймаут

            if not token or not text:
                return _resp(400, {"error": "token, text required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            lines_all = [x.strip() for x in text.split("\n") if x.strip()]
            total_all = len(lines_all)
            if total_all == 0:
                return _resp(400, {"error": "No tracks to import"})

            # прогресс_id один и тот же для всего импорта
            progress_id = f"{nickname}:favorites"

            # если offset=0 — стартуем прогресс (или перезапускаем)
            if offset == 0:
                q_start = """
                    DECLARE $progress_id AS Utf8;
                    DECLARE $total AS Uint32;
                    UPSERT INTO import_progress (progress_id, status, done, total, current, updated_at)
                    VALUES ($progress_id, 'running', 0, $total, '', CurrentUtcTimestamp());
                """
                _ydb_retry(
                    lambda: session.transaction().execute(
                        _prepare(session, q_start),
                        {"$progress_id": progress_id, "$total": total_all},
                        commit_tx=True,
                    )
                )

            # вырезаем батч
            batch = lines_all[offset: offset + batch_size]
            if not batch:
                # уже всё сделано
                q_finish = """
                    DECLARE $progress_id AS Utf8;
                    UPDATE import_progress
                    SET status = 'done', current = '✅ Done', updated_at = CurrentUtcTimestamp()
                    WHERE progress_id = $progress_id;
                """
                _ydb_retry(
                    lambda: session.transaction().execute(
                        _prepare(session, q_finish),
                        {"$progress_id": progress_id},
                        commit_tx=True,
                    )
                )
                return _resp(200, {
                    "message": "import favorites complete",
                    "total": total_all,
                    "added": 0,
                    "failed": 0,
                    "errors": [],
                    "offset": offset,
                    "next_offset": offset,
                    "done": True
                })

            # отдельная сессия (чтобы не словить странности при повторных вызовах)
            local_session = _ydb_session()

            q_like = """
                DECLARE $nickname AS Utf8;
                DECLARE $track_id AS Utf8;
                DECLARE $title AS Utf8;
                DECLARE $artist AS Utf8;
                DECLARE $image AS Utf8;
                DECLARE $preview AS Utf8;
                DECLARE $source AS Utf8;
                DECLARE $external_id AS Utf8;

                DECLARE $artist_id AS Utf8;
                DECLARE $album_id AS Utf8;
                DECLARE $album_title AS Utf8;
                DECLARE $album_year AS Utf8;

                DECLARE $owner_id AS Utf8;
                DECLARE $audio_id AS Utf8;
                DECLARE $access_key AS Utf8;

                UPSERT INTO user_favorites
                (nickname, track_id, title, artist, image, preview, liked_at, source, external_id,
                 artist_id, album_id, album_title, album_year,
                 owner_id, audio_id, access_key)
                VALUES
                ($nickname, $track_id, $title, $artist, $image, $preview, CurrentUtcTimestamp(), $source, $external_id,
                 $artist_id, $album_id, $album_title, $album_year,
                 $owner_id, $audio_id, $access_key);
            """
            st_like = _prepare(local_session, q_like)

            added = 0
            failed = 0
            errors = []

            # сколько “в целом” будет done после этого батча
            done_after = offset

            for line in batch:
                done_after += 1

                # обновляем прогресс (в done пишем done_after)
                try:
                    q_upd = """
                        DECLARE $progress_id AS Utf8;
                        DECLARE $done AS Uint32;
                        DECLARE $current AS Utf8;
                        UPDATE import_progress
                        SET done = $done, current = $current, updated_at = CurrentUtcTimestamp()
                        WHERE progress_id = $progress_id;
                    """
                    _ydb_retry(
                        lambda: session.transaction().execute(
                            _prepare(session, q_upd),
                            {"$progress_id": progress_id, "$done": done_after, "$current": line},
                            commit_tx=True,
                        )
                    )
                except Exception:
                    pass

                # SEARCH
                try:
                    r = requests.get(
                        SEARCH_URL,
                        params={"service": service, "q": line, "type": "search"},
                        timeout=6
                    )
                    if r.status_code != 200:
                        failed += 1
                        errors.append(f"{line}: HTTP {r.status_code}")
                        continue

                    items = r.json()
                except Exception as e:
                    failed += 1
                    errors.append(f"{line}: search {type(e).__name__}")
                    continue

                if not items or not isinstance(items, list) or not isinstance(items[0], dict):
                    failed += 1
                    errors.append(f"{line}: not found")
                    continue

                track = items[0]

                # UPSERT
                try:
                    src = (track.get("source") or service or "").strip()
                    external_id = (track.get("id") or "").strip()

                    artist_id = (track.get("artist_id") or "").strip()
                    album_id = (track.get("album_id") or "").strip()
                    album_title = (track.get("album_title") or "").strip()
                    album_year = str(track.get("album_year") or "").strip()

                    owner_id = (track.get("owner_id") or "").strip()
                    audio_id = str(track.get("audio_id") or "").strip()
                    access_key = (track.get("access_key") or "").strip()

                    base_id = external_id or f"{track.get('title','')}:{track.get('artist','')}"
                    track_id = f"{src}:{base_id}" if src else base_id

                    local_session.transaction().execute(
                        st_like,
                        {
                            "$nickname": nickname,
                            "$track_id": track_id,
                            "$title": track.get("title", "") or "",
                            "$artist": track.get("artist", "") or "",
                            "$image": track.get("image", "") or "",
                            "$preview": track.get("preview", "") or "",
                            "$source": src,
                            "$external_id": external_id,

                            "$artist_id": artist_id,
                            "$album_id": album_id,
                            "$album_title": album_title,
                            "$album_year": album_year,

                            "$owner_id": owner_id,
                            "$audio_id": audio_id,
                            "$access_key": access_key,
                        },
                        commit_tx=True
                    )
                    added += 1
                except Exception as e:
                    failed += 1
                    errors.append(f"{line}: ydb {type(e).__name__}")

            next_offset = offset + len(batch)
            done_flag = next_offset >= total_all

            if done_flag:
                q_finish = """
                    DECLARE $progress_id AS Utf8;
                    DECLARE $current AS Utf8;
                    UPDATE import_progress
                    SET status = 'done', current = $current, updated_at = CurrentUtcTimestamp()
                    WHERE progress_id = $progress_id;
                """
                _ydb_retry(
                    lambda: session.transaction().execute(
                        _prepare(session, q_finish),
                        {"$progress_id": progress_id, "$current": "✅ Done"},
                        commit_tx=True,
                    )
                )

            return _resp(200, {
                "message": "import favorites batch complete",
                "total": total_all,
                "added": added,
                "failed": failed,
                "errors": errors[:30],
                "offset": offset,
                "next_offset": next_offset,
                "done": done_flag,
                "progress_id": progress_id
            })





        # -----------------------------
        #     IMPORT TEXT PLAYLIST (улучшенный + диагностика)
        # -----------------------------
        elif action == "import_playlist_text":
            import base64 as _b64

            DEFAULT_SEARCH_URL = "https://functions.yandexcloud.net/d4e09khm9p5t3cu2oq22"

            raw = (os.getenv("SEARCH_BACKEND_URL", "") or "").strip()

            # 1) прямой URL
            # 2) base64(url)
            # 3) пусто -> DEFAULT
            if raw.startswith("http://") or raw.startswith("https://"):
                SEARCH_URL = raw.strip()
            elif raw:
                try:
                    SEARCH_URL = _b64.b64decode(raw).decode().strip()
                except Exception as e:
                    print("SEARCH_BACKEND_URL base64 decode error:", type(e).__name__, str(e))
                    SEARCH_URL = DEFAULT_SEARCH_URL
            else:
                SEARCH_URL = DEFAULT_SEARCH_URL

            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()
            text = (body.get("text") or "").strip()
            service = (body.get("service") or "vkmusic").strip().lower()

            if not token or not playlist_id or not text:
                return _resp(400, {"error": "token, playlist_id, text required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            # Проверяем существование плейлиста
            q_check = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                SELECT playlist_id FROM user_playlists
                WHERE nickname = $nickname AND playlist_id = $playlist_id;
            """
            st_check = _prepare(session, q_check)
            res_check = _ydb_retry(
                lambda: session.transaction().execute(
                    st_check, {"$nickname": nickname, "$playlist_id": playlist_id}, commit_tx=True
                )
            )
            if not res_check or len(res_check[0].rows) == 0:
                return _resp(404, {"error": "Playlist not found"})

            lines = [x.strip() for x in text.split("\n") if x.strip()]
            if not lines:
                return _resp(400, {"error": "No tracks to import"})

            # Удаляем старые треки
            q_del = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                DELETE FROM playlist_real_tracks
                WHERE nickname = $nickname AND playlist_id = $playlist_id;
            """
            st_del = _prepare(session, q_del)
            _ydb_retry(
                lambda: session.transaction().execute(
                    st_del, {"$nickname": nickname, "$playlist_id": playlist_id}, commit_tx=True
                )
            )

            # Прогресс
            progress_id = f"{nickname}:{playlist_id}"
            q_start_progress = """
                DECLARE $progress_id AS Utf8;
                DECLARE $total AS Uint32;
                UPSERT INTO import_progress (progress_id, status, done, total, current, updated_at)
                VALUES ($progress_id, 'running', 0, $total, '', CurrentUtcTimestamp());
            """
            st_start = _prepare(session, q_start_progress)
            _ydb_retry(
                lambda: session.transaction().execute(
                    st_start, {"$progress_id": progress_id, "$total": len(lines)}, commit_tx=True
                )
            )

            print("IMPORT START", {
                "nickname": nickname,
                "playlist_id": playlist_id,
                "service": service,
                "lines": len(lines),
                "SEARCH_URL": SEARCH_URL
            })

            index = 1
            st_update = _prepare(session, """
                    DECLARE $progress_id AS Utf8;
                    DECLARE $done AS Uint32;
                    DECLARE $current AS Utf8;
                    UPDATE import_progress
                    SET done = $done, current = $current, updated_at = CurrentUtcTimestamp()
                    WHERE progress_id = $progress_id;
                """)

            st_ins = _prepare(session, """
                        DECLARE $nickname AS Utf8;
                        DECLARE $playlist_id AS Utf8;
                        DECLARE $track_index AS Uint32;
                        DECLARE $title AS Utf8;
                        DECLARE $artist AS Utf8;
                        DECLARE $image AS Utf8;
                        DECLARE $preview AS Utf8;
                        DECLARE $source AS Utf8;
                        DECLARE $external_id AS Utf8;
                        DECLARE $album_id AS Utf8;
                        DECLARE $album_title AS Utf8;
                        DECLARE $album_year AS Utf8;
                        DECLARE $artist_id AS Utf8;
                        DECLARE $owner_id AS Utf8;
                        DECLARE $audio_id AS Utf8;
                        DECLARE $access_key AS Utf8;

                        UPSERT INTO playlist_real_tracks
                        (nickname, playlist_id, track_index, title, artist, image, preview, source, external_id,
                         album_id, album_title, album_year, artist_id, owner_id, audio_id, access_key)
                        VALUES
                        ($nickname, $playlist_id, $track_index, $title, $artist, $image, $preview, $source, $external_id,
                         $album_id, $album_title, $album_year, $artist_id, $owner_id, $audio_id, $access_key);
                    """)
            for line in lines:
                # update progress
                _ydb_retry(
                    lambda: session.transaction().execute(
                        st_update,
                        {"$progress_id": progress_id, "$done": index, "$current": line},
                        commit_tx=True,
                    )
                )

                items = []
                try:
                    if not SEARCH_URL:
                        raise Exception("SEARCH_URL is empty")

                    r = requests.get(
                        SEARCH_URL,
                        params={"service": service, "q": line, "type": "search"},
                        timeout=10
                    )

                    if r.status_code != 200:
                        print("SEARCH HTTP ERROR", r.status_code, r.text[:300])
                        items = []
                    else:
                        try:
                            items = r.json()
                        except Exception:
                            print("SEARCH NOT JSON", r.text[:300])
                            items = []

                except Exception as e:
                    print(f"{service} search error:", type(e).__name__, str(e))
                    items = []

                if items and isinstance(items, list):
                    track = items[0]

                    _ydb_retry(
                        lambda: session.transaction().execute(
                            st_ins,
                            {
                            "$nickname": nickname,
                            "$playlist_id": playlist_id,
                            "$track_index": index,
                            "$title": track.get("title", "") or "",
                            "$artist": track.get("artist", "") or "",
                            "$image": track.get("image", "") or "",
                            "$preview": track.get("preview", "") or "",
                            "$source": (track.get("source") or service) or service,
                            "$external_id": track.get("id", "") or "",
                            "$album_id": track.get("album_id", "") or "",
                            "$album_title": track.get("album_title", "") or "",
                            "$album_year": str(track.get("album_year", "")).strip() if track.get("album_year") else "",
                            "$artist_id": track.get("artist_id", "") or "",
                            "$owner_id": track.get("owner_id", "") or "",
                            "$audio_id": str(track.get("audio_id", "") or ""),
                            "$access_key": track.get("access_key", "") or "",
                            },
                            commit_tx=True,
                        )
                    )

                index += 1

            q_finish_progress = """
                DECLARE $progress_id AS Utf8;
                UPDATE import_progress
                SET status = 'done', updated_at = CurrentUtcTimestamp()
                WHERE progress_id = $progress_id;
            """
            st_finish = _prepare(session, q_finish_progress)
            _ydb_retry(lambda: session.transaction().execute(st_finish, {"$progress_id": progress_id}, commit_tx=True))

            return _resp(200, {"message": "import complete", "total": len(lines), "progress_id": progress_id})



        # -----------------------------
        #   GET IMPORT PROGRESS (из YDB)
        # -----------------------------
        elif action == "playlist_import_progress":
            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()
            
            if not token or not playlist_id:
                return _resp(400, {"error": "token & playlist_id required"})
            
            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")
            
            progress_id = f"{nickname}:{playlist_id}"
            
            q = """
                DECLARE $progress_id AS Utf8;
                SELECT status, done, total, current 
                FROM import_progress 
                WHERE progress_id = $progress_id;
            """
            st = session.prepare(q)
            res = session.transaction().execute(st, {"$progress_id": progress_id}, commit_tx=True)
            
            if not res or len(res[0].rows) == 0:
                return _resp(200, {"status": "none"})
            
            row = res[0].rows[0]
            return _resp(200, {
                "status": row.status,
                "done": row.done,
                "total": row.total,
                "current": row.current
            })

        # -----------------------------
        #   GET REAL PLAYLIST TRACKS (с полными данными)
        # -----------------------------
        elif action == "get_real_playlist":
            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()

            if not token or not playlist_id:
                return _resp(400, {"error": "token & playlist_id required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                SELECT 
                    track_index, title, artist, image, preview, source, external_id,
                    album_id, album_title, album_year, artist_id,
                    owner_id, audio_id, access_key
                FROM playlist_real_tracks
                WHERE nickname = $nickname AND playlist_id = $playlist_id
                ORDER BY track_index;
            """
            st = session.prepare(q)
            res = session.transaction().execute(st, {"$nickname": nickname, "$playlist_id": playlist_id}, commit_tx=True)

            items = []
            for row in res[0].rows:
                # Преобразуем год в число
                year_int = None
                try:
                    y = (row.album_year or "").strip()
                    year_int = int(y) if y else None
                except Exception:
                    year_int = None

                items.append({
                    "index": row.track_index,
                    "title": row.title,
                    "artist": row.artist,
                    "image": row.image,
                    "preview": row.preview,
                    "source": row.source,
                    "external_id": row.external_id,
                    "album_id": row.album_id or "",
                    "album_title": row.album_title or "",
                    "album_year": year_int,
                    "artist_id": row.artist_id or "",
                    "owner_id": row.owner_id or "",
                    "audio_id": row.audio_id or "",
                    "access_key": row.access_key or "",
                })

            return _resp(200, {"tracks": items})

        # -----------------------------
        #   DELETE PLAYLIST
        # -----------------------------
        elif action == "delete_playlist":
            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()
            
            if not token or not playlist_id:
                return _resp(400, {"error": "token & playlist_id required"})
            
            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")
            
            try:
                # Удаляем все связанные данные в одной транзакции
                q1 = """
                    DECLARE $nickname AS Utf8;
                    DECLARE $playlist_id AS Utf8;
                    DELETE FROM playlist_real_tracks
                    WHERE nickname = $nickname AND playlist_id = $playlist_id;
                """
                
                q2 = """
                    DECLARE $nickname AS Utf8;
                    DECLARE $playlist_id AS Utf8;
                    DELETE FROM playlist_tracks
                    WHERE nickname = $nickname AND playlist_id = $playlist_id;
                """
                
                q3 = """
                    DECLARE $nickname AS Utf8;
                    DECLARE $playlist_id AS Utf8;
                    DELETE FROM user_playlists
                    WHERE nickname = $nickname AND playlist_id = $playlist_id;
                """
                
                # Удаляем прогресс импорта
                progress_id = f"{nickname}:{playlist_id}"
                q4 = """
                    DECLARE $progress_id AS Utf8;
                    DELETE FROM import_progress
                    WHERE progress_id = $progress_id;
                """
                
                # Выполняем все запросы
                session.transaction().execute([
                    session.prepare(q1),
                    session.prepare(q2),
                    session.prepare(q3),
                    session.prepare(q4)
                ], commit_tx=True)
                
                return _resp(200, {"message": "playlist deleted"})
                
            except Exception as e:
                print("Delete playlist error:", e)
                return _resp(500, {"error": f"Delete failed: {str(e)}"})

        # -----------------------------
        #   UPDATE PLAYLIST TITLE
        # -----------------------------
        elif action == "update_playlist":
            token = body.get("token")
            playlist_id = (body.get("playlist_id") or "").strip()
            title = (body.get("title") or "").strip()
            
            if not token or not playlist_id:
                return _resp(400, {"error": "token & playlist_id required"})
            
            if not title:
                return _resp(400, {"error": "title is required"})
            
            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")
            
            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $playlist_id AS Utf8;
                DECLARE $title AS Utf8;
                UPDATE user_playlists 
                SET title = $title 
                WHERE nickname = $nickname AND playlist_id = $playlist_id;
            """
            st = session.prepare(q)
            session.transaction().execute(
                st,
                {"$nickname": nickname, "$playlist_id": playlist_id, "$title": title},
                commit_tx=True
            )
            
            return _resp(200, {"message": "playlist updated", "title": title})

        # -----------------------------
        #           FAVORITES
        # -----------------------------
        elif action == "like_track":
            token = body.get("token")
            track = body.get("track")
            if not token or not track:
                return _resp(400, {"error": "token & track required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            source = (track.get("source") or "").strip()
            external_id = (track.get("id") or "").strip()

            # ✅ мета для переходов
            artist_id = (track.get("artist_id") or "").strip()
            album_id = (track.get("album_id") or "").strip()
            album_title = (track.get("album_title") or "").strip()

            _raw_year = track.get("album_year")
            album_year = str(_raw_year).strip() if _raw_year is not None and str(_raw_year).strip() else ""

            # ✅ VK extras
            owner_id = (track.get("owner_id") or "").strip()
            audio_id = str(track.get("audio_id") or "").strip()
            access_key = (track.get("access_key") or "").strip()

            base_id = external_id or f"{track.get('title','')}:{track.get('artist','')}"
            track_id = f"{source}:{base_id}" if source else base_id

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $track_id AS Utf8;
                DECLARE $title AS Utf8;
                DECLARE $artist AS Utf8;
                DECLARE $image AS Utf8;
                DECLARE $preview AS Utf8;
                DECLARE $source AS Utf8;
                DECLARE $external_id AS Utf8;

                DECLARE $artist_id AS Utf8;
                DECLARE $album_id AS Utf8;
                DECLARE $album_title AS Utf8;
                DECLARE $album_year AS Utf8;

                DECLARE $owner_id AS Utf8;
                DECLARE $audio_id AS Utf8;
                DECLARE $access_key AS Utf8;

                UPSERT INTO user_favorites
                (nickname, track_id, title, artist, image, preview, liked_at, source, external_id,
                 artist_id, album_id, album_title, album_year,
                 owner_id, audio_id, access_key)
                VALUES
                ($nickname, $track_id, $title, $artist, $image, $preview, CurrentUtcTimestamp(), $source, $external_id,
                 $artist_id, $album_id, $album_title, $album_year,
                 $owner_id, $audio_id, $access_key);
            """
            st = session.prepare(q)
            session.transaction().execute(
                st,
                {
                    "$nickname": nickname,
                    "$track_id": track_id,
                    "$title": track.get("title", ""),
                    "$artist": track.get("artist", ""),
                    "$image": track.get("image", ""),
                    "$preview": track.get("preview", ""),  # как пришло при лайке
                    "$source": source,
                    "$external_id": external_id,

                    "$artist_id": artist_id,
                    "$album_id": album_id,
                    "$album_title": album_title,
                    "$album_year": album_year,

                    "$owner_id": owner_id,
                    "$audio_id": audio_id,
                    "$access_key": access_key,
                },
                commit_tx=True
            )
            return _resp(200, {"message": "liked", "track_id": track_id})

        elif action == "remove_like":
            token = body.get("token")
            track_id = body.get("track_id")
            if not token or not track_id:
                return _resp(400, {"error": "token & track_id required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $track_id AS Utf8;
                DELETE FROM user_favorites
                WHERE nickname = $nickname AND track_id = $track_id;
            """
            st = session.prepare(q)
            session.transaction().execute(
                st, {"$nickname": nickname, "$track_id": track_id},
                commit_tx=True
            )
            return _resp(200, {"message": "unliked"})

        # ✅ ЛЕНИВАЯ ЗАГРУЗКА: обновляем ссылку только когда юзер нажал play
        elif action == "get_stream":
            token = body.get("token")
            track_id = (body.get("track_id") or "").strip()
            if not token or not track_id:
                return _resp(400, {"error": "token & track_id required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            # достаём трек
            q = """
                DECLARE $nickname AS Utf8;
                DECLARE $track_id AS Utf8;
                SELECT track_id, title, artist, preview, source, external_id
                FROM user_favorites
                WHERE nickname = $nickname AND track_id = $track_id;
            """
            st = session.prepare(q)
            res = session.transaction().execute(
                st, {"$nickname": nickname, "$track_id": track_id}, commit_tx=True
            )
            if not res or len(res[0].rows) == 0:
                return _resp(404, {"error": "Track not found"})

            row = res[0].rows[0]
            src = (row.source or "").lower().strip()
            preview = row.preview or ""

            # yandex → refresh
            yandex_token_env = (os.getenv("YANDEXMUSIC_TOKEN", "") or "").strip()
            if src in ("yandex", "yandexmusic", "itunes", "ya") and yandex_token_env:
                yid = None
                ext = (row.external_id or "").strip()

                if ext:
                    try:
                        yid = int(ext)
                    except Exception:
                        yid = None

                if yid is None:
                    yid = _search_yandex_track_id_by_meta(
                        title=(row.title or ""),
                        artist=(row.artist or ""),
                        token=yandex_token_env
                    )
                    if yid is not None:
                        try:
                            q_upd_id = """
                                DECLARE $nickname AS Utf8;
                                DECLARE $track_id AS Utf8;
                                DECLARE $external_id AS Utf8;
                                UPDATE user_favorites SET external_id = $external_id
                                WHERE nickname = $nickname AND track_id = $track_id;
                            """
                            st_upd_id = session.prepare(q_upd_id)
                            session.transaction().execute(
                                st_upd_id,
                                {"$nickname": nickname, "$track_id": track_id, "$external_id": str(yid)},
                                commit_tx=True
                            )
                        except Exception as e:
                            print("External_id update error:", e)

                if yid is not None:
                    fresh = _get_yandex_stream(yid, yandex_token_env)
                    if fresh:
                        preview = fresh
                        try:
                            q_upd = """
                                DECLARE $nickname AS Utf8;
                                DECLARE $track_id AS Utf8;
                                DECLARE $preview AS Utf8;
                                UPDATE user_favorites SET preview = $preview
                                WHERE nickname = $nickname AND track_id = $track_id;
                            """
                            st_upd = session.prepare(q_upd)
                            session.transaction().execute(
                                st_upd,
                                {"$nickname": nickname, "$track_id": track_id, "$preview": preview},
                                commit_tx=True
                            )
                        except Exception as e:
                            print("Preview update error:", e)

            # soundcloud → refresh через SEARCH backend
            elif src in ("soundcloud", "sc"):
                fresh = _search_soundcloud_preview_by_meta(
                    title=(row.title or ""),
                    artist=(row.artist or "")
                )
                if fresh:
                    preview = fresh
                    try:
                        q_upd = """
                            DECLARE $nickname AS Utf8;
                            DECLARE $track_id AS Utf8;
                            DECLARE $preview AS Utf8;
                            UPDATE user_favorites SET preview = $preview
                            WHERE nickname = $nickname AND track_id = $track_id;
                        """
                        st_upd = session.prepare(q_upd)
                        session.transaction().execute(
                            st_upd,
                            {"$nickname": nickname, "$track_id": track_id, "$preview": preview},
                            commit_tx=True
                        )
                    except Exception as e:
                        print("SoundCloud preview update error:", e)

            return _resp(200, {"track_id": track_id, "preview": preview, "source": row.source})


        # ✅ Список избранного: refresh ТОЛЬКО если запросили 1 трек (only_track_id)
        elif action == "list_favorites":
            token = body.get("token")
            if not token:
                return _resp(400, {"error": "Token required"})

            decoded, err = _decode_token(token)
            if err:
                return err
            nickname = decoded.get("nickname")

            only_track_id = (body.get("only_track_id") or "").strip()

            # ✅ Если запрашивается конкретный трек — делаем точечный запрос
            if only_track_id:
                q = """
                    DECLARE $nickname AS Utf8;
                    DECLARE $track_id AS Utf8;
                    SELECT
                      track_id, title, artist, image, preview, source, external_id,
                      artist_id, album_id, album_title, album_year,
                      owner_id, audio_id, access_key
                    FROM user_favorites
                    WHERE nickname = $nickname AND track_id = $track_id;
                """
                st = session.prepare(q)
                res = session.transaction().execute(
                    st, 
                    {"$nickname": nickname, "$track_id": only_track_id}, 
                    commit_tx=True
                )
                
                if not res or len(res[0].rows) == 0:
                    return _resp(404, {"error": "Track not found"})
                
                row = res[0].rows[0]
                
                # ✅ album_year -> Int или null (чтобы Moshi не падал)
                year_int = None
                try:
                    y = (row.album_year or "").strip()
                    year_int = int(y) if y else None
                except Exception:
                    year_int = None

                item = {
                    "id": row.track_id,
                    "title": row.title,
                    "artist": row.artist,
                    "image": row.image,
                    "preview": (row.preview or ""),
                    "source": row.source,
                    "externalId": row.external_id,
                    "artist_id": row.artist_id,
                    "album_id": row.album_id,
                    "album_title": row.album_title,
                    "album_year": year_int,
                    "owner_id": row.owner_id,
                    "audio_id": row.audio_id,
                    "access_key": row.access_key,
                }
                
                # ✅ Refresh ТОЛЬКО для Яндекса + SoundCloud (если запросили 1 трек)
                src = (row.source or "").lower().strip()

                # -------------------
                # YANDEX refresh
                # -------------------
                if src in ("yandex", "yandexmusic", "itunes", "ya"):
                    yandex_token_env = (os.getenv("YANDEXMUSIC_TOKEN", "") or "").strip()
                    if yandex_token_env:
                        yid = None
                        ext = (row.external_id or "").strip()

                        # 1) external_id если есть
                        if ext:
                            try:
                                yid = int(ext)
                            except Exception:
                                yid = None

                        # 2) иначе — ищем по метаданным
                        if yid is None:
                            yid = _search_yandex_track_id_by_meta(
                                title=(row.title or ""),
                                artist=(row.artist or ""),
                                token=yandex_token_env
                            )
                            if yid is not None:
                                # сохраним найденный external_id
                                try:
                                    q_upd_id = """
                                        DECLARE $nickname AS Utf8;
                                        DECLARE $track_id AS Utf8;
                                        DECLARE $external_id AS Utf8;
                                        UPDATE user_favorites SET external_id = $external_id
                                        WHERE nickname = $nickname AND track_id = $track_id;
                                    """
                                    st_upd_id = session.prepare(q_upd_id)
                                    session.transaction().execute(
                                        st_upd_id,
                                        {"$nickname": nickname, "$track_id": row.track_id, "$external_id": str(yid)},
                                        commit_tx=True
                                    )
                                except Exception as e:
                                    print("External_id update error:", e)

                        # 3) если нашли id — получаем свежую ссылку и сохраняем
                        if yid is not None:
                            fresh = _get_yandex_stream(yid, yandex_token_env)
                            if fresh:
                                item["preview"] = fresh
                                try:
                                    q_upd = """
                                        DECLARE $nickname AS Utf8;
                                        DECLARE $track_id AS Utf8;
                                        DECLARE $preview AS Utf8;
                                        UPDATE user_favorites SET preview = $preview
                                        WHERE nickname = $nickname AND track_id = $track_id;
                                    """
                                    st_upd = session.prepare(q_upd)
                                    session.transaction().execute(
                                        st_upd,
                                        {"$nickname": nickname, "$track_id": row.track_id, "$preview": fresh},
                                        commit_tx=True
                                    )
                                except Exception as e:
                                    print("Preview update error:", e)

                # -------------------
                # SOUNDCLOUD refresh
                # -------------------
                elif src in ("soundcloud", "sc"):
                    fresh_sc = _search_soundcloud_preview_by_meta(
                        title=(row.title or ""),
                        artist=(row.artist or "")
                    )
                    if fresh_sc:
                        item["preview"] = fresh_sc
                        try:
                            q_upd_sc = """
                                DECLARE $nickname AS Utf8;
                                DECLARE $track_id AS Utf8;
                                DECLARE $preview AS Utf8;
                                UPDATE user_favorites SET preview = $preview
                                WHERE nickname = $nickname AND track_id = $track_id;
                            """
                            st_upd_sc = session.prepare(q_upd_sc)
                            session.transaction().execute(
                                st_upd_sc,
                                {"$nickname": nickname, "$track_id": row.track_id, "$preview": fresh_sc},
                                commit_tx=True
                            )
                        except Exception as e:
                            print("SoundCloud preview update error:", e)


                # ✅ Возвращаем ТОЛЬКО этот трек (в массиве для совместимости)
                return _resp(200, [item])

            # ✅ ЕСЛИ only_track_id НЕ передан — вернуть весь список избранного
            q_all = """
                DECLARE $nickname AS Utf8;
                SELECT
                  track_id, title, artist, image, preview, source, external_id,
                  artist_id, album_id, album_title, album_year,
                  owner_id, audio_id, access_key
                FROM user_favorites
                WHERE nickname = $nickname
                ORDER BY liked_at DESC;
            """
            st_all = session.prepare(q_all)
            res_all = session.transaction().execute(
                st_all, {"$nickname": nickname}, commit_tx=True
            )

            items = []
            for row in res_all[0].rows:
                year_int = None
                try:
                    y = (row.album_year or "").strip()
                    year_int = int(y) if y else None
                except Exception:
                    year_int = None

                items.append({
                    "id": row.track_id,
                    "title": row.title,
                    "artist": row.artist,
                    "image": row.image,
                    "preview": (row.preview or ""),
                    "source": row.source,
                    "externalId": row.external_id,

                    "artist_id": row.artist_id,
                    "album_id": row.album_id,
                    "album_title": row.album_title,
                    "album_year": year_int,

                    "owner_id": row.owner_id,
                    "audio_id": row.audio_id,
                    "access_key": row.access_key,
                })

            return _resp(200, items)

                # если action не совпал ни с одним из elif выше
        return _resp(400, {"error": f"Unknown action: {action}"})

    except Exception as e:
        print("❌ Unhandled error:", type(e).__name__, str(e))
        traceback.print_exc()
        return _resp(500, {"error": "Internal server error", "detail": str(e)})



