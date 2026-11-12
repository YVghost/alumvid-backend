"""Verificación de punta a punta del flujo pedido -> bandeja -> ruta -> entrega.

Usa las cuentas DEMO de entrega-pruebas/estado.local.json (generadas por seed-demo.py)
y crea un pedido nuevo cada vez (no modifica los escenarios demo existentes).

    python scripts/verificar-flujo-entregas.py [http://localhost:8080]
"""
import json
import pathlib
import sys
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:8080'
STATE = json.loads((ROOT / 'entrega-pruebas' / 'estado.local.json').read_text(encoding='utf-8'))
ok = 0
fallos = []


def req(method, path, token=None, body=None):
    data = None if body is None else json.dumps(body).encode()
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {})})
    try:
        with urllib.request.urlopen(r, timeout=30) as res:
            raw = res.read().decode()
            return res.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def login(key):
    a = STATE['accounts'][key]
    s, r = req('POST', '/api/v1/auth/login', body={'identification': a['identification'], 'password': a['password']})
    assert s == 200, (key, s, r)
    return r['accessToken'], a['id']


def check(nombre, condicion, detalle=''):
    global ok
    if condicion:
        ok += 1
        print('  OK ', nombre)
    else:
        fallos.append(nombre)
        print('  FALLA', nombre, detalle)


admin, _ = login('ADMIN')
ventas, _ = login('VENTAS')
bodega, _ = login('BODEGA')
chofer1, chofer1_id = login('CHOFER1')
chofer2, chofer2_id = login('CHOFER2')
# Conductor de la ruta de prueba: DEMO-MULTI (tiene rol CHOFER y no suele estar en ruta).
conductor, conductor_id = login('MULTI')
tornillo = STATE['steps']['product:TOR']['id']
cliente = STATE['steps']['client:1']['id']

print('Seguridad y limpieza')
check('logística sin token -> 401', req('GET', '/api/v1/logistica/rutas')[0] == 401)
check('panel web eliminado (/ -> 404)', req('GET', '/')[0] == 404)
check('chofer no ve rutas de otro chofer -> 403', req('GET', f'/api/v1/logistica/choferes/{chofer2_id}/rutas', chofer1)[0] == 403)
check('vendedor no planifica rutas -> 403', req('GET', '/api/v1/logistica/rutas', ventas)[0] == 403)
check('salida manual de stock -> 409', req('POST', f'/api/products/{tornillo}/movements', admin,
      {'requestId': str(uuid.uuid4()), 'type': 'SALIDA', 'quantity': 1, 'reason': 'prueba'})[0] == 409)
check('administrador (no maestro) ve auditoría', req('GET', '/api/v1/admin/audit', admin)[0] == 200)

print('Pedido con entrega -> bandeja')
s, creado = req('POST', '/api/pedidos/orders', ventas, {
    'requestId': str(uuid.uuid4()), 'clientId': cliente, 'deliveryMode': 'ENTREGA',
    'deliveryAddress': 'Av. Amazonas y Naciones Unidas, Quito', 'receiverName': 'Recepción',
    'deliveryLatitude': -0.1762, 'deliveryLongitude': -78.4847, 'externallyConfirmed': True,
    'lines': [{'productId': tornillo, 'quantity': '2', 'unitPrice': '1.50'}]})
check('vendedor crea pedido con ubicación', s == 200, creado)
pedido = creado['order']['id']
numero = creado['order']['number']
s, bandeja = req('GET', '/api/pedidos/deliveries/pending', admin)
fila = next((x for x in bandeja if x['id'] == pedido), None)
check('aparece en la bandeja aún sin preparar', fila is not None and float(fila['ready_quantity']) == 0, fila)
s, r = req('POST', '/api/v1/logistica/rutas', admin, {'choferId': conductor_id, 'pedidos': [{'pedidoId': pedido}]})
check('no se despacha sin preparar (409 con mensaje)', s == 409 and 'preparado' in str(r), r)
s, r = req('POST', f'/api/pedidos/orders/{pedido}/prepare', bodega, {'requestId': str(uuid.uuid4()), 'reason': 'Preparado en bodega'})
check('bodega prepara el pedido completo', s == 200, r)
s, bandeja = req('GET', '/api/pedidos/deliveries/pending', admin)
fila = next((x for x in bandeja if x['id'] == pedido), None)
check('queda listo para ruta', fila is not None and float(fila['ready_quantity']) == 2, fila)

