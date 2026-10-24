"""Verificador de ID de Free Fire — solo cuentas de Latinoamérica.

Ruta: /api/verify-id?uid=XXXXXXXX   (agregá &debug=1 para ver el detalle técnico)
Usa la API de 0xMe (carpeta ffapi/). Este archivo solo importa librerías estándar al
arrancar; lo pesado se carga recién cuando llega una consulta.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error
from urllib.parse import parse_qs, urlencode

ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

# Regiones del perfil que se consideran "Latinoamérica" (ajustable con LATAM_REGIONS="SAC,US,...")
LATAM_REGIONS = [r.strip().upper() for r in os.environ.get("LATAM_REGIONS", "SAC,BR,US").split(",") if r.strip()]

_hits = {}
_cache = {}
CACHE_SECONDS = 300


def _rate_limited(ip):
    now = time.time()
    recent = [t for t in _hits.get(ip, []) if now - t < 60]
    recent.append(now)
    _hits[ip] = recent
    return len(recent) > 12



def _external_ffinfo_lookup(uid):
    """Consulta el endpoint FFINFO configurado por el propietario, sin exponer la clave al navegador.

    FFINFO_API_URL debe ser la URL COMPLETA del endpoint de consulta (incluida la ruta).
    La clave se lee exclusivamente desde la variable de entorno FFINFO_API_KEY.
    """
    # Endpoint documentado de SiamBhau Free Fire Info. Se puede sobrescribir
    # FFINFO_API_URL desde Vercel si el proveedor cambia la ruta.
    endpoint = (os.environ.get("FFINFO_API_URL") or
                "https://siambhau69.eu.cc/freefireinfo/bhau").strip()
    api_key = (os.environ.get("FFINFO_API_KEY") or "").strip()
    if not api_key:
        return None  # sin clave configurada: usar el verificador integrado de respaldo

    id_param = (os.environ.get("FFINFO_ID_PARAM") or "uid").strip() or "uid"
    # La documentación del proveedor requiere `key` como parámetro de consulta,
    # además de UID y región. La solicitud se realiza solo desde el servidor.
    params = {id_param: uid, "region": (os.environ.get("FFINFO_REGION") or "SAC").strip().upper(), "key": api_key}
    separator = "&" if "?" in endpoint else "?"
    url = endpoint + separator + urlencode(params)
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "JoseRecargas-IDVerifier/1.0",
        },
        method="GET",
    )
    timeout = float(os.environ.get("FFINFO_TIMEOUT_SECONDS", "10"))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        # No devolver al navegador la URL, headers ni la clave.
        raise RuntimeError(f"FFINFO respondió HTTP {e.code}") from None
    except (urllib.error.URLError, TimeoutError, ValueError) as e:
        raise RuntimeError("No se pudo consultar el endpoint FFINFO: " + str(e)[:160]) from None

    if not isinstance(payload, dict):
        raise RuntimeError("La respuesta FFINFO no tiene formato JSON de objeto")

    # Normaliza formatos comunes sin asumir un único esquema del proveedor.
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    # SiamBhau /freefireinfo/bhau devuelve los datos dentro de `basicInfo`.
    basic = data.get("basicInfo") or data.get("basicinfo") or data
    if not isinstance(basic, dict):
        basic = data
    success = payload.get("success", payload.get("ok", data.get("success", data.get("ok"))))
    if success is False or payload.get("error"):
        return {"success": False, "code": "NOT_FOUND",
                "message": str(payload.get("message") or payload.get("error") or "No se pudo verificar ese ID.")}

    name = (basic.get("name") or basic.get("nickname") or basic.get("playerName") or
            basic.get("player_name") or data.get("name") or data.get("nickname"))
    region = basic.get("region") or data.get("region") or data.get("server") or data.get("country")
    level = basic.get("level") or basic.get("account_level") or data.get("level")
    returned_uid = str(basic.get("uid") or basic.get("accountId") or basic.get("account_id") or
                       data.get("uid") or data.get("user_id") or data.get("accountId") or uid)
    if not name:
        raise RuntimeError("La respuesta FFINFO no incluye el nombre del jugador; revisá el endpoint o su formato")
    region = str(region or "").upper()
    if region and region not in LATAM_REGIONS:
        return {"success": False, "code": "NOT_LATAM",
                "message": "Ese ID no pertenece al servidor de Latinoamérica. Solo hacemos recargas para cuentas LATAM."}
    result = {"success": True, "uid": returned_uid, "name": str(name), "region": region}
    if level is not None:
        result["level"] = level
    return result

def process(query_string, ip=""):
    """Devuelve (status_http, dict_respuesta)."""
    qs = parse_qs(query_string or "")
    uid = (qs.get("uid", [""])[0] or "").strip()
    debug = qs.get("debug", [""])[0] == "1"

    if not uid.isdigit() or not (6 <= len(uid) <= 15):
        return 400, {"success": False, "code": "BAD_ID", "message": "Ingresá un ID válido de entre 6 y 15 números."}

    if not debug and _rate_limited(ip):
        return 429, {"success": False, "code": "RATE_LIMIT", "message": "Demasiadas consultas seguidas. Esperá un minuto e intentá de nuevo."}

    if not debug:
        c = _cache.get(uid)
        if c and time.time() - c[0] < CACHE_SECONDS:
            return 200, c[1]

    # Si se configuró FFINFO_API_URL y FFINFO_API_KEY, consultar ese servicio primero.
    # Si no están configuradas, conservar el verificador integrado existente.
    if os.environ.get("FFINFO_API_KEY"):
        try:
            external_body = _external_ffinfo_lookup(uid)
            if external_body is not None:
                if external_body.get("success"):
                    _cache[uid] = (time.time(), external_body)
                return 200, external_body
        except Exception as e:  # noqa: BLE001
            print("FFINFO verify-id error:", repr(e))
            if debug:
                return 200, {"debug": True, "version": "ffinfo-proxy", "exception": repr(e)}
            return 502, {"success": False, "code": "UPSTREAM", "message": "No pudimos consultar el servicio de verificación. Revisá la configuración de FFINFO e intentá de nuevo."}

    try:
        from ffapi.lookup import lookup_player, LOOKUP_SERVERS  # carga diferida
        player, attempts = lookup_player(uid)
    except Exception as e:  # noqa: BLE001
        print("verify-id error:", repr(e))
        if debug:
            return 200, {"debug": True, "version": "v4-py", "exception": repr(e)}
        return 502, {"success": False, "code": "UPSTREAM", "message": "No pudimos consultar el servicio en este momento. Intentá de nuevo en unos minutos."}

    if debug:
        return 200, {
            "debug": True, "version": "v4-py",
            "servidoresConsultados": LOOKUP_SERVERS, "regionesLatamAceptadas": LATAM_REGIONS,
            "intentos": attempts, "jugador": player,
        }

    if player is None:
        if any("error" in a for a in attempts):
            print("verify-id intentos:", json.dumps(attempts, ensure_ascii=False))
            return 502, {"success": False, "code": "UPSTREAM", "message": "No pudimos consultar el servicio en este momento. Intentá de nuevo en unos minutos."}
        return 404, {"success": False, "code": "NOT_FOUND", "message": "No encontramos ese ID en el servidor de Latinoamérica. Revisalo e intentá de nuevo."}

    if player["region"] not in LATAM_REGIONS:
        return 200, {"success": False, "code": "NOT_LATAM", "message": "Ese ID no pertenece al servidor de Latinoamérica. Solo hacemos recargas para cuentas LATAM."}

    body = {"success": True, "uid": uid, "name": player["name"], "level": player["level"], "region": player["region"]}
    _cache[uid] = (time.time(), body)
    return 200, body


# --- Punto de entrada WSGI (Vercel detecta `app` en app.py automáticamente) ---
_STATUS = {200: "200 OK", 400: "400 Bad Request", 404: "404 Not Found", 429: "429 Too Many Requests", 502: "502 Bad Gateway"}


def _respond(start_response, status, body_bytes, content_type, cache="no-store"):
    start_response(_STATUS.get(status, f"{status} Error"), [
        ("Content-Type", content_type),
        ("Cache-Control", cache),
        ("Content-Length", str(len(body_bytes))),
    ])
    return [body_bytes]


def app(environ, start_response):
    path = (environ.get("PATH_INFO") or "/").rstrip("/") or "/"

    if path == "/api/verify-id":
        ip = (environ.get("HTTP_X_FORWARDED_FOR") or "").split(",")[0].strip()
        status, body = process(environ.get("QUERY_STRING", ""), ip)
        return _respond(start_response, status, json.dumps(body, ensure_ascii=False).encode("utf-8"),
                        "application/json; charset=utf-8")

    # Respaldo: si la plataforma no sirve la página por su cuenta, la sirve esta función.
    # (Solo index.html: nunca se exponen otros archivos del proyecto.)
    if path in ("/", "/index.html"):
        for candidate in (os.path.join(ROOT, "public", "index.html"), os.path.join(ROOT, "index.html")):
            if os.path.isfile(candidate):
                with open(candidate, "rb") as f:
                    return _respond(start_response, 200, f.read(), "text/html; charset=utf-8", "public, max-age=60")

    return _respond(start_response, 404, b'{"success":false,"code":"NOT_FOUND_ROUTE"}', "application/json; charset=utf-8")
