"""Comprueba assets, contrato DOM y conexión real con usuarios sin cambiar productos."""
import json
import re
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

root = Path(__file__).resolve().parent.parent
assets = root / "services/inventario-service/src/main/resources/static"
html = (assets / "index.html").read_text(encoding="utf-8")
source = (assets / "app.js").read_text(encoding="utf-8")
ids = set(re.findall(r'id="([^"]+)"', html))
references = set(re.findall(r"\$\('([^']+)'\)", source))
assert not references - ids, references - ids
config = dict(line.split("=", 1) for line in (root / ".env").read_text().splitlines()
              if line and not line.startswith("#") and "=" in line)
base = "http://localhost:" + config.get("INVENTARIO_PORT", "8092")

def request(path, method="GET", body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = Request(base + path, method=method, headers=headers,
                  data=json.dumps(body).encode() if body is not None else None)
    try:
        with urlopen(req, timeout=10) as response:
            return response.status, response.read()
    except HTTPError as error:
        return error.code, error.read()

for asset in ["/", "/app.js", "/style.css", "/actuator/health"]:
    status, content = request(asset)
    assert status == 200 and content, (asset, status)
assert request("/api/products")[0] == 401
assert request("/api/auth/login", "POST", {"identification": "INVALID-SMOKE", "password": "incorrecta"})[0] == 401
status, content = request("/api/auth/login", "POST", {
    "identification": config["MASTER_IDENTIFICATION"], "password": config["MASTER_PASSWORD"],
})
if status == 401:
    print("OK: assets, DOM, salud y autenticación real. Clave inicial cambiada: sesión del principal no comprobada.")
else:
    assert status == 200, status
    session = json.loads(content)
    token = session["accessToken"]
    try:
        assert request("/api/auth/me", token=token)[0] == 200
        assert request("/api/products", token=token)[0] == (403 if session["user"]["mustChangePassword"] else 200)
    finally:
        assert request("/api/auth/logout", "POST", token=token)[0] == 204
    assert request("/api/auth/me", token=token)[0] == 401
    print("OK: assets, DOM, salud, login, identidad y revocación entre inventario y usuarios")
