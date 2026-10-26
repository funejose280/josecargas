"""Consulta de jugadores de Free Fire por ID, usando la API de 0xMe (FreeFire-Api).

Hace login con cuentas guest del servidor correspondiente y pide el perfil público
del jugador (nombre, nivel, región). No usa ni guarda datos del usuario.
"""
import os
import time

from ffapi.Utilities.until import load_accounts
from ffapi.Api.Account import get_garena_token, get_major_login
from ffapi.Api.InGame import get_player_personal_show

# Servidores (cuentas guest) donde se busca el ID, en orden.
LOOKUP_SERVERS = [s.strip().upper() for s in os.environ.get("LOOKUP_SERVERS", "US").split(",") if s.strip()]

_accounts = None
_sessions = {}          # server -> (timestamp, token, serverUrl)
SESSION_TTL = 20 * 60   # reutiliza el login mientras la instancia siga "caliente"


def _get_accounts():
    global _accounts
    if _accounts is None:
        _accounts = load_accounts()
    return _accounts


def _login(server, force=False):
    cached = _sessions.get(server)
    if cached and not force and time.time() - cached[0] < SESSION_TTL:
        return cached[1], cached[2]
    acc = _get_accounts().get(server)
    if not acc:
        raise RuntimeError(f"No hay cuenta configurada para el servidor {server}")
    tok = get_garena_token(acc["uid"], acc["password"])
    if not tok or "access_token" not in tok or "open_id" not in tok:
        raise RuntimeError("Garena rechazó el login de la cuenta del servidor " + server)
    major = get_major_login(tok["access_token"], tok["open_id"])
    if not major or "token" not in major or "serverUrl" not in major:
        raise RuntimeError("Falló el login principal en " + server)
    _sessions[server] = (time.time(), major["token"], major["serverUrl"])
    return major["token"], major["serverUrl"]


def _basic(show):
    if not isinstance(show, dict):
        return None
    return show.get("basicinfo") or show.get("basicInfo")


def lookup_player(uid):
    """Devuelve (player|None, intentos). player = {name, level, region, server}."""
    attempts = []
    for server in LOOKUP_SERVERS:
        info = {"server": server}
        try:
            token, url = _login(server)
            show = get_player_personal_show(url, token, int(uid))
            if show is None:  # el token pudo vencer: reintentar una vez con login nuevo
                token, url = _login(server, force=True)
                show = get_player_personal_show(url, token, int(uid))
            basic = _basic(show)
            if basic and basic.get("nickname"):
                info.update(found=True, region=basic.get("region"))
                attempts.append(info)
                player = {
                    "name": basic["nickname"],
                    "level": basic.get("level"),
                    "region": str(basic.get("region") or "").upper(),
                    "server": server,
                }
                # Si la respuesta del juego/proveedor ya incluye una URL de avatar,
                # la exponemos. No se puede convertir un avatarId en foto sin un catálogo oficial.
                for key in ("profile_image", "profileImage", "avatar_url", "avatarUrl", "image_url", "imageUrl", "photo"):
                    value = basic.get(key)
                    if isinstance(value, str) and value.startswith("https://"):
                        player["profile_image"] = value
                        break
                return player, attempts
            info.update(found=False, note="sin datos para ese ID en este servidor",
                        keys=sorted(show.keys()) if isinstance(show, dict) else str(type(show)))
        except Exception as e:  # noqa: BLE001
            info.update(found=False, error=str(e)[:300])
        attempts.append(info)
    return None, attempts
