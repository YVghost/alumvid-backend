"""Verificación HTTP local: no modifica usuarios ni imprime credenciales."""
import json
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

root = Path(__file__).resolve().parent.parent
config = dict(line.split("=", 1) for line in (root / ".env").read_text().splitlines()
              if line and not line.startswith("#") and "=" in line)
base = "http://localhost:" + config.get("USUARIOS_PORT", "8091")

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

for asset in ["/", "/app.js", "/style.css"]:
    status, content = request(asset)
    assert status == 200 and content, (asset, status)
assert request("/api/admin/users")[0] == 401
status, content = request("/api/auth/login", "POST", {
    "identification": config["MASTER_IDENTIFICATION"],
    "password": config["MASTER_PASSWORD"],
})
assert status == 200, "El smoke test requiere la contraseña inicial del principal"
session = json.loads(content)
token = session["accessToken"]
try:
    assert request("/api/auth/me", token=token)[0] == 200
    assert request("/api/admin/users", token=token)[0] == (403 if session["user"]["mustChangePassword"] else 200)
finally:
    assert request("/api/auth/logout", "POST", token=token)[0] == 204
assert request("/api/auth/me", token=token)[0] == 401
print("OK: portal, assets, login, identidad, cambio obligatorio y cierre de sesión en Docker")
