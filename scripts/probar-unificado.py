"""Prueba de lectura autenticada para el backend unificado; no crea datos de negocio."""
import argparse
import concurrent.futures
import json
from pathlib import Path
import time
import urllib.request
from urllib.parse import urlsplit


def load_env(path):
    values = {}
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def check(base, env_file, count):
    origin = urlsplit(base)
    if origin.scheme not in ("http", "https") or not origin.hostname or origin.username or origin.password or origin.query or origin.fragment or origin.path not in ("", "/"):
        raise ValueError("Indica solo el origen HTTP/HTTPS del servidor.")
    env = load_env(env_file)
    base = base.rstrip("/")
    credentials = {"identification": env["MASTER_IDENTIFICATION"], "password": env["MASTER_PASSWORD"]}
    request = urllib.request.Request(base + "/api/v1/auth/login", data=json.dumps(credentials).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=20) as response:
        login = json.load(response)
    token = login.get("accessToken") or login.get("token")
    if not token:
        raise RuntimeError("El login no devolvió un token")
    paths = ["/api/auth/me", "/api/products", "/api/retazos/products", "/api/pedidos/orders", "/api/ubicaciones/spaces", "/api/v1/logistica/rutas"]

    def read(index):
        request = urllib.request.Request(base + paths[index % len(paths)], headers={"Authorization": "Bearer " + token})
        started = time.monotonic()
        with urllib.request.urlopen(request, timeout=30) as response:
            assert response.status == 200
            json.load(response)
        return time.monotonic() - started

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            elapsed = list(pool.map(read, range(count)))
    finally:
        request = urllib.request.Request(base + "/api/auth/logout", data=b"", headers={"Authorization": "Bearer " + token}, method="POST")
        with urllib.request.urlopen(request, timeout=20) as response:
            assert response.status == 204
    print(json.dumps({"passed": True, "url": base, "authenticatedReads": count, "concurrency": 4, "maxResponseSeconds": round(max(elapsed), 3), "businessDataCreated": False, "testSessionClosed": True}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://localhost:8090")
    parser.add_argument("--env-file", type=Path, default=Path(__file__).resolve().parents[1] / ".env")
    parser.add_argument("--requests", type=int, default=120)
    args = parser.parse_args()
    if args.requests < 1:
        parser.error("--requests debe ser positivo")
    check(args.url, args.env_file, args.requests)
