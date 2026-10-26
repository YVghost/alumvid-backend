"""Prueba integral de la plataforma AlumVid a través del API Gateway (puerto 8080)."""
import json
import urllib.request
from urllib.error import HTTPError

GATEWAY_URL = "http://localhost:8080"

def do_request(path, method="GET", body=None, token=None):
    url = f"{GATEWAY_URL}{path}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            content = resp.read().decode("utf-8")
            return resp.status, content
    except HTTPError as e:
        content = e.read().decode("utf-8")
        return e.code, content

print("[1/5] Verificando estado del API Gateway en puerto 8080...")
status, body = do_request("/")
assert status == 200, f"Error respondiendo Gateway: {status}"
assert "AlumVid" in body, "El Gateway no contiene la identidad AlumVid"
print(" -> OK: API Gateway AlumVid respondiendo correctamente en puerto 8080.")

print("[2/5] Probando autenticación JWT unificada (Master Admin por cédula)...")
status, resp_str = do_request("/api/v1/auth/login", method="POST", body={
    "identification": "1700000000",
    "password": "AlumVidAdmin2026!"
})
assert status == 200, f"Error en login: {status} - {resp_str}"
auth_data = json.loads(resp_str)
token = auth_data.get("accessToken") or auth_data.get("token")
assert token, "No se recibió accessToken ni token"
print(f" -> OK: Login exitoso para {auth_data.get('fullName')}, roles: {auth_data.get('roles')}")

print("[3/5] Probando autenticación con email alternativo...")
status_email, resp_email_str = do_request("/api/v1/auth/login", method="POST", body={
    "email": "admin@alumvid.com",
    "password": "AlumVidAdmin2026!"
})
assert status_email == 200, f"Error en login por email: {status_email} - {resp_email_str}"
print(" -> OK: Login dual (por correo electronico) validado.")

print("[4/5] Probando inventario-service a través del Gateway...")
status_inv, inv_str = do_request("/api/products", method="GET", token=token)
assert status_inv == 200, f"Error obteniendo productos de inventario: {status_inv} - {inv_str}"
products = json.loads(inv_str)
print(f" -> OK: Inventario respondió vía Gateway. Productos listados: {len(products)}")

print("[5/5] Probando logistica-service (PostGIS) a través del Gateway...")
status_log, log_str = do_request("/api/v1/logistica/pedidos", method="GET", token=token)
assert status_log == 200, f"Error obteniendo pedidos de logística: {status_log} - {log_str}"
pedidos = json.loads(log_str)
print(f" -> OK: Logística PostGIS respondió vía Gateway. Pedidos en base de datos: {len(pedidos)}")

print("\n=======================================================")
print("¡TODAS LAS PRUEBAS INTEGRALES DE ALUMVID PASARON AL 100%!")
print("=======================================================")
