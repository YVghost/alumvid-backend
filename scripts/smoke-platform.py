"""Consulta la plataforma integrada sin crear datos de negocio ni imprimir secretos."""
import json
import os
from pathlib import Path
import urllib.request
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]
config = {}
if (ROOT / '.env').exists():
    for line in (ROOT / '.env').read_text(encoding='utf-8-sig').splitlines():
        if line.strip() and not line.lstrip().startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            config[key] = value.strip().strip('"').strip("'")
config.update(os.environ)
BASE = config.get('SMOKE_GATEWAY_URL', 'http://localhost:' + config.get('GATEWAY_PORT', '8080'))

def request(path, method='GET', body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            return res.status, res.read().decode()
    except HTTPError as exc:
        return exc.code, exc.read().decode()

def run():
    token = None
    checks = []
    try:
        for path in ['/', '/platform-info', '/retazos/', '/pedidos/', '/ubicaciones/', '/css/styles.css', '/js/app.js', '/maps-loader.js']:
            status, _ = request(path)
            assert status == 200, f'{path}: HTTP {status}'
            checks.append(path)
        status, _ = request('/api/v1/admin/users')
        assert status == 401, f'Sin sesion se esperaba 401, recibido {status}'
        status, body = request('/api/v1/auth/login', 'POST', {
            'identification': config['MASTER_IDENTIFICATION'], 'password': config['MASTER_PASSWORD']})
        assert status == 200, f'Login HTTP {status}; revisa las credenciales locales sin publicarlas.'
        login = json.loads(body)
        token = login.get('accessToken') or login['token']
        if login.get('mustChangePassword'):
            raise AssertionError('La cuenta de prueba necesita cambiar la contraseña temporal; hacerlo desde el portal antes del smoke.')
        for path in ['/api/v1/auth/me', '/api/v1/admin/users', '/api/products', '/api/products/movements', '/api/retazos/products', '/api/pedidos/clients', '/api/pedidos/orders', '/api/ubicaciones/spaces', '/api/v1/logistica/rutas']:
            status, _ = request(path, token=token)
            assert status == 200, f'{path}: HTTP {status}'
            checks.append(path)
        status, _ = request('/api/products/movements?from=invalid-date', token=token)
        assert status == 400, f'Fecha invalida HTTP {status}'
        print(json.dumps({'passed': True, 'checks': len(checks) + 2, 'businessDataCreated': False}, indent=2))
    finally:
        if token:
            status, _ = request('/api/v1/auth/logout', 'POST', token=token)
            assert status == 204, 'No se pudo revocar la sesion de prueba'

if __name__ == '__main__':
    run()