print('Choferes y ruta')
s, choferes = req('GET', '/api/v1/logistica/choferes', admin)
estados = {c['id']: c['estadoDisponibilidad'] for c in choferes}
check('choferes con disponibilidad calculada', s == 200 and estados.get(conductor_id) == 'DISPONIBLE', estados)
ocupado = next((i for i in (chofer1_id, chofer2_id) if estados.get(i) == 'EN_RUTA'), None)
if ocupado:
    s, r = req('POST', '/api/v1/logistica/rutas', admin, {'choferId': ocupado, 'pedidos': []})
    check('chofer en ruta no recibe ruta nueva (409)', s == 409 and 'en ruta' in str(r), r)
s, ruta = req('POST', '/api/v1/logistica/rutas', admin, {'codigoRuta': f'VERIF-{numero}', 'choferId': conductor_id,
                                                           'comentarios': 'Verificación', 'pedidos': [{'pedidoId': pedido}]})
check('ruta creada con el pedido', s == 201 and len(ruta['paradas']) == 1, ruta)
parada = ruta['paradas'][0]
check('la parada trae la carga (manifiesto)', len(parada.get('carga') or []) == 1 and float(parada['carga'][0]['quantity']) == 2, parada.get('carga'))
s, pedido_det = req('GET', f'/api/pedidos/orders/{pedido}', admin)
check('pedido queda EN_REPARTO con envío', pedido_det['order']['state'] == 'EN_REPARTO' and len(pedido_det['shipments']) == 1, pedido_det['order']['state'])

linea = pedido_det['lines'][0]['id']
s, r = req('PUT', f"/api/v1/logistica/rutas/{ruta['id']}/destinos/{parada['id']}/carga", admin, {'lineas': [{'lineId': linea, 'quantity': 1}]})
check('modificar carga a 1 unidad', s == 200 and float(r['paradas'][0]['carga'][0]['quantity']) == 1, r)
parada = r['paradas'][0]
s, r = req('DELETE', f"/api/v1/logistica/rutas/{ruta['id']}/destinos/{parada['id']}", admin)
check('quitar parada de ruta pendiente', s == 200 and len(r['paradas']) == 0, r)
s, bandeja = req('GET', '/api/pedidos/deliveries/pending', admin)
fila = next((x for x in bandeja if x['id'] == pedido), None)
check('el material vuelve a la bandeja', fila is not None and float(fila['ready_quantity']) == 2, fila)
s, r = req('POST', f"/api/v1/logistica/rutas/{ruta['id']}/pedidos", admin, {'pedidos': [{'pedidoId': pedido}]})
check('agregar el pedido de nuevo', s == 200 and len(r['paradas']) == 1, r)
parada = r['paradas'][0]

print('Operación del chofer')
s, r = req('POST', f"/api/v1/logistica/despachos/{parada['id']}/aceptar-inicio", chofer1)
check('otro chofer no opera la parada (403)', s == 403, r)
s, r = req('POST', f"/api/v1/logistica/despachos/{parada['id']}/aceptar-inicio", conductor)
check('chofer inicia la parada (ruta pasa a EN_CURSO)', s == 200 and r['estado'] == 'EN_CURSO', r)
s, r = req('PUT', f"/api/v1/logistica/rutas/{ruta['id']}/chofer", admin, {'choferId': chofer2_id})
check('no se cambia chofer en curso (409)', s == 409, r)
s, r = req('POST', f"/api/v1/logistica/despachos/{parada['id']}/cerrar-entrega", conductor, {
    'fotoPodUrl': 'data:image/png;base64,iVBORw0KGgo=', 'firmaUrl': 'data:image/png;base64,iVBORw0KGgo=',
    'latitud': -0.1762, 'longitud': -78.4847, 'comentarios': 'Verificación automática'})
check('entrega con evidencia', s == 200 and r['estado'] == 'ENTREGADO', r)
s, r = req('GET', f"/api/v1/logistica/rutas/{ruta['id']}", admin)
check('la ruta se completa sola', r['estado'] == 'COMPLETADA', r.get('estado'))
s, r = req('GET', f'/api/pedidos/orders/{pedido}', admin)
check('pedido ENTREGADO en pedidos', r['order']['state'] == 'ENTREGADO', r['order']['state'])

print('Inventario y retazos')
s, r = req('GET', '/api/retazos/pieces?kind=ALUMINIO&minLengthM=3', bodega)
check('buscar piezas por medida', s == 200 and all(float(x['lengthM']) >= 3 for x in r['items']) and r['items'], r)
if s == 200 and r['items']:
    s, f = req('GET', f"/api/retazos/pieces/{r['items'][0]['id']}", ventas)
    check('ficha de pieza (medidas, ubicación, producto)', s == 200 and f['piece']['location'] and f['product']['name'], f)

for t in [admin, ventas, bodega, chofer1, chofer2, conductor]:
    req('POST', '/api/v1/auth/logout', t)
print(f'\n{ok} verificaciones correctas, {len(fallos)} fallas')
sys.exit(1 if fallos else 0)
